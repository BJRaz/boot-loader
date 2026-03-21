# VirtualBox 7.0 MCP Debug Server

A **Model Context Protocol (MCP) server** (stdio transport) that exposes
VirtualBox VM lifecycle control and 16-bit real-mode GDB debugging as MCP
tools.

Originally written for the `boot-loader` project in this repo but generic
enough to adapt to any VirtualBox-hosted bare-metal project via environment
variables.

---

## Folder layout

```
mcp-server/
├── server.py          # MCP server entry point (stdio)
├── vbox.py            # VBoxManage subprocess wrappers
├── gdb_client.py      # pygdbmi GDB/MI client with real-mode helpers
├── config.py          # Centralised configuration (env-var overrides)
├── requirements.txt   # Python dependencies
└── README.md          # This file
```

---

## Prerequisites

| Requirement | Notes |
|---|---|
| Python 3.11+ | `python3 --version` |
| VirtualBox 7.0 | `VBoxManage --version` must be on `$PATH` |
| GDB with i8086 support | `brew install gdb` or system GDB |
| A VirtualBox VM named `boot-loader` | Already configured in this project |

---

## Installation

```bash
cd mcp-server/

# Create a virtual environment (recommended)
python3 -m venv .venv
source .venv/bin/activate

# Install dependencies
pip3 install -r requirements.txt
```

---

## Running the server

```bash
# With the venv active:
python3 server.py
```

The server communicates over **stdio** — it is designed to be launched by an
MCP client (Claude Desktop, VS Code Copilot, etc.), not run directly by users.

---

## MCP client configuration

### Claude Desktop (`~/Library/Application Support/Claude/claude_desktop_config.json`)

```json
{
    "mcpServers": {
        "vbox-boot-debug": {
            "command": "/path/to/boot-loader/mcp-server/.venv/bin/python3",
            "args": ["/path/to/boot-loader/mcp-server/server.py"],
            "env": {
                "VBOX_VM_NAME": "boot-loader",
                "VBOX_GDB_PORT": "5037",
                "VBOX_START_GUI": "true"
            }
        }
    }
}
```

### VS Code (`settings.json` or `.vscode/mcp.json`)

```json
{
    "mcp": {
        "servers": {
            "vbox-boot-debug": {
                "type": "stdio",
                "command": "${workspaceFolder}/mcp-server/.venv/bin/python3",
                "args": ["${workspaceFolder}/mcp-server/server.py"]
            }
        }
    }
}
```

---

## Configuration (environment variables)

All defaults match this project's `Makefile`. Override by setting env vars in
the MCP client config (see above) or exporting them in the shell.

| Variable | Default | Description |
|---|---|---|
| `BOOT_PROJECT_ROOT` | parent of `mcp-server/` | Root of the bootloader project |
| `BOOT_FLOPPY_IMAGE` | `<root>/floppy.img` | Floppy image path |
| `BOOT_BUILD_CMD` | `make clean && make` | Command to rebuild the image |
| `BOOT_BUILD_CWD` | `BOOT_PROJECT_ROOT` | Working dir for build command |
| `VBOX_VM_NAME` | `boot-loader` | VirtualBox VM name |
| `VBOX_STORAGE_CTL` | `Floppy` | Storage controller name |
| `VBOX_STORAGE_PORT` | `0` | Floppy controller port |
| `VBOX_STORAGE_DEVICE` | `0` | Floppy controller device |
| `VBOX_START_GUI` | `true` | `true` = GUI window, `false` = headless |
| `VBOX_GDB_HOST` | `localhost` | GDB stub bind address |
| `VBOX_GDB_PORT` | `5037` | GDB stub TCP port |

---

## Available MCP tools

### Build

| Tool | Description |
|---|---|
| `build_image` | Run `make clean && make` to rebuild `floppy.img` |

### VM lifecycle

| Tool | Description |
|---|---|
| `get_vm_state` | Query current power state (`running`, `poweroff`, …) |
| `prepare_debug_session` | **One-shot**: stop → attach floppy → configure GDB stub → start VM |
| `attach_floppy` | Attach `floppy.img` to the VM floppy drive (VM must be off) |
| `configure_gdb_stub` | Set up the VirtualBox GDB stub (VM must be off) |
| `start_vm` | Start VM — `gui: true/false` controls window vs headless |
| `stop_vm` | Hard power-off |
| `reset_vm` | Hard reset |
| `pause_vm` | Pause execution |
| `resume_vm` | Resume execution |

### GDB / debug

| Tool | Description |
|---|---|
| `connect_gdb` | Spawn GDB, set arch to `i8086`, connect to stub |
| `disconnect_gdb` | Disconnect and exit GDB |
| `set_breakpoint` | Hardware breakpoint at flat physical address |
| `set_breakpoint_segoff` | Hardware breakpoint at segment:offset |
| `delete_breakpoint` | Remove breakpoint by flat address |
| `list_breakpoints` | List all active breakpoints |
| `continue_execution` | GDB `continue` |
| `step_instruction` | GDB `stepi` |
| `next_instruction` | GDB `nexti` |
| `interrupt_execution` | GDB `interrupt` (halt running VM) |
| `read_registers` | All registers + computed `flat_ip` |
| `read_memory` | Hex dump from flat physical address |
| `read_memory_segoff` | Hex dump from segment:offset address |
| `write_memory` | Write bytes to flat physical address |
| `disassemble` | Disassemble N instructions at flat address |

### Addressing helpers

| Tool | Description |
|---|---|
| `seg_off_to_flat` | `(segment << 4) + offset` → flat |
| `flat_to_seg_off` | flat → `(segment, offset)` given a preferred segment |

---

## Typical debug session workflow

```
1. build_image                        # rebuild floppy.img from source
2. prepare_debug_session              # stop VM → attach image → configure GDB stub → start VM (GUI)
3. connect_gdb (timeout=20)           # wait for stub, connect with i8086 arch
4. set_breakpoint (flat_addr=0x7C00)  # break at stage-1 BIOS entry point
5. set_breakpoint (flat_addr=0x8000)  # break at stage-2 entry point
6. continue_execution                 # let the VM run until breakpoint
7. read_registers                     # inspect CS, IP, flat_ip, flags, SP …
8. disassemble (flat_addr=0x7C00, count=20)
9. step_instruction                   # single-step through boot code
```

---

## Real-mode addressing notes

VirtualBox's GDB stub exposes **flat physical addresses**.  In 16-bit real mode
the CPU accesses memory via `segment:offset` pairs where:

```
flat_physical = (segment << 4) + offset
```

Key boot-loader physical addresses:

| Address | Content |
|---|---|
| `0x00000–0x003FF` | IVT (Interrupt Vector Table) |
| `0x00400–0x004FF` | BIOS Data Area (BDA) |
| `0x07C00` | Stage-1 entry (`CS=0x0000 IP=0x7C00`) |
| `0x08000` | Stage-2 entry (`CS=0x0000 IP=0x8000`) |

Use `set_breakpoint(0x7C00)` or `set_breakpoint_segoff(0x0000, 0x7C00)` —
both resolve to the same physical address.

---

## Adapting to other projects

1. Set env vars in your MCP client config (`VBOX_VM_NAME`, `BOOT_FLOPPY_IMAGE`,
   `BOOT_BUILD_CMD`, `VBOX_GDB_PORT`, …).
2. Adjust `STAGE1_ADDR` / `STAGE2_ADDR` in `config.py` if your image loads
   at different addresses.
3. Verify your VirtualBox storage controller name matches `VBOX_STORAGE_CTL`
   (`VBoxManage showvminfo <vm> | grep "Storage Controller Name"`).
