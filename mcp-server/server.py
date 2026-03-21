"""
server.py — MCP server (stdio transport) for VirtualBox 7.0 boot-loader debugging.

Run:
    python3 server.py

MCP client configuration (Claude Desktop / VS Code):
    {
        "mcpServers": {
            "vbox-boot-debug": {
                "command": "python3",
                "args": ["/path/to/mcp-server/server.py"],
                "env": {
                    "VBOX_VM_NAME": "boot-loader",
                    "VBOX_GDB_PORT": "5037",
                    "VBOX_START_GUI": "true"
                }
            }
        }
    }

Tools exposed
-------------
Build / image
  build_image          — Run make clean && make to (re-)build floppy.img

VM lifecycle
  get_vm_state         — Query current power state of the VM
  prepare_debug_session— One-shot: stop, attach floppy, configure GDB stub, start VM
  attach_floppy        — Attach floppy.img to the VM (VM must be off)
  configure_gdb_stub   — Configure VirtualBox GDB stub (VM must be off)
  start_vm             — Start the VM (gui or headless)
  stop_vm              — Power off the VM immediately
  reset_vm             — Hard reset the VM
  pause_vm             — Pause VM execution
  resume_vm            — Resume VM execution

GDB / debug
  connect_gdb          — Connect GDB client to the VirtualBox stub
  disconnect_gdb       — Disconnect GDB client
  set_breakpoint       — Set a hardware breakpoint at a flat physical address
  set_breakpoint_segoff— Set a hardware breakpoint at a segment:offset address
  delete_breakpoint    — Remove a previously set breakpoint
  list_breakpoints     — List all active breakpoints
  continue_execution   — Resume execution (GDB continue)
  step_instruction     — Single-step one machine instruction (stepi)
  next_instruction     — Step over one instruction (nexti)
  interrupt_execution  — Halt a running VM
  read_registers       — Read all CPU registers (includes flat CS:IP)
  read_memory          — Read bytes from a flat physical address
  read_memory_segoff   — Read bytes from a segment:offset address
  write_memory         — Write bytes to a flat physical address
  disassemble          — Disassemble instructions at a flat physical address

Addressing helpers (returned values)
  seg_off_to_flat      — Convert segment:offset → flat physical address
  flat_to_seg_off      — Convert flat physical address → segment:offset
"""

import json
import subprocess
import sys
from typing import Any

import mcp.server.stdio
import mcp.types as types
from mcp.server import Server

import config
import vbox
from gdb_client import GdbClient, seg_off_to_flat, flat_to_seg_off

# ---------------------------------------------------------------------------
# Server & shared GDB client instance
# ---------------------------------------------------------------------------

app = Server("vbox-boot-debug")

# One shared GDB client per server process (stdio = single session).
_gdb = GdbClient(host=config.GDB_HOST, port=config.GDB_PORT)


# ---------------------------------------------------------------------------
# Tool registration helpers
# ---------------------------------------------------------------------------

def _tool(name: str, description: str, properties: dict, required: list[str] = None):
    """Build a Tool definition."""
    return types.Tool(
        name=name,
        description=description,
        inputSchema={
            "type": "object",
            "properties": properties,
            "required": required or [],
        },
    )


def _int_prop(desc: str) -> dict:
    return {"type": "integer", "description": desc}


def _str_prop(desc: str) -> dict:
    return {"type": "string", "description": desc}


def _bool_prop(desc: str, default: bool = True) -> dict:
    return {"type": "boolean", "description": desc, "default": default}


# ---------------------------------------------------------------------------
# Tool list
# ---------------------------------------------------------------------------

@app.list_tools()
async def list_tools() -> list[types.Tool]:
    return [
        # -- Build --
        _tool(
            "build_image",
            f"Build the bootloader floppy image by running `{config.BUILD_CMD}` in the project directory. "
            "Returns stdout/stderr and the exit code.",
            {},
        ),

        # -- VM lifecycle --
        _tool(
            "get_vm_state",
            f"Return the current power state of VM '{config.VM_NAME}' "
            "(e.g. 'running', 'poweroff', 'saved', 'aborted').",
            {
                "vm_name": _str_prop(f"VM name (default: {config.VM_NAME})"),
            },
        ),
        _tool(
            "prepare_debug_session",
            "One-shot convenience tool: powers off the VM (if running), attaches the floppy image, "
            "configures the VirtualBox GDB stub, then starts the VM. "
            "After this call, connect GDB with `target remote localhost:<port>`.",
            {
                "gui": _bool_prop("Start VM with GUI window (true) or headless (false).", default=config.START_GUI),
                "vm_name": _str_prop(f"VM name (default: {config.VM_NAME})"),
                "image_path": _str_prop(f"Absolute path to floppy image (default: {config.FLOPPY_IMAGE})"),
                "gdb_host": _str_prop(f"GDB stub host (default: {config.GDB_HOST})"),
                "gdb_port": _int_prop(f"GDB stub port (default: {config.GDB_PORT})"),
            },
        ),
        _tool(
            "attach_floppy",
            "Attach a floppy image to the VM. The VM must be powered off.",
            {
                "image_path": _str_prop(f"Absolute path to floppy image (default: {config.FLOPPY_IMAGE})"),
                "vm_name": _str_prop(f"VM name (default: {config.VM_NAME})"),
            },
        ),
        _tool(
            "configure_gdb_stub",
            "Configure the VirtualBox built-in GDB stub on the VM. The VM must be powered off. "
            "Sets provider=gdb, io=tcp, address=host, port=port.",
            {
                "vm_name": _str_prop(f"VM name (default: {config.VM_NAME})"),
                "gdb_host": _str_prop(f"GDB listen address (default: {config.GDB_HOST})"),
                "gdb_port": _int_prop(f"GDB listen port (default: {config.GDB_PORT})"),
            },
        ),
        _tool(
            "start_vm",
            "Start the VM.",
            {
                "vm_name": _str_prop(f"VM name (default: {config.VM_NAME})"),
                "gui": _bool_prop(
                    "True = launch with GUI window (--type gui). "
                    "False = headless (--type headless).",
                    default=config.START_GUI,
                ),
            },
        ),
        _tool("stop_vm",   "Power off the VM immediately (hard off).",
              {"vm_name": _str_prop(f"VM name (default: {config.VM_NAME})")}),
        _tool("reset_vm",  "Hard reset the VM (like pressing the reset button).",
              {"vm_name": _str_prop(f"VM name (default: {config.VM_NAME})")}),
        _tool("pause_vm",  "Pause the VM.",
              {"vm_name": _str_prop(f"VM name (default: {config.VM_NAME})")}),
        _tool("resume_vm", "Resume a paused VM.",
              {"vm_name": _str_prop(f"VM name (default: {config.VM_NAME})")}),

        # -- GDB connection --
        _tool(
            "connect_gdb",
            f"Spawn a local GDB process and connect it to the VirtualBox stub at "
            f"{config.GDB_HOST}:{config.GDB_PORT}. "
            "Automatically sets architecture to i8086 for real-mode debugging. "
            "Waits up to `timeout` seconds for the stub to become reachable.",
            {
                "timeout": {
                    "type": "number",
                    "description": "Seconds to wait for the GDB port (default 15).",
                    "default": 15,
                },
            },
        ),
        _tool("disconnect_gdb", "Disconnect GDB and terminate the local GDB process.", {}),

        # -- Breakpoints --
        _tool(
            "set_breakpoint",
            "Set a hardware breakpoint at a flat physical address. "
            "Common addresses: 0x7C00 (stage-1 entry), 0x8000 (stage-2 entry).",
            {
                "flat_addr": _int_prop(
                    "Flat physical address (e.g. 0x7C00 = 31744). "
                    "Pass as integer or hex string."
                ),
            },
            required=["flat_addr"],
        ),
        _tool(
            "set_breakpoint_segoff",
            "Set a hardware breakpoint at a real-mode segment:offset address. "
            "Automatically converts to flat physical address: flat = (segment << 4) + offset.",
            {
                "segment": _int_prop("Segment register value (0x0000–0xFFFF)."),
                "offset":  _int_prop("Offset within segment (0x0000–0xFFFF)."),
            },
            required=["segment", "offset"],
        ),
        _tool(
            "delete_breakpoint",
            "Remove a previously set breakpoint by flat physical address.",
            {"flat_addr": _int_prop("Flat physical address of the breakpoint to remove.")},
            required=["flat_addr"],
        ),
        _tool("list_breakpoints", "List all currently active breakpoints.", {}),

        # -- Execution control --
        _tool("continue_execution",  "Resume execution (GDB continue).", {}),
        _tool("step_instruction",    "Single-step one machine instruction (stepi).", {}),
        _tool("next_instruction",    "Step over one instruction (nexti).", {}),
        _tool("interrupt_execution", "Halt the running VM (GDB interrupt).", {}),

        # -- Registers / memory --
        _tool(
            "read_registers",
            "Read all CPU registers. Returns a dict of register names → hex values. "
            "Also includes 'flat_ip' = (CS << 4) + IP for quick real-mode location.",
            {},
        ),
        _tool(
            "read_memory",
            "Read bytes from a flat physical address. "
            "Returns hex dump and ASCII representation.",
            {
                "flat_addr": _int_prop("Flat physical address to read from."),
                "length":    _int_prop("Number of bytes to read (default 16)."),
            },
            required=["flat_addr"],
        ),
        _tool(
            "read_memory_segoff",
            "Read bytes from a real-mode segment:offset address. "
            "Converts to flat physical address automatically.",
            {
                "segment": _int_prop("Segment register value."),
                "offset":  _int_prop("Offset within segment."),
                "length":  _int_prop("Number of bytes to read (default 16)."),
            },
            required=["segment", "offset"],
        ),
        _tool(
            "write_memory",
            "Write bytes to a flat physical address. Use with caution.",
            {
                "flat_addr": _int_prop("Flat physical address to write to."),
                "data": {
                    "type": "array",
                    "items": {"type": "integer"},
                    "description": "List of byte values (0–255) to write.",
                },
            },
            required=["flat_addr", "data"],
        ),
        _tool(
            "disassemble",
            "Disassemble machine instructions at a flat physical address. "
            "Uses GDB x/Ni format in i8086 real-mode context.",
            {
                "flat_addr": _int_prop("Flat physical address to disassemble from."),
                "count":     _int_prop("Number of instructions to disassemble (default 10)."),
            },
            required=["flat_addr"],
        ),

        # -- Addressing helpers --
        _tool(
            "seg_off_to_flat",
            "Convert a real-mode segment:offset pair to a flat physical address. "
            "Formula: flat = (segment << 4) + offset.",
            {
                "segment": _int_prop("Segment value (0x0000–0xFFFF)."),
                "offset":  _int_prop("Offset value (0x0000–0xFFFF)."),
            },
            required=["segment", "offset"],
        ),
        _tool(
            "flat_to_seg_off",
            "Convert a flat physical address to a real-mode segment:offset pair. "
            "Supply a preferred segment; the offset is computed as flat - (segment << 4).",
            {
                "flat_addr": _int_prop("Flat physical address."),
                "segment":   _int_prop("Preferred segment (default 0x0000)."),
            },
            required=["flat_addr"],
        ),
    ]


# ---------------------------------------------------------------------------
# Tool dispatcher
# ---------------------------------------------------------------------------

def _parse_addr(value: Any) -> int:
    """Accept int or hex-string address from tool arguments."""
    if isinstance(value, int):
        return value
    if isinstance(value, str):
        return int(value, 16) if value.startswith("0x") or value.startswith("0X") else int(value)
    raise ValueError(f"Cannot parse address from {value!r}")


@app.call_tool()
async def call_tool(name: str, arguments: dict) -> list[types.TextContent]:
    result: Any = None

    # -- Build --
    if name == "build_image":
        proc = subprocess.run(
            config.BUILD_CMD,
            shell=True,
            capture_output=True,
            text=True,
            cwd=str(config.BUILD_CWD),
        )
        result = {
            "ok": proc.returncode == 0,
            "exit_code": proc.returncode,
            "stdout": proc.stdout.strip(),
            "stderr": proc.stderr.strip(),
        }

    # -- VM lifecycle --
    elif name == "get_vm_state":
        result = vbox.get_vm_state(arguments.get("vm_name", config.VM_NAME))

    elif name == "prepare_debug_session":
        result = vbox.prepare_debug_session(
            image_path=arguments.get("image_path", config.FLOPPY_IMAGE),
            vm_name=arguments.get("vm_name", config.VM_NAME),
            gdb_host=arguments.get("gdb_host", config.GDB_HOST),
            gdb_port=int(arguments.get("gdb_port", config.GDB_PORT)),
            gui=bool(arguments.get("gui", config.START_GUI)),
        )

    elif name == "attach_floppy":
        result = vbox.attach_floppy(
            image_path=arguments.get("image_path", config.FLOPPY_IMAGE),
            vm_name=arguments.get("vm_name", config.VM_NAME),
        )

    elif name == "configure_gdb_stub":
        result = vbox.configure_gdb_stub(
            vm_name=arguments.get("vm_name", config.VM_NAME),
            host=arguments.get("gdb_host", config.GDB_HOST),
            port=int(arguments.get("gdb_port", config.GDB_PORT)),
        )

    elif name == "start_vm":
        result = vbox.start_vm(
            vm_name=arguments.get("vm_name", config.VM_NAME),
            gui=bool(arguments.get("gui", config.START_GUI)),
        )

    elif name == "stop_vm":
        result = vbox.stop_vm(arguments.get("vm_name", config.VM_NAME))

    elif name == "reset_vm":
        result = vbox.reset_vm(arguments.get("vm_name", config.VM_NAME))

    elif name == "pause_vm":
        result = vbox.pause_vm(arguments.get("vm_name", config.VM_NAME))

    elif name == "resume_vm":
        result = vbox.resume_vm(arguments.get("vm_name", config.VM_NAME))

    # -- GDB connection --
    elif name == "connect_gdb":
        result = _gdb.connect(timeout=float(arguments.get("timeout", 15)))

    elif name == "disconnect_gdb":
        result = _gdb.disconnect()

    # -- Breakpoints --
    elif name == "set_breakpoint":
        result = _gdb.set_breakpoint(_parse_addr(arguments["flat_addr"]))

    elif name == "set_breakpoint_segoff":
        result = _gdb.set_breakpoint_segoff(
            int(arguments["segment"]),
            int(arguments["offset"]),
        )

    elif name == "delete_breakpoint":
        result = _gdb.delete_breakpoint(_parse_addr(arguments["flat_addr"]))

    elif name == "list_breakpoints":
        result = _gdb.list_breakpoints()

    # -- Execution control --
    elif name == "continue_execution":
        result = _gdb.continue_execution()

    elif name == "step_instruction":
        result = _gdb.step_instruction()

    elif name == "next_instruction":
        result = _gdb.next_instruction()

    elif name == "interrupt_execution":
        result = _gdb.interrupt_execution()

    # -- Registers / memory --
    elif name == "read_registers":
        result = _gdb.read_registers()

    elif name == "read_memory":
        result = _gdb.read_memory(
            _parse_addr(arguments["flat_addr"]),
            int(arguments.get("length", 16)),
        )

    elif name == "read_memory_segoff":
        result = _gdb.read_memory_segoff(
            int(arguments["segment"]),
            int(arguments["offset"]),
            int(arguments.get("length", 16)),
        )

    elif name == "write_memory":
        result = _gdb.write_memory(
            _parse_addr(arguments["flat_addr"]),
            [int(b) for b in arguments["data"]],
        )

    elif name == "disassemble":
        result = _gdb.disassemble(
            _parse_addr(arguments["flat_addr"]),
            int(arguments.get("count", 10)),
        )

    # -- Addressing helpers --
    elif name == "seg_off_to_flat":
        flat = seg_off_to_flat(int(arguments["segment"]), int(arguments["offset"]))
        result = {
            "ok": True,
            "segment": f"0x{int(arguments['segment']):04X}",
            "offset":  f"0x{int(arguments['offset']):04X}",
            "flat":    f"0x{flat:05X}",
            "flat_int": flat,
        }

    elif name == "flat_to_seg_off":
        flat = _parse_addr(arguments["flat_addr"])
        seg  = int(arguments.get("segment", 0))
        try:
            s, o = flat_to_seg_off(flat, seg)
            result = {
                "ok": True,
                "flat": f"0x{flat:05X}",
                "segment": f"0x{s:04X}",
                "offset":  f"0x{o:04X}",
            }
        except ValueError as exc:
            result = {"ok": False, "error": str(exc)}

    else:
        result = {"ok": False, "error": f"Unknown tool: {name}"}

    return [types.TextContent(type="text", text=json.dumps(result, indent=2))]


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

async def main():
    async with mcp.server.stdio.stdio_server() as (read_stream, write_stream):
        await app.run(
            read_stream,
            write_stream,
            app.create_initialization_options(),
        )


if __name__ == "__main__":
    import asyncio
    asyncio.run(main())
