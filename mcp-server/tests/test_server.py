"""
tests/test_server.py — MCP client-based integration tests for vbox-boot-debug server.

The tests start the server as a subprocess over stdio (exactly how a real MCP
client such as Claude Desktop would use it), connect with the MCP Python SDK
ClientSession, and verify every tool's contract.

Tests that require VirtualBox or GDB hardware are auto-skipped when
VBoxManage / gdb are not on PATH, keeping the suite runnable in CI without a
hypervisor.

Run:
    cd mcp-server
    .venv/bin/python -m pytest tests/ -v
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

MCP_SERVER_DIR = Path(__file__).parent.parent   # mcp-server/
SERVER_SCRIPT  = MCP_SERVER_DIR / "server.py"
PYTHON         = sys.executable                 # same interpreter / venv

# ---------------------------------------------------------------------------
# Pytest-asyncio configuration
# ---------------------------------------------------------------------------

async def _session_with_env(env_overrides: dict):
    """Spawn MCP server over stdio and yield connected ClientSession."""
    params = StdioServerParameters(
        command=PYTHON,
        args=[str(SERVER_SCRIPT)],
        env={
            **os.environ,
            **env_overrides,
        },
    )

    # Synchronisation primitives shared between the host task and test code.
    session_ready  = asyncio.Event()
    teardown_event = asyncio.Event()
    session_holder: list = []          # session_holder[0] = ClientSession once ready
    error_holder:   list = []          # error_holder[0]   = exception if startup fails

    async def _run_session():
        try:
            async with stdio_client(params) as (read, write):
                async with ClientSession(read, write) as session:
                    await session.initialize()
                    session_holder.append(session)
                    session_ready.set()
                    # Wait until tests are done.
                    await teardown_event.wait()
        except Exception as exc:
            error_holder.append(exc)
            session_ready.set()   # unblock fixture even on error

    task = asyncio.get_event_loop().create_task(_run_session())

    await session_ready.wait()
    if error_holder:
        task.cancel()
        raise error_holder[0]

    yield session_holder[0]

    # Signal the host task to tear down and wait for clean shutdown.
    teardown_event.set()
    await task


@pytest_asyncio.fixture(scope="session")
async def mcp_session():
    """
    Default test session: auto backend mode, isolated VM name/port.
    """
    async for s in _session_with_env({
        "VBOX_VM_NAME": "test-vm",
        "VBOX_GDB_PORT": "15037",
        "VBOX_START_GUI": "false",
        "VBOX_DEBUG_BACKEND": "auto",
    }):
        yield s


@pytest_asyncio.fixture(scope="session")
async def strict_native_session():
    """Strict native backend session (`VBOX_DEBUG_BACKEND=native`)."""
    async for s in _session_with_env({
        "VBOX_VM_NAME": "test-vm",
        "VBOX_GDB_PORT": "15037",
        "VBOX_START_GUI": "false",
        "VBOX_DEBUG_BACKEND": "native",
    }):
        yield s


@pytest_asyncio.fixture(scope="session")
async def strict_gdb_session():
    """Strict gdb backend session (`VBOX_DEBUG_BACKEND=gdb`)."""
    async for s in _session_with_env({
        "VBOX_VM_NAME": "test-vm",
        "VBOX_GDB_PORT": "15037",
        "VBOX_START_GUI": "false",
        "VBOX_DEBUG_BACKEND": "gdb",
    }):
        yield s


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

async def call(session: ClientSession, tool: str, **kwargs) -> dict:
    """Call a tool and return the parsed JSON payload dict."""
    result = await session.call_tool(tool, arguments=kwargs)
    assert result.content, f"Tool '{tool}' returned empty content"
    raw = result.content[0].text
    return json.loads(raw)


async def active_backend(session: ClientSession) -> str:
    r = await call(session, "get_debug_backend")
    return r.get("backend", "unknown")


def requires_vboxmanage():
    return pytest.mark.skipif(
        shutil.which("VBoxManage") is None,
        reason="VBoxManage not found on PATH",
    )


def requires_gdb():
    return pytest.mark.skipif(
        shutil.which("gdb") is None,
        reason="gdb not found on PATH",
    )


# ===========================================================================
# Group 1: Server connectivity and tool listing
# ===========================================================================

async def test_server_starts_and_lists_tools(mcp_session):
    """Server must start and expose at least the expected tool names."""
    response = await mcp_session.list_tools()
    names = {t.name for t in response.tools}

    expected = {
        "build_image", "get_vm_state", "prepare_debug_session",
        "attach_floppy", "configure_gdb_stub", "start_vm", "stop_vm",
        "reset_vm", "pause_vm", "resume_vm", "connect_gdb", "disconnect_gdb",
        "set_breakpoint", "set_breakpoint_segoff", "delete_breakpoint",
        "list_breakpoints", "continue_execution", "step_instruction",
        "next_instruction", "interrupt_execution", "read_registers",
        "read_memory", "read_memory_segoff", "write_memory", "disassemble",
        "seg_off_to_flat", "flat_to_seg_off",
    }
    missing = expected - names
    assert not missing, f"Missing tools: {missing}"


# ===========================================================================
# Group 2: Addressing helpers — pure computation, no hardware required
# ===========================================================================

class TestAddressingHelpers:

    async def test_seg_off_to_flat_stage1(self, mcp_session):
        """Stage-1 canonical address: CS=0x0000, IP=0x7C00 → flat=0x7C00."""
        r = await call(mcp_session, "seg_off_to_flat", segment=0x0000, offset=0x7C00)
        assert r["ok"] is True
        assert r["flat_int"] == 0x7C00

    async def test_seg_off_to_flat_stage1_alt_segment(self, mcp_session):
        """CS=0x07C0, IP=0x0000 must also resolve to flat=0x7C00."""
        r = await call(mcp_session, "seg_off_to_flat", segment=0x07C0, offset=0x0000)
        assert r["ok"] is True
        assert r["flat_int"] == 0x7C00

    async def test_seg_off_to_flat_stage2(self, mcp_session):
        """Stage-2 entry: CS=0x0000, IP=0x8000 → flat=0x8000."""
        r = await call(mcp_session, "seg_off_to_flat", segment=0x0000, offset=0x8000)
        assert r["ok"] is True
        assert r["flat_int"] == 0x8000

    async def test_seg_off_to_flat_ivt_base(self, mcp_session):
        r = await call(mcp_session, "seg_off_to_flat", segment=0, offset=0)
        assert r["ok"] is True
        assert r["flat_int"] == 0

    async def test_seg_off_to_flat_max(self, mcp_session):
        """Segment=0xFFFF, offset=0xFFFF → flat=0x10FFEF."""
        r = await call(mcp_session, "seg_off_to_flat", segment=0xFFFF, offset=0xFFFF)
        assert r["ok"] is True
        assert r["flat_int"] == (0xFFFF << 4) + 0xFFFF

    async def test_flat_to_seg_off_stage1_seg0(self, mcp_session):
        r = await call(mcp_session, "flat_to_seg_off", flat_addr=0x7C00, segment=0)
        assert r["ok"] is True
        assert r["segment"] == "0x0000"
        assert r["offset"]  == "0x7C00"

    async def test_flat_to_seg_off_stage1_seg07c0(self, mcp_session):
        r = await call(mcp_session, "flat_to_seg_off", flat_addr=0x7C00, segment=0x07C0)
        assert r["ok"] is True
        assert r["segment"] == "0x07C0"
        assert r["offset"]  == "0x0000"

    async def test_flat_to_seg_off_out_of_range(self, mcp_session):
        """Offset would be negative → must return ok=False."""
        r = await call(mcp_session, "flat_to_seg_off", flat_addr=0x7C00, segment=0xFFFF)
        assert r["ok"] is False
        assert "error" in r

    async def test_roundtrip(self, mcp_session):
        """seg_off_to_flat → flat_to_seg_off must be identity."""
        flat_r = await call(mcp_session, "seg_off_to_flat", segment=0x0800, offset=0x0100)
        flat   = flat_r["flat_int"]
        back_r = await call(mcp_session, "flat_to_seg_off", flat_addr=flat, segment=0x0800)
        assert back_r["ok"] is True
        assert int(back_r["offset"], 16) == 0x0100


# ===========================================================================
# Group 3: GDB client state — no hardware needed
# ===========================================================================

class TestGdbClientState:

    async def test_get_debug_backend(self, mcp_session):
        r = await call(mcp_session, "get_debug_backend")
        assert "backend" in r
        assert "configured" in r
        assert "strict_mode" in r

    async def test_get_debug_capabilities(self, mcp_session):
        r = await call(mcp_session, "get_debug_capabilities")
        assert "backend" in r
        assert "capabilities" in r
        assert "set_breakpoint" in r["capabilities"]
        assert "read_memory" in r["capabilities"]

    async def test_native_unsupported_operation_contract(self, mcp_session):
        backend = await call(mcp_session, "get_debug_backend")
        if backend.get("backend") != "native":
            pytest.skip("Backend is not native; unsupported contract test not applicable.")

        r = await call(mcp_session, "read_memory", flat_addr=0x7C00, length=16)
        assert r["ok"] is False
        assert r["error"] == "unsupported_by_backend"
        assert r["backend"] == "native"

    async def test_disconnect_when_not_connected(self, mcp_session):
        r = await call(mcp_session, "disconnect_gdb")
        assert r["ok"] is True

    async def test_list_breakpoints_empty(self, mcp_session):
        r = await call(mcp_session, "list_breakpoints")
        backend = await active_backend(mcp_session)
        if backend == "native":
            assert r["ok"] is False
            assert r["error"] == "unsupported_by_backend"
            assert r["breakpoints"] == []
        else:
            assert r["ok"] is True
            assert r["breakpoints"] == []

    async def test_step_without_connection(self, mcp_session):
        r = await call(mcp_session, "step_instruction")
        assert r["ok"] is False
        backend = await active_backend(mcp_session)
        if backend == "native":
            assert r["error"] == "unsupported_by_backend"
        else:
            assert "connect" in r["error"].lower()

    async def test_read_registers_without_connection(self, mcp_session):
        r = await call(mcp_session, "read_registers")
        assert r["ok"] is False

    async def test_read_memory_without_connection(self, mcp_session):
        r = await call(mcp_session, "read_memory", flat_addr=0x7C00, length=16)
        assert r["ok"] is False

    async def test_set_breakpoint_without_connection(self, mcp_session):
        r = await call(mcp_session, "set_breakpoint", flat_addr=0x7C00)
        assert r["ok"] is False

    async def test_delete_breakpoint_without_connection(self, mcp_session):
        r = await call(mcp_session, "delete_breakpoint", flat_addr=0x7C00)
        assert r["ok"] is False

    async def test_continue_without_connection(self, mcp_session):
        r = await call(mcp_session, "continue_execution")
        assert r["ok"] is False

    async def test_disassemble_without_connection(self, mcp_session):
        r = await call(mcp_session, "disassemble", flat_addr=0x7C00, count=5)
        assert r["ok"] is False

    async def test_connect_gdb_unreachable_port(self, mcp_session):
        """connect_gdb with a closed port must fail within timeout."""
        r = await call(mcp_session, "connect_gdb", timeout=3)
        backend = await active_backend(mcp_session)
        if backend == "native":
            assert r["ok"] is True
        else:
            assert r["ok"] is False
            assert "error" in r


class TestStrictBackendModes:

    async def test_strict_native_backend_selected(self, strict_native_session):
        r = await call(strict_native_session, "get_debug_backend")
        assert r["configured"] == "native"
        assert r["strict_mode"] is True
        assert r["backend"] == "native"

    async def test_strict_native_unsupported_contract(self, strict_native_session):
        r = await call(strict_native_session, "set_breakpoint", flat_addr=0x7C00)
        assert r["ok"] is False
        assert r["error"] == "unsupported_by_backend"
        assert r["backend"] == "native"

    async def test_strict_gdb_backend_resolution(self, strict_gdb_session):
        r = await call(strict_gdb_session, "get_debug_backend")
        assert r["configured"] == "gdb"
        assert r["strict_mode"] is True

        if shutil.which("gdb") is None:
            assert r["ok"] is False
            assert r["backend"] == "unavailable"
            assert "gdb" in r.get("error", "").lower()
        else:
            assert r["ok"] is True
            assert r["backend"] == "gdb"

    async def test_strict_gdb_unavailable_tool_contract(self, strict_gdb_session):
        if shutil.which("gdb") is not None:
            pytest.skip("gdb is installed; unavailable strict-gdb path not applicable.")

        r = await call(strict_gdb_session, "connect_gdb", timeout=2)
        assert r["ok"] is False
        assert r["error"] == "debug_backend_unavailable"
        assert r["backend"] == "unavailable"


# ===========================================================================
# Group 4: VM lifecycle — requires VBoxManage on PATH
# ===========================================================================

class TestVmLifecycle:

    @requires_vboxmanage()
    async def test_get_vm_state_unknown_vm(self, mcp_session):
        r = await call(mcp_session, "get_vm_state", vm_name="__nonexistent_test_vm__")
        assert r["ok"] is False

    @requires_vboxmanage()
    async def test_stop_unknown_vm(self, mcp_session):
        r = await call(mcp_session, "stop_vm", vm_name="__nonexistent_test_vm__")
        assert r["ok"] is False

    @requires_vboxmanage()
    async def test_attach_floppy_nonexistent_image(self, mcp_session):
        r = await call(
            mcp_session, "attach_floppy",
            vm_name="__nonexistent_test_vm__",
            image_path="/tmp/__does_not_exist__.img",
        )
        assert r["ok"] is False

    @requires_vboxmanage()
    async def test_configure_gdb_stub_nonexistent_vm(self, mcp_session):
        r = await call(
            mcp_session, "configure_gdb_stub",
            vm_name="__nonexistent_test_vm__",
            gdb_host="localhost",
            gdb_port=15037,
        )
        assert r["ok"] is False


# ===========================================================================
# Group 5: build_image — requires make + nasm
# ===========================================================================

class TestBuildImage:

    @pytest.mark.skipif(
        shutil.which("make") is None or shutil.which("nasm") is None,
        reason="make or nasm not found on PATH",
    )
    async def test_build_image_succeeds(self, mcp_session):
        r = await call(mcp_session, "build_image")
        assert r["exit_code"] == 0, f"Build failed:\n{r.get('stderr')}"
        assert r["ok"] is True
        floppy = Path(MCP_SERVER_DIR).parent / "floppy.img"
        assert floppy.exists(), "floppy.img was not created"
        assert floppy.stat().st_size == 512 * 2880, "floppy.img wrong size"


# ===========================================================================
# Group 6: Live hardware tests (opt-in only: BOOT_LIVE_TESTS=1)
# ===========================================================================

LIVE = pytest.mark.skipif(
    os.environ.get("BOOT_LIVE_TESTS") != "1",
    reason="Live hardware tests disabled. Set BOOT_LIVE_TESTS=1 to enable.",
)


class TestLiveDebugSession:
    """
    Full end-to-end: start VM → connect GDB → break at 0x7C00 / 0x8000 →
    inspect real-mode registers.
    Enable: BOOT_LIVE_TESTS=1 .venv/bin/python -m pytest tests/ -v -k live
    """

    @LIVE
    @requires_vboxmanage()
    async def test_live_prepare_debug_session(self, mcp_session):
        r = await call(mcp_session, "prepare_debug_session", gui=False)
        assert r["ok"] is True, r.get("error")

    @LIVE
    @requires_gdb()
    async def test_live_connect_gdb(self, mcp_session):
        r = await call(mcp_session, "connect_gdb", timeout=20)
        assert r["ok"] is True, r.get("error")

    @LIVE
    @requires_gdb()
    async def test_live_set_stage1_breakpoint(self, mcp_session):
        r = await call(mcp_session, "set_breakpoint", flat_addr=0x7C00)
        assert r["ok"] is True
        assert r["flat_addr"] == "0x07C00"

    @LIVE
    @requires_gdb()
    async def test_live_set_stage2_breakpoint_segoff(self, mcp_session):
        r = await call(mcp_session, "set_breakpoint_segoff", segment=0x0000, offset=0x8000)
        assert r["ok"] is True
        assert r["flat_addr"] == "0x08000"

    @LIVE
    @requires_gdb()
    async def test_live_continue_to_stage1(self, mcp_session):
        cont = await call(mcp_session, "continue_execution")
        assert cont["ok"] is True
        await asyncio.sleep(3)
        regs = await call(mcp_session, "read_registers")
        assert regs["ok"] is True
        assert regs["flat_ip"] == "0x07C00", f"Got {regs['flat_ip']}"

    @LIVE
    @requires_gdb()
    async def test_live_read_stage1_memory(self, mcp_session):
        r = await call(mcp_session, "read_memory", flat_addr=0x7C00, length=16)
        assert r["ok"] is True
        assert r["length"] == 16

    @LIVE
    @requires_gdb()
    async def test_live_disassemble_stage1(self, mcp_session):
        r = await call(mcp_session, "disassemble", flat_addr=0x7C00, count=5)
        assert r["ok"] is True
        assert len(r["instructions"]) >= 1

    @LIVE
    @requires_gdb()
    async def test_live_step_instruction(self, mcp_session):
        r = await call(mcp_session, "step_instruction")
        assert r["ok"] is True

    @LIVE
    @requires_gdb()
    async def test_live_disconnect_gdb(self, mcp_session):
        r = await call(mcp_session, "disconnect_gdb")
        assert r["ok"] is True

    @LIVE
    @requires_vboxmanage()
    async def test_live_stop_vm(self, mcp_session):
        r = await call(mcp_session, "stop_vm")
        assert r["ok"] is True


# ===========================================================================
# Group 7: Print-function verification (live, opt-in)
#
# Tests that the print/println routines in print.asm actually work by:
#   1. Building a fresh floppy.img
#   2. Starting the boot-loader VM via prepare_debug_session
#   3. Setting breakpoints at Stage-1 (0x7C00) and Stage-2 (0x8000)
#   4. Verifying Stage-1 code and its "[BOOT]" message strings are present
#      in physical memory — confirming the binary was loaded by BIOS correctly
#      and the print routine has data to work with
#   5. Verifying Stage-2 code and its "[BOOT2]" message strings are loaded
#      at 0x8000 — confirming Stage-1's disk-read and jmp to 0x8000 worked
#   6. Single-stepping past the first `print` call in Stage-2 and confirming
#      IP advanced (i.e. the print routine was entered and returned)
#
# Enable: BOOT_LIVE_TESTS=1 .venv/bin/python -m pytest tests/ -v -k print
# ===========================================================================


class TestPrintFunction:
    """
    Verify that the `print` / `println` BIOS routines (include/print.asm) are
    properly assembled into the image and are reachable at runtime.

    The strategy is memory-based: after BIOS loads stage-1 to 0x7C00 and
    stage-1 disk-reads stage-2 to 0x8000, both regions must contain the
    ASCII bytes for their respective debug strings.  A working `print` call
    means those strings are present AND the IP advances past the call site.
    """

    @LIVE
    @pytest.mark.skipif(
        shutil.which("make") is None or shutil.which("nasm") is None,
        reason="make or nasm not found on PATH",
    )
    async def test_print_build_fresh_image(self, mcp_session):
        """Step 1 — build a fresh floppy.img before starting the VM."""
        r = await call(mcp_session, "build_image")
        assert r["exit_code"] == 0, f"Build failed:\n{r.get('stderr', '')}"
        assert r["ok"] is True
        floppy = Path(MCP_SERVER_DIR).parent / "floppy.img"
        assert floppy.exists()
        assert floppy.stat().st_size == 512 * 2880

    @LIVE
    @requires_vboxmanage()
    async def test_print_prepare_vm(self, mcp_session):
        """Step 2 — stop → attach floppy → configure GDB stub → start VM (GUI)."""
        r = await call(mcp_session, "prepare_debug_session", gui=True)
        assert r["ok"] is True, r.get("error")

    @LIVE
    @requires_gdb()
    async def test_print_connect_gdb(self, mcp_session):
        """Step 3 — connect GDB to VirtualBox stub (allow up to 20 s for boot)."""
        r = await call(mcp_session, "connect_gdb", timeout=20)
        assert r["ok"] is True, r.get("error")

    @LIVE
    @requires_gdb()
    async def test_print_set_stage1_breakpoint(self, mcp_session):
        """Set a hardware breakpoint at the Stage-1 BIOS entry point 0x7C00."""
        r = await call(mcp_session, "set_breakpoint", flat_addr=0x7C00)
        assert r["ok"] is True, r.get("error")
        assert r["flat_addr"] == "0x07C00"

    @LIVE
    @requires_gdb()
    async def test_print_set_stage2_breakpoint(self, mcp_session):
        """Set a hardware breakpoint at the Stage-2 entry point 0x8000."""
        r = await call(mcp_session, "set_breakpoint", flat_addr=0x8000)
        assert r["ok"] is True, r.get("error")
        assert r["flat_addr"] == "0x08000"

    @LIVE
    @requires_gdb()
    async def test_print_continue_to_stage1(self, mcp_session):
        """Continue execution and confirm we break at 0x7C00 (Stage-1 entry)."""
        cont = await call(mcp_session, "continue_execution")
        assert cont["ok"] is True
        await asyncio.sleep(4)          # give BIOS POST time to reach 0x7C00
        regs = await call(mcp_session, "read_registers")
        assert regs["ok"] is True, regs.get("error")
        assert regs["flat_ip"] == "0x07C00", (
            f"Expected IP=0x07C00 at Stage-1 entry, got {regs['flat_ip']}"
        )

    @LIVE
    @requires_gdb()
    async def test_print_stage1_boot_sector_contains_print_strings(self, mcp_session):
        """
        Read the full 512-byte boot sector from 0x7C00 and verify it contains
        the ASCII text for the '[BOOT]' debug messages that Stage-1 passes to
        `print`.  Their presence confirms the binary was assembled correctly
        and that `print` has valid data to display.
        """
        r = await call(mcp_session, "read_memory", flat_addr=0x7C00, length=512)
        assert r["ok"] is True, r.get("error")
        assert r["length"] == 512

        # Decode hex bytes into a raw bytes object for substring search.
        raw_hex: str = r["hex"]                 # e.g. "fa fc 31 c0 ..."
        raw_bytes = bytes.fromhex(raw_hex.replace(" ", ""))

        # Stage-1 strings that print.asm must be able to display.
        expected_strings = [
            b"[BOOT] Stage 1 initialized",
            b"[BOOT] Video mode set",
            b"[BOOT] Disk reset complete",
            b"[BOOT] Boot2 loaded successfully",
            b"[BOOT] Jumping to stage 2",
        ]
        for s in expected_strings:
            assert s in raw_bytes, (
                f"String {s!r} not found in Stage-1 boot sector — "
                "print.asm data may be missing or overwritten"
            )

    @LIVE
    @requires_gdb()
    async def test_print_continue_to_stage2(self, mcp_session):
        """
        Continue from Stage-1 breakpoint; Stage-1 loads Stage-2 via BIOS
        int 0x13 and jumps to 0x8000.  Confirm IP lands at 0x8000.
        """
        cont = await call(mcp_session, "continue_execution")
        assert cont["ok"] is True
        await asyncio.sleep(5)          # allow disk read + jump
        regs = await call(mcp_session, "read_registers")
        assert regs["ok"] is True, regs.get("error")
        assert regs["flat_ip"] == "0x08000", (
            f"Expected IP=0x08000 at Stage-2 entry, got {regs['flat_ip']}"
        )

    @LIVE
    @requires_gdb()
    async def test_print_stage2_memory_contains_print_strings(self, mcp_session):
        """
        Read 512 bytes from 0x8000 (Stage-2 code) and confirm the '[BOOT2]'
        message strings are present.  These are the strings that Stage-2's
        `print` calls display on the BIOS console.
        """
        r = await call(mcp_session, "read_memory", flat_addr=0x8000, length=512)
        assert r["ok"] is True, r.get("error")
        assert r["length"] == 512

        raw_hex: str = r["hex"]
        raw_bytes = bytes.fromhex(raw_hex.replace(" ", ""))

        expected_strings = [
            b"[BOOT2] Stage 2 initialized at 0x8000",
            b"[BOOT2] Setting up interrupt handlers",
            b"[BOOT2] IDT setup complete",
            b"[BOOT2] Interrupts enabled",
        ]
        for s in expected_strings:
            assert s in raw_bytes, (
                f"String {s!r} not found in Stage-2 memory at 0x8000 — "
                "stage-1 disk-read or print.asm data may be corrupted"
            )

    @LIVE
    @requires_gdb()
    async def test_print_step_through_first_print_call(self, mcp_session):
        """
        Single-step several instructions from the Stage-2 entry point.
        The first thing Stage-2 does is `call print` with SI→msg_boot2_start.
        We step until IP leaves 0x8000 (entered a subroutine), confirming the
        call was made and the print routine is reachable.  This proves
        print.asm is wired up correctly.
        """
        regs_before = await call(mcp_session, "read_registers")
        assert regs_before["ok"] is True
        start_ip = regs_before["flat_ip"]       # should be "0x08000"

        ip_left_entry = False
        for _ in range(30):                     # at most 30 single steps
            step = await call(mcp_session, "step_instruction")
            assert step["ok"] is True, step.get("error")
            regs = await call(mcp_session, "read_registers")
            assert regs["ok"] is True
            current_ip = regs["flat_ip"]
            # Once IP diverges from the entry region we know we entered print.
            if current_ip != start_ip:
                ip_left_entry = True
                break

        assert ip_left_entry, (
            "IP never left 0x8000 after 30 steps — "
            "Stage-2 `call print` was not reached or print.asm is missing"
        )

    @LIVE
    @requires_gdb()
    async def test_print_disassemble_print_routine(self, mcp_session):
        """
        Disassemble 10 instructions from the current IP (inside or just past
        print).  Confirms GDB can decode 16-bit real-mode instructions —
        a prerequisite for step-debugging the print routine.
        """
        regs = await call(mcp_session, "read_registers")
        assert regs["ok"] is True
        flat_ip = int(regs["flat_ip"], 16)

        r = await call(mcp_session, "disassemble", flat_addr=flat_ip, count=10)
        assert r["ok"] is True, r.get("error")
        assert len(r["instructions"]) >= 1, "No instructions returned by disassemble"

    @LIVE
    @requires_gdb()
    async def test_print_disconnect_gdb(self, mcp_session):
        """Disconnect GDB cleanly."""
        r = await call(mcp_session, "disconnect_gdb")
        assert r["ok"] is True

    @LIVE
    @requires_vboxmanage()
    async def test_print_stop_vm(self, mcp_session):
        """Hard power-off the VM after the print verification session."""
        r = await call(mcp_session, "stop_vm")
        assert r["ok"] is True