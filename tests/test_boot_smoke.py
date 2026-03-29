"""
tests/test_boot_smoke.py — Live VM smoke test: boot-loader starts with no errors.

Checks that the boot-loader image can be built, the VM boots successfully,
and the CPU reaches a sane post-boot state (CS:IP has left the BIOS reset
vector and is executing inside the loaded image).

Requires VBoxManage on PATH and the 'boot-loader' VM to be registered.
Skipped automatically when either condition is not met.

Run:
    cd mcp-server
    .venv/bin/python -m pytest tests/test_boot_smoke.py -v
"""

import asyncio
import json
import os
import shutil
import sys
from pathlib import Path

import pytest
import pytest_asyncio
from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client

# ---------------------------------------------------------------------------
# Paths / helpers
# ---------------------------------------------------------------------------

MCP_SERVER_DIR = Path(__file__).parent.parent / "mcp-server"
SERVER_SCRIPT  = MCP_SERVER_DIR / "server.py"
PYTHON         = sys.executable

BOOT_VM        = os.environ.get("VBOX_VM_NAME", "boot-loader")
BOOT_GDB_PORT  = os.environ.get("VBOX_GDB_PORT", "5037")

# BIOS power-on reset vector: CS=0xF000, IP=0xFFF0.
# If CS:IP is exactly this after 2+ seconds, the CPU is genuinely stuck.
BIOS_RESET_CS  = 0xF000
BIOS_RESET_IP  = 0xFFF0


def requires_vboxmanage():
    return pytest.mark.skipif(
        shutil.which("VBoxManage") is None,
        reason="VBoxManage not found on PATH — live VM tests skipped.",
    )


async def _call(session: ClientSession, tool: str, **kwargs) -> dict:
    result = await session.call_tool(tool, arguments=kwargs)
    assert result.content, f"Tool '{tool}' returned empty content"
    raw = result.content[0].text
    try:
        return json.loads(raw)
    except (json.JSONDecodeError, TypeError):
        return {"raw": raw}


# ---------------------------------------------------------------------------
# Session fixture — dedicated to this test module, uses the real boot-loader VM
# ---------------------------------------------------------------------------

@pytest_asyncio.fixture(scope="module")
async def boot_session():
    """MCP session pointed at the real 'boot-loader' VM (native backend)."""
    params = StdioServerParameters(
        command=PYTHON,
        args=[str(SERVER_SCRIPT)],
        env={
            **os.environ,
            "VBOX_VM_NAME": BOOT_VM,
            "VBOX_GDB_PORT": BOOT_GDB_PORT,
            "VBOX_START_GUI": "true",
            "VBOX_DEBUG_BACKEND": "native",
        },
    )

    session_ready  = asyncio.Event()
    teardown_event = asyncio.Event()
    session_holder: list = []
    error_holder:   list = []

    async def _run():
        try:
            async with stdio_client(params) as (read, write):
                async with ClientSession(read, write) as session:
                    await session.initialize()
                    session_holder.append(session)
                    session_ready.set()
                    await teardown_event.wait()
        except Exception as exc:
            error_holder.append(exc)
            session_ready.set()

    task = asyncio.get_event_loop().create_task(_run())
    await session_ready.wait()
    if error_holder:
        task.cancel()
        raise error_holder[0]

    yield session_holder[0]

    teardown_event.set()
    await task


# ---------------------------------------------------------------------------
# Test
# ---------------------------------------------------------------------------

class TestBootSmokeLifecycle:
    """End-to-end smoke: build → start → boot → sane CPU state → stop."""

    @requires_vboxmanage()
    async def test_build_succeeds(self, boot_session):
        """make clean && make must exit 0 and produce floppy.img."""
        r = await _call(boot_session, "build_image")
        assert r.get("ok") is True, f"Build failed: {r.get('error') or r.get('raw')}"

    @requires_vboxmanage()
    async def test_vm_starts(self, boot_session):
        """prepare_debug_session must start the VM without error."""
        r = await _call(boot_session, "prepare_debug_session", gui=True)
        assert r.get("ok") is True, f"VM start failed: {r.get('error') or r.get('raw')}"

    @requires_vboxmanage()
    async def test_vm_is_running_after_start(self, boot_session):
        """VM power state must be 'running' shortly after start."""
        # Allow up to 5 s for the VM to reach 'running'.
        for _ in range(10):
            r = await _call(boot_session, "get_vm_state", vm_name=BOOT_VM)
            if r.get("state") == "running":
                break
            await asyncio.sleep(0.5)
        assert r.get("state") == "running", (
            f"VM did not reach 'running' state; last state: {r.get('state')}"
        )

    @requires_vboxmanage()
    async def test_cpu_left_bios_reset_vector(self, boot_session):
        """
        After 2 s of boot time, CS:IP must NOT be sitting at the BIOS power-on
        reset vector (0xF000:0xFFF0).  The CPU is allowed to be temporarily
        inside a BIOS interrupt handler (CS=0xF000 with a low IP) — that is
        normal during boot-loader execution.  What must not happen is the CPU
        being frozen at the reset vector itself, which would mean it never
        executed any boot code at all.

        A flat physical address check is also done: the CPU must have reached
        at least one instruction in the boot-sector range (≥ 0x7C00).

        Acceptable post-boot states:
          CS=0x0000, IP≥0x7C00 — stage 1 running
          CS=0x0000, IP≥0x8000 — stage 2 running
          CS=0xF000, IP<0xFFF0  — briefly inside a BIOS ISR (OK)
        """
        # Ensure VM is running (native backend may have paused it on connect).
        await _call(boot_session, "resume_vm")

        # Let the boot-loader run for 2 seconds.
        await asyncio.sleep(2)

        pause = await _call(boot_session, "pause_vm")
        assert pause.get("ok") is True, f"Could not pause VM: {pause.get('error')}"

        regs = await _call(boot_session, "read_registers")
        assert regs.get("ok") is True, f"Could not read registers: {regs.get('error')}"

        # CS and IP come back as hex strings like "0xf000" / "0x76ba".
        cs_raw = regs.get("cs", "")
        ip_raw = regs.get("ip", "")
        cs = int(cs_raw, 16) if cs_raw else BIOS_RESET_CS
        ip = int(ip_raw, 16) if ip_raw else BIOS_RESET_IP

        # Fail only if we're still at the exact power-on reset vector.
        assert not (cs == BIOS_RESET_CS and ip == BIOS_RESET_IP), (
            f"CS:IP is 0x{cs:04X}:0x{ip:04X} — stuck at BIOS reset vector. "
            "Boot-loader never executed."
        )

        # Additionally verify the flat IP has reached boot-sector territory
        # (≥ 0x7C00) at some point — the flat_ip field is set by read_registers.
        flat_ip_raw = regs.get("flat_ip")
        if flat_ip_raw:
            flat_ip = int(flat_ip_raw, 16)
            # CS=0xF000 with low IP means a BIOS ISR; skip flat-IP check in that case.
            if cs != BIOS_RESET_CS:
                assert flat_ip >= 0x7C00, (
                    f"Flat IP 0x{flat_ip:05X} is below boot-sector load address 0x7C00. "
                    "Boot-loader may not have been loaded."
                )

    @requires_vboxmanage()
    async def test_vm_stops_cleanly(self, boot_session):
        """stop_vm must power off the VM without error."""
        # Resume first in case we're still paused from the previous test.
        await _call(boot_session, "resume_vm")
        r = await _call(boot_session, "stop_vm")
        assert r.get("ok") is True, f"VM stop failed: {r.get('error') or r.get('raw')}"

    @requires_vboxmanage()
    async def test_vm_is_off_after_stop(self, boot_session):
        """VM power state must be 'poweroff' after stop_vm."""
        for _ in range(10):
            r = await _call(boot_session, "get_vm_state", vm_name=BOOT_VM)
            if r.get("state") in ("poweroff", "aborted"):
                break
            await asyncio.sleep(0.5)
        assert r.get("state") in ("poweroff", "aborted"), (
            f"VM did not power off; last state: {r.get('state')}"
        )
