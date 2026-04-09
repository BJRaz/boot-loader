"""
tests/test_qemu_smoke.py — Live QEMU smoke test: boot-loader boots successfully.

Checks that the boot-loader image can be built, QEMU starts, the CPU leaves
the BIOS reset vector, and the boot-loader executes inside its expected
address range.

Skipped automatically when qemu-system-i386 is not on PATH.

Run:
    cd mcp-server
    .venv/bin/python -m pytest ../tests/test_qemu_smoke.py -v -s
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
# Paths
# ---------------------------------------------------------------------------

MCP_SERVER_DIR = Path(__file__).parent.parent / "mcp-server"
SERVER_SCRIPT  = MCP_SERVER_DIR / "server.py"
PYTHON         = sys.executable

GDB_PORT = int(os.environ.get("QEMU_GDB_PORT", "15037"))

BIOS_RESET_CS = 0xF000
BIOS_RESET_IP = 0xFFF0

requires_qemu = pytest.mark.skipif(
    shutil.which("qemu-system-i386") is None,
    reason="qemu-system-i386 not found on PATH — QEMU smoke tests skipped.",
)

requires_gdb = pytest.mark.skipif(
    shutil.which("gdb") is None,
    reason="gdb not found on PATH — GDB connection tests skipped.",
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
# Session fixture
# ---------------------------------------------------------------------------

@pytest_asyncio.fixture(scope="module")
async def qemu_session():
    """MCP session with HYPERVISOR=qemu."""
    params = StdioServerParameters(
        command=PYTHON,
        args=[str(SERVER_SCRIPT)],
        env={
            **os.environ,
            "HYPERVISOR": "qemu",
            "VBOX_GDB_PORT": str(GDB_PORT),
            "QEMU_DISPLAY": "none",
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

    # Ensure VM is stopped on teardown.
    try:
        await _call(session_holder[0], "stop_vm")
    except Exception:
        pass
    teardown_event.set()
    await task


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

class TestQemuBootSmoke:
    """Build → QEMU start → GDB connect → CPU left reset vector → stop."""

    @requires_qemu
    async def test_build_succeeds(self, qemu_session):
        """make must exit 0 and produce floppy.img."""
        r = await _call(qemu_session, "build_image")
        assert r.get("ok") is True, f"Build failed: {r.get('stderr') or r.get('error') or r}"

    @requires_qemu
    async def test_qemu_starts(self, qemu_session):
        """prepare_debug_session must launch QEMU and report ok."""
        r = await _call(qemu_session, "prepare_debug_session",
                        gdb_port=GDB_PORT, display="none")
        assert r.get("ok") is True, f"QEMU start failed: {r.get('error') or r}"

    @requires_qemu
    async def test_vm_is_running(self, qemu_session):
        """get_vm_state must report 'running' after start."""
        r = await _call(qemu_session, "get_vm_state")
        assert r.get("state") == "running", f"Unexpected state: {r.get('state')} — {r}"

    @requires_qemu
    @requires_gdb
    async def test_gdb_connects(self, qemu_session):
        """connect_gdb must establish a GDB session."""
        r = await _call(qemu_session, "connect_gdb",
                        host="localhost", port=GDB_PORT)
        assert r.get("ok") is True, f"GDB connect failed: {r.get('error') or r}"

    @requires_qemu
    @requires_gdb
    async def test_cpu_left_bios_reset_vector(self, qemu_session):
        """
        Set a breakpoint at the stage-1 entry point (0x7C00), resume the CPU,
        and verify it stops there — proving the boot-loader was loaded and
        executed (i.e. the CPU left the BIOS reset vector).
        """
        # Set a breakpoint at the boot-sector load address.
        r = await _call(qemu_session, "set_breakpoint", flat_addr=0x7C00)
        assert r.get("ok") is True, f"set_breakpoint failed: {r.get('error') or r}"

        # Resume the CPU (QEMU started halted with -S).
        r = await _call(qemu_session, "continue_execution")
        assert r.get("ok") is True, f"continue_execution failed: {r.get('error') or r}"

        # Give the CPU time to reach 0x7C00 (should be almost instant).
        await asyncio.sleep(3)

        regs = await _call(qemu_session, "read_registers")
        assert regs.get("ok") is True, f"read_registers failed: {regs.get('error') or regs}"

        cs_raw = regs.get("cs", "")
        ip_raw = regs.get("ip", "")
        cs = int(cs_raw, 16) if cs_raw else BIOS_RESET_CS
        ip = int(ip_raw, 16) if ip_raw else BIOS_RESET_IP

        assert not (cs == BIOS_RESET_CS and ip == BIOS_RESET_IP), (
            f"CS:IP is 0x{cs:04X}:0x{ip:04X} — stuck at BIOS reset vector. "
            "Boot-loader never executed."
        )

    @requires_qemu
    async def test_qemu_stops_cleanly(self, qemu_session):
        """stop_vm must terminate QEMU without error."""
        r = await _call(qemu_session, "stop_vm")
        assert r.get("ok") is True, f"stop_vm failed: {r.get('error') or r}"

    @requires_qemu
    async def test_vm_is_off_after_stop(self, qemu_session):
        """get_vm_state must report 'poweroff' after stop."""
        r = await _call(qemu_session, "get_vm_state")
        assert r.get("state") == "poweroff", f"Unexpected state: {r.get('state')} — {r}"
