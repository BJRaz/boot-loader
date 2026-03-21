"""
vbox.py — thin subprocess wrappers around VBoxManage for VM lifecycle control.

Every public function returns a dict:
    {"ok": True,  "output": str}   on success
    {"ok": False, "error":  str}   on failure

This keeps all VBoxManage invocations in one place and makes the MCP tool
layer trivial to test / mock.
"""

import subprocess
import re
from pathlib import Path
from typing import Union

import config


# ---------------------------------------------------------------------------
# Internal helper
# ---------------------------------------------------------------------------

def _run(*args: str) -> "subprocess.CompletedProcess[str]":
    """Run VBoxManage with the given arguments, capturing output."""
    cmd = ["VBoxManage"] + list(args)
    return subprocess.run(
        cmd,
        capture_output=True,
        text=True,
    )


def _ok(output: str) -> dict:
    return {"ok": True, "output": output.strip()}


def _err(msg: str) -> dict:
    return {"ok": False, "error": msg.strip()}


# ---------------------------------------------------------------------------
# VM state
# ---------------------------------------------------------------------------

def get_vm_state(vm_name: str = config.VM_NAME) -> dict:
    """
    Return the current power state of the VM.

    Parsed state string examples: "running", "poweroff", "saved", "aborted".
    """
    result = _run("showvminfo", vm_name, "--machinereadable")
    if result.returncode != 0:
        return _err(result.stderr or result.stdout)

    for line in result.stdout.splitlines():
        if line.startswith("VMState="):
            state = line.split("=", 1)[1].strip().strip('"')
            return {"ok": True, "vm_name": vm_name, "state": state, "output": result.stdout.strip()}

    return _err(f"Could not parse VMState from showvminfo output:\n{result.stdout}")


# ---------------------------------------------------------------------------
# Floppy image
# ---------------------------------------------------------------------------

def attach_floppy(
    image_path: Union[str, Path] = config.FLOPPY_IMAGE,
    vm_name: str = config.VM_NAME,
    storage_ctl: str = config.STORAGE_CTL,
    port: int = config.STORAGE_PORT,
    device: int = config.STORAGE_DEVICE,
) -> dict:
    """
    Attach *image_path* as the floppy medium for *vm_name*.

    The VM must be powered off before calling this.
    """
    image_path = str(Path(image_path).resolve())
    result = _run(
        "storageattach", vm_name,
        "--storagectl", storage_ctl,
        "--port", str(port),
        "--device", str(device),
        "--type", "fdd",
        "--medium", image_path,
    )
    if result.returncode != 0:
        return _err(result.stderr or result.stdout)
    return _ok(f"Floppy attached: {image_path}")


def detach_floppy(
    vm_name: str = config.VM_NAME,
    storage_ctl: str = config.STORAGE_CTL,
    port: int = config.STORAGE_PORT,
    device: int = config.STORAGE_DEVICE,
) -> dict:
    """Remove the floppy medium from *vm_name* (set to 'none')."""
    result = _run(
        "storageattach", vm_name,
        "--storagectl", storage_ctl,
        "--port", str(port),
        "--device", str(device),
        "--type", "fdd",
        "--medium", "none",
    )
    if result.returncode != 0:
        return _err(result.stderr or result.stdout)
    return _ok("Floppy detached.")


# ---------------------------------------------------------------------------
# GDB stub configuration
# ---------------------------------------------------------------------------

def configure_gdb_stub(
    vm_name: str = config.VM_NAME,
    host: str = config.GDB_HOST,
    port: int = config.GDB_PORT,
) -> dict:
    """
    Configure VirtualBox's built-in GDB stub on *vm_name*.

    The VM **must be powered off** for modifyvm to succeed.
    After this call connect GDB with:  target remote <host>:<port>
    """
    result = _run(
        "modifyvm", vm_name,
        "--guest-debug-provider", config.GDB_PROVIDER,
        "--guest-debug-io-provider", config.GDB_IO_PROVIDER,
        "--guest-debug-address", host,
        "--guest-debug-port", str(port),
    )
    if result.returncode != 0:
        return _err(result.stderr or result.stdout)
    return _ok(f"GDB stub configured: {host}:{port}")


def disable_gdb_stub(vm_name: str = config.VM_NAME) -> dict:
    """Remove the GDB stub from *vm_name* (set provider to 'none')."""
    result = _run(
        "modifyvm", vm_name,
        "--guest-debug-provider", "none",
    )
    if result.returncode != 0:
        return _err(result.stderr or result.stdout)
    return _ok("GDB stub disabled.")


# ---------------------------------------------------------------------------
# VM lifecycle
# ---------------------------------------------------------------------------

def start_vm(
    vm_name: str = config.VM_NAME,
    gui: bool = config.START_GUI,
) -> dict:
    """
    Start *vm_name*.

    Parameters
    ----------
    gui : bool
        True  → launch with a graphical window (``--type gui``).
        False → launch headless (``--type headless``).
    """
    vm_type = "gui" if gui else "headless"
    result = _run("startvm", vm_name, "--type", vm_type)
    if result.returncode != 0:
        return _err(result.stderr or result.stdout)
    return _ok(f"VM '{vm_name}' started ({vm_type}).")


def stop_vm(vm_name: str = config.VM_NAME) -> dict:
    """Power off *vm_name* immediately (ACPI off)."""
    result = _run("controlvm", vm_name, "poweroff")
    if result.returncode != 0:
        return _err(result.stderr or result.stdout)
    return _ok(f"VM '{vm_name}' powered off.")


def reset_vm(vm_name: str = config.VM_NAME) -> dict:
    """Hard reset *vm_name* (equivalent to pressing the reset button)."""
    result = _run("controlvm", vm_name, "reset")
    if result.returncode != 0:
        return _err(result.stderr or result.stdout)
    return _ok(f"VM '{vm_name}' reset.")


def pause_vm(vm_name: str = config.VM_NAME) -> dict:
    """Pause execution of *vm_name*."""
    result = _run("controlvm", vm_name, "pause")
    if result.returncode != 0:
        return _err(result.stderr or result.stdout)
    return _ok(f"VM '{vm_name}' paused.")


def resume_vm(vm_name: str = config.VM_NAME) -> dict:
    """Resume a paused *vm_name*."""
    result = _run("controlvm", vm_name, "resume")
    if result.returncode != 0:
        return _err(result.stderr or result.stdout)
    return _ok(f"VM '{vm_name}' resumed.")


# ---------------------------------------------------------------------------
# Convenience: full debug-start sequence
# ---------------------------------------------------------------------------

def prepare_debug_session(
    image_path: Union[str, Path] = config.FLOPPY_IMAGE,
    vm_name: str = config.VM_NAME,
    gdb_host: str = config.GDB_HOST,
    gdb_port: int = config.GDB_PORT,
    gui: bool = config.START_GUI,
) -> dict:
    """
    One-shot helper that:
      1. Powers off the VM (if running).
      2. Attaches the floppy image.
      3. Configures the GDB stub.
      4. Starts the VM.

    Returns a summary dict with keys ``ok``, ``steps``, and optionally ``error``.
    """
    steps = []

    # --- 1. Stop VM if running ---
    state_result = get_vm_state(vm_name)
    if not state_result["ok"]:
        return {"ok": False, "error": state_result["error"], "steps": steps}

    if state_result["state"] not in ("poweroff", "aborted", "saved"):
        r = stop_vm(vm_name)
        steps.append({"action": "stop_vm", **r})
        if not r["ok"]:
            return {"ok": False, "error": r["error"], "steps": steps}
    else:
        steps.append({"action": "stop_vm", "ok": True, "output": "VM already stopped."})

    # --- 2. Attach floppy ---
    r = attach_floppy(image_path, vm_name)
    steps.append({"action": "attach_floppy", **r})
    if not r["ok"]:
        return {"ok": False, "error": r["error"], "steps": steps}

    # --- 3. Configure GDB stub ---
    r = configure_gdb_stub(vm_name, gdb_host, gdb_port)
    steps.append({"action": "configure_gdb_stub", **r})
    if not r["ok"]:
        return {"ok": False, "error": r["error"], "steps": steps}

    # --- 4. Start VM ---
    r = start_vm(vm_name, gui=gui)
    steps.append({"action": "start_vm", **r})
    if not r["ok"]:
        return {"ok": False, "error": r["error"], "steps": steps}

    return {
        "ok": True,
        "output": f"Debug session started. Connect GDB: target remote {gdb_host}:{gdb_port}",
        "steps": steps,
    }
