#!/usr/bin/env python3
"""
Live MCP debug session for print function.
Stages:
  1. build_image
  2. prepare_debug_session (start VM)
  3. connect_gdb (establish GDB stub connection)
  4. set_breakpoint at print function entry
  5. continue_execution (let VM run)
  6. read_registers, read_memory, disassemble for inspection
  7. step_instruction to trace through print logic
  8. disconnect, stop_vm
"""
import asyncio
import sys
import os
from pathlib import Path

# Add mcp-server to path
MCP_SERVER = Path(__file__).parent
sys.path.insert(0, str(MCP_SERVER))

from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client
from contextlib import asynccontextmanager
import json

async def call(session: ClientSession, tool_name: str, **kwargs):
    """Call a tool via MCP."""
    result = await session.call_tool(tool_name, kwargs)
    if result.content:
        content = result.content[0].text
        # Try to parse as JSON
        try:
            return json.loads(content)
        except (json.JSONDecodeError, TypeError):
            return {"raw": content}
    return {}

@asynccontextmanager
async def mcp_session():
    """Connect to MCP server over stdio."""
    params = StdioServerParameters(
        command=str(MCP_SERVER / ".venv/bin/python"),
        args=[str(MCP_SERVER / "server.py")],
        env={
            **os.environ,
            "VBOX_VM_NAME": "boot-loader",
            "VBOX_GDB_PORT": "5037",
            "VBOX_START_GUI": "true",
            "VBOX_DEBUG_BACKEND": "auto",
        },
    )
    
    async with stdio_client(params) as (read, write):
        async with ClientSession(read, write) as session:
            await session.initialize()
            yield session

async def main():
    async with mcp_session() as session:
        print("=== MCP Live Print Debug Session ===\n")
        
        # 1. Build image
        print("[1] Building floppy.img...")
        build_result = await call(session, "build_image")
        print(f"    Build: {build_result}\n")
        
        # 2. Prepare debug session (stop → attach → configure → start VM)
        print("[2] Preparing debug session (start VM with GUI)...")
        prep_result = await call(session, "prepare_debug_session", gui=True)
        print(f"    Result: ok={prep_result.get('ok')}\n")
        
        if not prep_result.get("ok"):
            print(f"    ERROR: {prep_result.get('error')}")
            return
        
        # 3. Connect GDB
        print("[3] Connecting GDB (timeout 20s)...")
        connect_result = await call(session, "connect_gdb", timeout=20)
        print(f"    Result: ok={connect_result.get('ok')}\n")
        
        if not connect_result.get("ok"):
            print(f"    WARNING: {connect_result.get('error')}")
            print("    Continuing without GDB (native backend)...\n")
        
        # Check active backend
        backend_info = await call(session, "get_debug_backend")
        print(f"[*] Active backend: {backend_info.get('backend')}")
        print(f"    Strict mode: {backend_info.get('strict_mode')}\n")
        
        # 4. Set breakpoints for print function
        # print function is at 0x8000 + offset (in boot2.asm)
        print("[4] Setting breakpoints on print-related addresses...")
        
        # Break at stage2 entry (where print is called first)
        bp1 = await call(session, "set_breakpoint", flat_addr=0x8000)
        print(f"    Stage2 entry (0x8000): {bp1.get('ok')}")
        
        # Break at print function entry (in boot2.asm, after includes)
        # Print is at approximately 0x8100+ in boot2, let's set at 0x8050 as probe
        bp2 = await call(session, "set_breakpoint", flat_addr=0x8050)
        print(f"    Print probe (0x8050): {bp2.get('ok')}\n")
        
        # 5. List breakpoints
        bps = await call(session, "list_breakpoints")
        print(f"[5] Active breakpoints: {bps.get('breakpoints', [])}\n")
        
        # 6. Continue execution until first breakpoint
        print("[6] Continuing execution (VM will break at stage2)...")
        cont = await call(session, "continue_execution")
        print(f"    Continue: ok={cont.get('ok')}\n")
        
        # 7. Read registers to see where we stopped
        print("[7] Reading registers...")
        regs = await call(session, "read_registers")
        if regs.get('ok'):
            print(f"    CS:IP = 0x{regs.get('cs', '0'):s}:0x{regs.get('ip', '0'):s}")
            print(f"    flat_ip = 0x{regs.get('flat_ip', '0'):s}")
            print(f"    SP = 0x{regs.get('sp', '0'):s}")
            print(f"    AX = 0x{regs.get('ax', '0'):s}, BX = 0x{regs.get('bx', '0'):s}\n")
        else:
            print(f"    ERROR: {regs.get('error')}\n")
        
        # 8. Disassemble around current IP
        print("[8] Disassembling from stage2 entry...")
        disasm = await call(session, "disassemble", flat_addr=0x8000, count=20)
        if disasm.get('ok'):
            print(f"    Assembly:\n{disasm.get('assembly', 'N/A')}\n")
        else:
            print(f"    Disassembly not available: {disasm.get('error')}\n")
        
        # 9. Read memory at stage2 to inspect strings/code
        print("[9] Reading memory at stage2 (0x8000, 64 bytes)...")
        mem = await call(session, "read_memory", flat_addr=0x8000, length=64)
        if mem.get('ok'):
            print(f"    Hex dump:\n{mem.get('hex_dump', 'N/A')}\n")
        else:
            print(f"    Memory read failed: {mem.get('error')}\n")
        
        # 10. Single-step through a few instructions
        print("[10] Single-stepping 5 instructions...")
        for i in range(5):
            step = await call(session, "step_instruction")
            print(f"    Step {i+1}: ok={step.get('ok')}")
            
            # Read registers after each step
            regs = await call(session, "read_registers")
            if regs.get('ok'):
                print(f"      → IP=0x{regs.get('ip', '0'):s}, AX=0x{regs.get('ax', '0'):s}")
        
        print()
        
        # 11. Cleanup
        print("[11] Cleaning up...")
        disc = await call(session, "disconnect_gdb")
        print(f"    Disconnected: ok={disc.get('ok')}")
        
        stop = await call(session, "stop_vm")
        print(f"    Stopped VM: ok={stop.get('ok')}\n")
        
        print("=== Debug session complete ===")

if __name__ == "__main__":
    asyncio.run(main())
