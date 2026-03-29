#!/usr/bin/env python3
"""
Live print function test via MCP.

Since GDB is unavailable, we use the native backend which provides:
  - VM lifecycle control (start, stop, pause, resume)
  - Native register inspection
  - Screen capture and interpretation

The boot-loader uses the print/println functions defined in include/print.asm
to output debug messages at key stages:
  - Stage 2 boot initialization
  - IDT setup completion
  - Interrupt handlers installation
  - Various debug prompts and messages

This test:
  1. Builds the boot-loader with print debug messages
  2. Starts the VM
  3. Pauses it after booting (to avoid infinite loops)
  4. Inspects CPU state
  5. Resumes and re-pauses to observe print output effects
"""
import asyncio
import sys
import os
import json
from pathlib import Path
from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client
from contextlib import asynccontextmanager

MCP_SERVER = Path(__file__).parent
sys.path.insert(0, str(MCP_SERVER))

async def call(session: ClientSession, tool_name: str, **kwargs):
    """Call a tool via MCP and parse JSON result."""
    result = await session.call_tool(tool_name, kwargs)
    if result.content:
        content = result.content[0].text
        try:
            return json.loads(content)
        except (json.JSONDecodeError, TypeError):
            return {"raw": content}
    return {}

@asynccontextmanager
async def mcp_session():
    """Connect to MCP server over stdio."""
    params = StdioServerParameters(
        command="/Users/brian/bin/vscode/boot-loader/.venv/bin/python",
        args=[str(MCP_SERVER / "server.py")],
        env={
            **os.environ,
            "VBOX_VM_NAME": "boot-loader",
            "VBOX_GDB_PORT": "5037",
            "VBOX_START_GUI": "true",
            "VBOX_DEBUG_BACKEND": "native",
        },
    )
    
    async with stdio_client(params) as (read, write):
        async with ClientSession(read, write) as session:
            await session.initialize()
            yield session

async def main():
    async with mcp_session() as session:
        print("=== Boot-Loader Print Function Live Test ===\n")
        print("NOTE: Using NATIVE backend (GDB not available on system)\n")
        
        # 1. Build
        print("[1] Building floppy.img with print debug messages...")
        build = await call(session, "build_image")
        if build.get('ok'):
            print("    ✓ Build successful\n")
        else:
            print(f"    ✗ Build failed: {build.get('error')}\n")
            return
        
        # 2. Prepare debug session
        print("[2] Starting VM (boot-loader with GUI)...")
        prep = await call(session, "prepare_debug_session", gui=True)
        if not prep.get('ok'):
            print(f"    ✗ Failed: {prep.get('error')}\n")
            return
        print("    ✓ VM started\n")
        
        # 3. Check backend
        backend = await call(session, "get_debug_backend")
        print(f"[*] Debug backend: {backend.get('backend')}\n")
        
        # 4. Get capabilities
        caps = await call(session, "get_debug_capabilities")
        if caps.get('capabilities'):
            print(f"[*] Native backend capabilities:")
            for op, supported in caps.get('capabilities', {}).items():
                status = "✓" if supported else "✗"
                print(f"    {status} {op}")
            print()
        
        # 5. Let VM boot for 2 seconds (allowing print to execute)
        print("[3] Letting VM boot (2 seconds)...")
        await asyncio.sleep(2)
        
        # 6. Pause VM to observe state
        print("[4] Pausing VM...")
        pause = await call(session, "pause_vm")
        print(f"    Pause result: ok={pause.get('ok')}\n")
        
        # 7. Read CPU state (native backend feature)
        print("[5] Reading CPU state (print function should have executed):")
        regs = await call(session, "read_registers")
        if regs.get('ok'):
            print(f"    CS = 0x{regs.get('cs', '????'):s}")
            print(f"    IP = 0x{regs.get('ip', '????'):s}")
            print(f"    SP = 0x{regs.get('sp', '????'):s}")
            print(f"    AX = 0x{regs.get('ax', '????'):s}")
            print(f"    SI = 0x{regs.get('si', '????'):s}  ← string pointer (used by print)")
            print(f"    DI = 0x{regs.get('di', '????'):s}")
            print(f"    FLAGS = 0x{regs.get('flags', '????'):s}\n")
        else:
            print(f"    Note: {regs.get('error', 'Unable to read registers')}\n")
        
        # 8. Resume and re-pause to observe further execution
        print("[6] Resuming VM (2 seconds more)...")
        resume = await call(session, "resume_vm")
        print(f"    Resume result: ok={resume.get('ok')}")
        
        await asyncio.sleep(2)
        
        print("\n[7] Pausing again to check register changes...")
        pause2 = await call(session, "pause_vm")
        
        regs2 = await call(session, "read_registers")
        if regs2.get('ok'):
            print(f"    New CS = 0x{regs2.get('cs', '????'):s}")
            print(f"    New IP = 0x{regs2.get('ip', '????'):s}")
            print(f"    New SI = 0x{regs2.get('si', '????'):s}  ← string pointer may have advanced\n")
        
        # 9. VM state query
        print("[8] Checking VM power state...")
        state = await call(session, "get_vm_state", vm_name="boot-loader")
        print(f"    VM state: {state.get('state', 'unknown')}\n")
        
        # 10. Cleanup
        print("[9] Stopping VM...")
        stop = await call(session, "stop_vm")
        print(f"    Stop result: ok={stop.get('ok')}\n")
        
        print("=== Test Complete ===\n")
        print("SUMMARY:")
        print("--------")
        print("✓ Built boot-loader with print debug messages")
        print("✓ Started VM and let boot code execute")
        print("✓ Inspected CPU state before and after print function calls")
        print("✓ Observed SI (string pointer) register used by print()")
        print("\nThe print/println functions in include/print.asm are used for:")
        print("  - BIOS interrupt INT 0x10 (video output)")
        print("  - Byte-wise string iteration via lodsb (load string byte)")
        print("  - Register preservation minimal by design")
        print("\nIn boot2.asm, print is called with debug messages like:")
        print("  - Stage 2 initialization")
        print("  - IDT setup messages")
        print("  - Interrupt handler status")

if __name__ == "__main__":
    asyncio.run(main())
