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


def _unsupported_native(operation: str) -> dict:
    return {
        "ok": False,
        "backend": "native",
        "error": "unsupported_by_backend",
        "operation": operation,
        "message": (
            f"Operation '{operation}' is not supported by VirtualBox native debugger backend. "
            "Use VBOX_DEBUG_BACKEND=gdb for full breakpoint/memory/disassembly support."
        ),
    }


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

def configure_debug_provider(
    vm_name: str = config.VM_NAME,
    provider: str = config.GDB_PROVIDER,
    host: str = config.GDB_HOST,
    port: int = config.GDB_PORT,
    io_provider: str = config.GDB_IO_PROVIDER,
) -> dict:
    """
    Configure VirtualBox's built-in guest debug provider on *vm_name*.

    The VM **must be powered off** for modifyvm to succeed.
    For provider='gdb', connect with: target remote <host>:<port>
    """
    provider = provider.strip().lower()
    if provider not in ("gdb", "native", "none", "kd"):
        return _err(f"Unsupported debug provider: {provider}")

    if provider == "gdb":
        result = _run(
            "modifyvm", vm_name,
            "--guest-debug-provider", "gdb",
            "--guest-debug-io-provider", io_provider,
            "--guest-debug-address", host,
            "--guest-debug-port", str(port),
        )
    else:
        result = _run(
            "modifyvm", vm_name,
            "--guest-debug-provider", provider,
        )

    if result.returncode != 0:
        return _err(result.stderr or result.stdout)

    if provider == "gdb":
        return _ok(f"Debug provider configured: gdb at {host}:{port}")
    return _ok(f"Debug provider configured: {provider}")


def configure_gdb_stub(
    vm_name: str = config.VM_NAME,
    host: str = config.GDB_HOST,
    port: int = config.GDB_PORT,
) -> dict:
    """Backwards-compatible wrapper for GDB provider setup."""
    return configure_debug_provider(
        vm_name=vm_name,
        provider="gdb",
        host=host,
        port=port,
        io_provider=config.GDB_IO_PROVIDER,
    )


def configure_native_debug(
    vm_name: str = config.VM_NAME,
) -> dict:
    """Configure VirtualBox native debug provider."""
    return configure_debug_provider(vm_name=vm_name, provider="native")


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
    debug_provider: str = config.GDB_PROVIDER,
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

    # --- 3. Configure debug provider ---
    r = configure_debug_provider(
        vm_name=vm_name,
        provider=debug_provider,
        host=gdb_host,
        port=gdb_port,
    )
    steps.append({"action": "configure_debug_provider", "provider": debug_provider, **r})
    if not r["ok"]:
        return {"ok": False, "error": r["error"], "steps": steps}

    # --- 4. Start VM ---
    r = start_vm(vm_name, gui=gui)
    steps.append({"action": "start_vm", **r})
    if not r["ok"]:
        return {"ok": False, "error": r["error"], "steps": steps}

    return {
        "ok": True,
        "output": (
            f"Debug session started with provider '{debug_provider}'. "
            + (f"Connect GDB: target remote {gdb_host}:{gdb_port}" if debug_provider == "gdb" else "")
        ).strip(),
        "steps": steps,
    }


# ---------------------------------------------------------------------------
# Native debugger operations (VBoxManage debugvm)
# ---------------------------------------------------------------------------

def debugvm_getregisters(
    vm_name: str = config.VM_NAME,
    cpu: int = 0,
    reg_names: list[str] | None = None,
) -> dict:
    args = ["debugvm", vm_name, "getregisters", "--cpu", str(cpu)]
    if reg_names:
        args.extend(reg_names)
    result = _run(*args)
    if result.returncode != 0:
        return _err(result.stderr or result.stdout)

    parsed: dict[str, str] = {}
    for line in result.stdout.splitlines():
        match = re.match(r"\s*([A-Za-z0-9_.]+)\s*=\s*([^\s]+)", line)
        if match:
            parsed[match.group(1).lower()] = match.group(2)

    return {
        "ok": True,
        "backend": "native",
        "cpu": cpu,
        "registers": parsed,
        "raw": result.stdout.strip(),
    }


def native_read_registers(vm_name: str = config.VM_NAME, cpu: int = 0) -> dict:
    r = debugvm_getregisters(vm_name=vm_name, cpu=cpu)
    if not r.get("ok"):
        return r

    registers = r.get("registers", {})
    cs_raw = registers.get("cs")
    ip_raw = registers.get("ip") or registers.get("eip") or registers.get("rip")

    flat_ip = None
    try:
        if cs_raw is not None and ip_raw is not None:
            cs_val = int(cs_raw, 0)
            ip_val = int(ip_raw, 0)
            flat_ip = (cs_val << 4) + (ip_val & 0xFFFF)
    except ValueError:
        flat_ip = None

    return {
        "ok": True,
        "backend": "native",
        "registers": registers,
        "cs": cs_raw,
        "ip": ip_raw,
        "flat_ip": f"0x{flat_ip:05X}" if flat_ip is not None else None,
        "raw": r.get("raw"),
    }


def native_connect() -> dict:
    return {
        "ok": True,
        "backend": "native",
        "output": "Native debugger backend does not require an explicit connect step.",
    }


def native_disconnect() -> dict:
    return {
        "ok": True,
        "backend": "native",
        "output": "Native debugger backend does not require an explicit disconnect step.",
    }


def native_continue_execution(vm_name: str = config.VM_NAME) -> dict:
    r = resume_vm(vm_name)
    return {"backend": "native", **r}


def native_interrupt_execution(vm_name: str = config.VM_NAME) -> dict:
    r = pause_vm(vm_name)
    return {"backend": "native", **r}


def native_step_instruction() -> dict:
    return _unsupported_native("step_instruction")


def native_next_instruction() -> dict:
    return _unsupported_native("next_instruction")


def native_set_breakpoint() -> dict:
    return _unsupported_native("set_breakpoint")


def native_set_breakpoint_segoff() -> dict:
    return _unsupported_native("set_breakpoint_segoff")


def native_delete_breakpoint() -> dict:
    return _unsupported_native("delete_breakpoint")


def native_list_breakpoints() -> dict:
    return {
        "ok": False,
        "backend": "native",
        "error": "unsupported_by_backend",
        "operation": "list_breakpoints",
        "breakpoints": [],
        "message": "Native backend does not provide breakpoint enumeration via this MCP interface.",
    }


def native_read_memory() -> dict:
    return _unsupported_native("read_memory")


def native_read_memory_segoff() -> dict:
    return _unsupported_native("read_memory_segoff")


def native_write_memory() -> dict:
    return _unsupported_native("write_memory")


def native_disassemble() -> dict:
    return _unsupported_native("disassemble")
