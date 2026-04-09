"""
qemu.py — QEMU process lifecycle for boot-loader debugging.

QEMU is ephemeral: launched fresh each session, killed to stop.
The built-in GDB stub is enabled with -gdb tcp::<port> -S (halt at startup).

Every public function returns:
    {"ok": True,  ...}   on success
    {"ok": False, "error": str}  on failure
"""

import subprocess
from pathlib import Path
from typing import Union

import config

# Module-level handle to the running QEMU process (one at a time).
_proc: subprocess.Popen | None = None


def _ok(output: str) -> dict:
    return {"ok": True, "output": output.strip()}


def _err(msg: str) -> dict:
    return {"ok": False, "error": msg.strip()}


# ---------------------------------------------------------------------------
# VM state
# ---------------------------------------------------------------------------

def get_vm_state() -> dict:
    """Return 'running' if a QEMU process is alive, else 'poweroff'."""
    global _proc
    if _proc is not None and _proc.poll() is None:
        return {"ok": True, "state": "running", "pid": _proc.pid,
                "output": f"QEMU running (pid {_proc.pid})."}
    if _proc is not None:
        _proc = None
    return {"ok": True, "state": "poweroff", "output": "No QEMU process running."}


# ---------------------------------------------------------------------------
# VM lifecycle
# ---------------------------------------------------------------------------

def start_vm(
    image_path: Union[str, Path] = config.FLOPPY_IMAGE,
    gdb_host: str = config.GDB_HOST,
    gdb_port: int = config.GDB_PORT,
    halt_on_start: bool = True,
    display: str = config.QEMU_DISPLAY,
) -> dict:
    """
    Launch qemu-system-i386 with the floppy image and GDB stub.

    Parameters
    ----------
    halt_on_start : bool
        If True, passes -S so the CPU halts until GDB sends 'continue'.
        Recommended for debugging so GDB can set breakpoints before execution.
    display : str
        QEMU display backend. 'none' = headless (default).
        'sdl' or 'gtk' opens a window.
    """
    global _proc

    if config.QEMU_BINARY is None:
        return _err(
            "qemu-system-i386 not found on PATH. "
            "Install QEMU or set the QEMU_BINARY environment variable."
        )

    state = get_vm_state()
    if state["state"] == "running":
        return _err(f"QEMU already running (pid {_proc.pid}). Call stop_vm first.")

    image_path = str(Path(image_path).resolve())
    cmd = [
        config.QEMU_BINARY,
        "-nic", "none",
        "-display", display,
        "-fda", image_path,
        "-gdb", f"tcp:{gdb_host}:{gdb_port}",
        "-no-reboot",
    ]
    if halt_on_start:
        cmd.append("-S")

    try:
        _proc = subprocess.Popen(
            cmd,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.PIPE,
        )
    except OSError as exc:
        return _err(f"Failed to launch QEMU: {exc}")

    # Give the process a moment then check it didn't exit immediately.
    try:
        _proc.wait(timeout=0.3)
        # If we get here the process exited.
        stderr_out = (_proc.stderr.read() or b"").decode(errors="replace").strip()
        rc = _proc.returncode
        _proc = None
        detail = f": {stderr_out}" if stderr_out else ""
        return _err(f"QEMU exited immediately (exit code {rc}){detail}")
    except subprocess.TimeoutExpired:
        pass  # Still running — good.

    halt_note = " Halted at startup — connect GDB then call continue_execution." if halt_on_start else ""
    return _ok(
        f"QEMU started (pid {_proc.pid}).{halt_note} "
        f"GDB stub listening at {gdb_host}:{gdb_port}."
    )


def stop_vm() -> dict:
    """Terminate the QEMU process."""
    global _proc
    if _proc is None or _proc.poll() is not None:
        _proc = None
        return _ok("No QEMU process running.")

    _proc.terminate()
    try:
        _proc.wait(timeout=3)
    except subprocess.TimeoutExpired:
        _proc.kill()
        _proc.wait()
    _proc = None
    return _ok("QEMU stopped.")


def reset_vm(
    image_path: Union[str, Path] = config.FLOPPY_IMAGE,
    gdb_host: str = config.GDB_HOST,
    gdb_port: int = config.GDB_PORT,
    halt_on_start: bool = True,
    display: str = config.QEMU_DISPLAY,
) -> dict:
    """Stop the running QEMU process and start a fresh one."""
    r = stop_vm()
    if not r["ok"]:
        return r
    return start_vm(
        image_path=image_path,
        gdb_host=gdb_host,
        gdb_port=gdb_port,
        halt_on_start=halt_on_start,
        display=display,
    )


# ---------------------------------------------------------------------------
# Convenience: full debug-start sequence
# ---------------------------------------------------------------------------

def prepare_debug_session(
    image_path: Union[str, Path] = config.FLOPPY_IMAGE,
    gdb_host: str = config.GDB_HOST,
    gdb_port: int = config.GDB_PORT,
    display: str = config.QEMU_DISPLAY,
) -> dict:
    """
    One-shot helper:
      1. Stops any running QEMU process.
      2. Starts a fresh QEMU instance halted at startup (-S).

    After this, connect GDB with: target remote <host>:<port>
    then call continue_execution to begin booting.
    """
    steps = []

    r = stop_vm()
    steps.append({"action": "stop_vm", **r})

    r = start_vm(
        image_path=image_path,
        gdb_host=gdb_host,
        gdb_port=gdb_port,
        halt_on_start=True,
        display=display,
    )
    steps.append({"action": "start_vm", **r})
    if not r["ok"]:
        return {"ok": False, "error": r["error"], "steps": steps}

    return {
        "ok": True,
        "output": (
            f"QEMU debug session started. "
            f"Connect GDB: target remote {gdb_host}:{gdb_port}"
        ),
        "steps": steps,
    }
