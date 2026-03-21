"""
config.py — centralised configuration for the VirtualBox MCP debug server.

All values can be overridden by environment variables so the server is
reusable across different projects without editing this file.
"""

import os
import shutil
from pathlib import Path

# ---------------------------------------------------------------------------
# Project / image paths
# ---------------------------------------------------------------------------

# Root of the bootloader project (parent of mcp-server/).
PROJECT_ROOT: Path = Path(os.environ.get("BOOT_PROJECT_ROOT", Path(__file__).parent.parent)).resolve()

# Floppy image that gets written to the VM floppy drive.
FLOPPY_IMAGE: Path = Path(
    os.environ.get("BOOT_FLOPPY_IMAGE", PROJECT_ROOT / "floppy.img")
).resolve()

# Shell command used to (re-)build the bootloader image.
BUILD_CMD: str = os.environ.get("BOOT_BUILD_CMD", "make clean && make")

# Working directory for BUILD_CMD (usually the project root).
BUILD_CWD: Path = Path(
    os.environ.get("BOOT_BUILD_CWD", PROJECT_ROOT)
).resolve()

# ---------------------------------------------------------------------------
# VirtualBox VM settings
# ---------------------------------------------------------------------------

# Name of the VirtualBox VM to control.
VM_NAME: str = os.environ.get("VBOX_VM_NAME", "boot-loader")

# Storage controller name as it appears in VBoxManage showvminfo output.
STORAGE_CTL: str = os.environ.get("VBOX_STORAGE_CTL", "Floppy")

# Floppy controller port / device numbers.
STORAGE_PORT: int = int(os.environ.get("VBOX_STORAGE_PORT", "0"))
STORAGE_DEVICE: int = int(os.environ.get("VBOX_STORAGE_DEVICE", "0"))

# Start the VM with a GUI window (True) or headless (False).
# Pass --gui / --headless flag to the server, or set this env var.
START_GUI: bool = os.environ.get("VBOX_START_GUI", "true").lower() not in ("0", "false", "no")

# ---------------------------------------------------------------------------
# GDB stub settings (VirtualBox built-in GDB server)
# ---------------------------------------------------------------------------

GDB_HOST: str = os.environ.get("VBOX_GDB_HOST", "localhost")
GDB_PORT: int = int(os.environ.get("VBOX_GDB_PORT", "5037"))

# GDB debug provider / IO provider passed to VBoxManage modifyvm.
GDB_PROVIDER: str = "gdb"
GDB_IO_PROVIDER: str = "tcp"

# Debug backend selection:
#   auto   -> use gdb if binary exists, else native
#   gdb    -> strict: require gdb binary
#   native -> strict: use VirtualBox native debug operations
DEBUG_BACKEND: str = os.environ.get("VBOX_DEBUG_BACKEND", "auto").strip().lower()


def detect_gdb_binary() -> str | None:
    """Return resolved gdb binary path if available, else None."""
    return shutil.which("gdb")


def select_debug_backend() -> tuple[str, str | None]:
    """
    Resolve backend with strict semantics.

    Returns
    -------
    tuple[str, str|None]
        (backend, gdb_binary)
    """
    if DEBUG_BACKEND not in ("auto", "gdb", "native"):
        raise ValueError(
            "Invalid VBOX_DEBUG_BACKEND. Expected one of: auto, gdb, native. "
            f"Got: {DEBUG_BACKEND!r}"
        )

    gdb_bin = detect_gdb_binary()

    if DEBUG_BACKEND == "native":
        return "native", None

    if DEBUG_BACKEND == "gdb":
        if not gdb_bin:
            raise RuntimeError(
                "Strict mode enabled (VBOX_DEBUG_BACKEND=gdb), but 'gdb' binary was not found on PATH."
            )
        return "gdb", gdb_bin

    if gdb_bin:
        return "gdb", gdb_bin
    return "native", None

# ---------------------------------------------------------------------------
# Real-mode memory map constants (used by gdb_client helpers)
# ---------------------------------------------------------------------------

# Physical address where BIOS loads stage 1.
STAGE1_ADDR: int = 0x7C00

# Physical address where stage 1 loads stage 2.
STAGE2_ADDR: int = 0x8000

# Number of bytes in a real-mode segment (64 KiB).
SEGMENT_SIZE: int = 0x10000
