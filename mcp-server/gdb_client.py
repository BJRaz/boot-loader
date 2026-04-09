"""
gdb_client.py — GDB/MI client for debugging 16-bit real-mode code via the
VirtualBox built-in GDB stub.

Real-mode addressing
--------------------
In 16-bit real mode the CPU uses segment:offset addressing.  The physical
(flat) address is:

    flat = (segment << 4) + offset

VirtualBox's GDB stub exposes *physical* addresses, so every API here that
accepts an address works with flat physical addresses.  Helper functions
``seg_off_to_flat`` and ``flat_to_seg_off`` are provided for conversion.

Typical boot-loader addresses:
    Stage 1 entry:  0x7C00  (CS=0x0000, IP=0x7C00)
    Stage 2 entry:  0x8000  (CS=0x0000, IP=0x8000)
    IVT:            0x0000–0x03FF
    BDA:            0x0400–0x04FF

Usage
-----
    from gdb_client import GdbClient
    gdb = GdbClient()
    gdb.connect()                          # target remote localhost:5037
    gdb.set_breakpoint(0x7C00)             # break at stage-1 entry
    gdb.set_breakpoint_segoff(0x0000, 0x8000)  # break at stage-2 entry
    gdb.continue_execution()
    regs = gdb.read_registers()
    mem  = gdb.read_memory(0x7C00, 16)
    gdb.disconnect()
"""

import socket
import time
import re
from typing import Optional

from pygdbmi.gdbcontroller import GdbController
from pygdbmi.constants import GdbTimeoutError

import config


# ---------------------------------------------------------------------------
# Real-mode addressing helpers (module-level, no instance needed)
# ---------------------------------------------------------------------------

def seg_off_to_flat(segment: int, offset: int) -> int:
    """Convert a real-mode segment:offset pair to a flat physical address."""
    return ((segment & 0xFFFF) << 4) + (offset & 0xFFFF)


def flat_to_seg_off(flat: int, segment: int = 0x0000) -> tuple[int, int]:
    """
    Convert a flat physical address to a segment:offset pair.

    By default uses segment 0 (offset == flat address).  Supply a preferred
    segment to get the canonical offset within that segment.

    Returns (segment, offset).  Raises ValueError if offset would exceed 0xFFFF.
    """
    offset = flat - (segment << 4)
    if offset < 0 or offset > 0xFFFF:
        raise ValueError(
            f"Flat address 0x{flat:05X} cannot be expressed in segment 0x{segment:04X}. "
            f"Computed offset 0x{offset:X} is out of range."
        )
    return segment, offset


def canonical_seg_off(flat: int) -> tuple[int, int]:
    """
    Return the canonical segment:offset for *flat* where offset is always
    in [0, 0x000F] — i.e. the segment absorbs as much as possible.

    Useful for display; not necessarily what the CPU uses.
    """
    segment = (flat >> 4) & 0xFFFF
    offset = flat & 0x000F
    return segment, offset


# ---------------------------------------------------------------------------
# GDB/MI client
# ---------------------------------------------------------------------------

_GDB_TIMEOUT = 10  # seconds for MI responses


class GdbClient:
    """
    Thin wrapper around pygdbmi.GdbController that adds real-mode helpers
    for the VirtualBox GDB stub.

    The client spawns a local ``gdb`` process and connects it to the remote
    VirtualBox stub via ``target remote host:port``.
    """

    def __init__(
        self,
        host: str = config.GDB_HOST,
        port: int = config.GDB_PORT,
    ) -> None:
        self.host = host
        self.port = port
        self._controller: Optional[GdbController] = None
        self._breakpoints: dict[int, str] = {}  # flat_addr -> bp number

    # ------------------------------------------------------------------
    # Connection management
    # ------------------------------------------------------------------

    def connect(self, timeout: float = 15.0) -> dict:
        """
        Spawn a GDB process and connect it to the VirtualBox stub.

        Retries for *timeout* seconds to allow the VM time to boot and
        expose the GDB port.
        """
        if self._controller is not None:
            return {"ok": True, "output": "Already connected."}

        # Wait for the TCP port to become available.
        deadline = time.monotonic() + timeout
        while True:
            try:
                with socket.create_connection((self.host, self.port), timeout=2):
                    break
            except OSError:
                if time.monotonic() >= deadline:
                    return {
                        "ok": False,
                        "error": f"GDB stub at {self.host}:{self.port} not reachable after {timeout}s. "
                                 "Is the VM running with the GDB stub configured?",
                    }
                time.sleep(1)

        try:
            self._controller = GdbController(["gdb", "--interpreter=mi3"])
            # Consume the GDB banner output.
            self._controller.get_gdb_response(timeout_sec=5, raise_error_on_timeout=False)

            # Set architecture to i8086 for correct real-mode register display.
            self._send_cmd("set architecture i8086")

            # Connect to the remote stub.
            resp = self._send_cmd(f"target remote {self.host}:{self.port}")
            return {"ok": True, "output": f"Connected to {self.host}:{self.port}", "detail": resp}
        except Exception as exc:
            self._controller = None
            return {"ok": False, "error": str(exc)}

    def disconnect(self) -> dict:
        """Disconnect from the GDB stub and terminate the local GDB process."""
        if self._controller is None:
            return {"ok": True, "output": "Not connected."}
        try:
            self._send_cmd("disconnect")
            self._controller.exit()
        except Exception:
            pass
        self._controller = None
        self._breakpoints.clear()
        return {"ok": True, "output": "Disconnected."}

    def is_connected(self) -> bool:
        return self._controller is not None

    # ------------------------------------------------------------------
    # Breakpoints
    # ------------------------------------------------------------------

    def set_breakpoint(self, flat_addr: int) -> dict:
        """
        Set a hardware breakpoint at *flat_addr* (physical address).

        Example:
            set_breakpoint(0x7C00)   # stage-1 entry
            set_breakpoint(0x8000)   # stage-2 entry
        """
        if not self._require_connected():
            return self._not_connected()

        resp = self._send_cmd(f"hbreak *0x{flat_addr:05X}")
        # Parse breakpoint number from MI response.
        bp_num = self._parse_bp_number(resp)
        if bp_num:
            self._breakpoints[flat_addr] = bp_num
        return {
            "ok": True,
            "flat_addr": f"0x{flat_addr:05X}",
            "breakpoint": bp_num,
            "detail": resp,
        }

    def set_breakpoint_segoff(self, segment: int, offset: int) -> dict:
        """
        Set a hardware breakpoint at a real-mode segment:offset address.

        Converts to flat physical address automatically.
        """
        flat = seg_off_to_flat(segment, offset)
        result = self.set_breakpoint(flat)
        result["segment"] = f"0x{segment:04X}"
        result["offset"] = f"0x{offset:04X}"
        return result

    def delete_breakpoint(self, flat_addr: int) -> dict:
        """Remove the breakpoint previously set at *flat_addr*."""
        if not self._require_connected():
            return self._not_connected()

        bp_num = self._breakpoints.get(flat_addr)
        if bp_num is None:
            return {"ok": False, "error": f"No tracked breakpoint at 0x{flat_addr:05X}."}

        resp = self._send_cmd(f"delete {bp_num}")
        del self._breakpoints[flat_addr]
        return {"ok": True, "output": f"Breakpoint {bp_num} deleted.", "detail": resp}

    def list_breakpoints(self) -> dict:
        """Return all tracked breakpoints as a list of {flat_addr, bp_num} dicts."""
        return {
            "ok": True,
            "breakpoints": [
                {"flat_addr": f"0x{addr:05X}", "number": num}
                for addr, num in self._breakpoints.items()
            ],
        }

    # ------------------------------------------------------------------
    # Execution control
    # ------------------------------------------------------------------

    def continue_execution(self) -> dict:
        """Resume execution (GDB ``continue``)."""
        if not self._require_connected():
            return self._not_connected()
        resp = self._send_cmd("-exec-continue")
        return {"ok": True, "output": "Continuing.", "detail": resp}

    def step_instruction(self) -> dict:
        """Single-step one machine instruction (GDB ``stepi``)."""
        if not self._require_connected():
            return self._not_connected()
        resp = self._send_cmd("-exec-step-instruction")
        return {"ok": True, "output": "Stepped one instruction.", "detail": resp}

    def next_instruction(self) -> dict:
        """Step *over* the next instruction (GDB ``nexti``)."""
        if not self._require_connected():
            return self._not_connected()
        resp = self._send_cmd("-exec-next-instruction")
        return {"ok": True, "output": "Stepped over one instruction.", "detail": resp}

    def interrupt_execution(self) -> dict:
        """Halt a running VM (GDB ``interrupt`` / Ctrl-C equivalent)."""
        if not self._require_connected():
            return self._not_connected()
        resp = self._send_cmd("-exec-interrupt")
        return {"ok": True, "output": "Execution interrupted.", "detail": resp}

    # ------------------------------------------------------------------
    # Register access
    # ------------------------------------------------------------------

    def read_registers(self) -> dict:
        """
        Read all CPU registers.

        Returns a dict with keys ``registers`` (list of {name, value} dicts)
        and helper keys ``cs``, ``ip``, ``flat_ip`` for quick access.

        ``flat_ip`` is the current flat physical address:
            flat_ip = (CS << 4) + IP
        """
        if not self._require_connected():
            return self._not_connected()

        resp = self._send_cmd("-data-list-register-names")
        names_msg = self._find_result(resp, "register-names")

        resp2 = self._send_cmd("-data-list-register-values x")
        values_msg = self._find_result(resp2, "register-values")

        if names_msg is None or values_msg is None:
            return {"ok": False, "error": "Could not parse register response.", "detail": resp + resp2}

        names = names_msg  # list of strings
        values = values_msg  # list of {number, value} dicts

        registers = {}
        for v in values:
            idx = int(v["number"])
            if idx < len(names) and names[idx]:
                registers[names[idx]] = v["value"]

        # Compute flat CS:IP physical address for convenience.
        cs_raw = registers.get("cs", "0x0")
        ip_raw = registers.get("pc") or registers.get("ip", "0x0")
        try:
            cs_val = int(cs_raw, 16)
            ip_val = int(ip_raw, 16)
            flat_ip = seg_off_to_flat(cs_val, ip_val)
        except (ValueError, TypeError):
            flat_ip = None

        return {
            "ok": True,
            "registers": registers,
            "cs": cs_raw,
            "ip": ip_raw,
            "flat_ip": f"0x{flat_ip:05X}" if flat_ip is not None else None,
        }

    # ------------------------------------------------------------------
    # Memory access
    # ------------------------------------------------------------------

    def read_memory(self, flat_addr: int, length: int = 16) -> dict:
        """
        Read *length* bytes from flat physical address *flat_addr*.

        Returns:
            {
              "ok": True,
              "flat_addr": "0x7C00",
              "bytes": [0xFA, 0xFC, ...],
              "hex": "FA FC ...",
              "ascii": "...."
            }
        """
        if not self._require_connected():
            return self._not_connected()

        resp = self._send_cmd(
            f"-data-read-memory-bytes 0x{flat_addr:05X} {length}"
        )
        mem_msg = self._find_result(resp, "memory")

        if mem_msg is None or not mem_msg:
            return {"ok": False, "error": "Could not read memory.", "detail": resp}

        # mem_msg is a list of {begin, offset, end, contents} dicts.
        raw_hex = mem_msg[0].get("contents", "")
        byte_list = [int(raw_hex[i:i+2], 16) for i in range(0, len(raw_hex), 2)]
        hex_str = " ".join(f"{b:02X}" for b in byte_list)
        ascii_str = "".join(chr(b) if 0x20 <= b < 0x7F else "." for b in byte_list)

        return {
            "ok": True,
            "flat_addr": f"0x{flat_addr:05X}",
            "length": len(byte_list),
            "bytes": byte_list,
            "hex": hex_str,
            "ascii": ascii_str,
        }

    def read_memory_segoff(self, segment: int, offset: int, length: int = 16) -> dict:
        """Read memory at a real-mode segment:offset address."""
        flat = seg_off_to_flat(segment, offset)
        result = self.read_memory(flat, length)
        result["segment"] = f"0x{segment:04X}"
        result["offset"] = f"0x{offset:04X}"
        return result

    def write_memory(self, flat_addr: int, data: list[int]) -> dict:
        """
        Write *data* (list of byte ints) to flat physical address *flat_addr*.

        Use with caution — modifying memory while the VM runs may cause
        unpredictable behaviour.
        """
        if not self._require_connected():
            return self._not_connected()

        hex_str = "".join(f"{b:02x}" for b in data)
        resp = self._send_cmd(
            f"-data-write-memory-bytes 0x{flat_addr:05X} {hex_str}"
        )
        return {"ok": True, "output": f"Wrote {len(data)} bytes to 0x{flat_addr:05X}.", "detail": resp}

    # ------------------------------------------------------------------
    # Disassembly
    # ------------------------------------------------------------------

    def disassemble(self, flat_addr: int, count: int = 10) -> dict:
        """
        Disassemble *count* instructions starting at *flat_addr*.

        Uses GDB's ``x/Ni`` format (N instructions, i=instruction).
        Returns a list of instruction strings.
        """
        if not self._require_connected():
            return self._not_connected()

        resp = self._send_cmd(f"x/{count}i 0x{flat_addr:05X}")
        # Collect console-stream lines.
        lines = [
            msg["payload"].rstrip("\\n").rstrip("\n")
            for msg in resp
            if msg.get("type") == "console" and msg.get("payload")
        ]
        return {
            "ok": True,
            "flat_addr": f"0x{flat_addr:05X}",
            "instructions": lines,
        }

    # ------------------------------------------------------------------
    # Internal helpers
    # ------------------------------------------------------------------

    def _send_cmd(self, cmd: str) -> list:
        """Send a GDB/MI command and return the response messages."""
        try:
            self._controller.write(cmd, timeout_sec=_GDB_TIMEOUT, raise_error_on_timeout=False)
            return self._controller.get_gdb_response(timeout_sec=_GDB_TIMEOUT, raise_error_on_timeout=False) or []
        except GdbTimeoutError:
            return [{"type": "error", "payload": f"Timeout waiting for response to: {cmd}"}]
        except Exception as exc:
            return [{"type": "error", "payload": str(exc)}]

    @staticmethod
    def _find_result(msgs: list, key: str):
        """Extract a named payload from a GDB/MI result message list."""
        for msg in msgs:
            if msg.get("type") == "result" and msg.get("message") == "done":
                payload = msg.get("payload") or {}
                if key in payload:
                    return payload[key]
        return None

    @staticmethod
    def _parse_bp_number(msgs: list) -> Optional[str]:
        """Parse the breakpoint number from a -break-insert or hbreak response."""
        for msg in msgs:
            payload = msg.get("payload") or {}
            bkpt = payload.get("bkpt") or {}
            if "number" in bkpt:
                return bkpt["number"]
            # Fallback: scan console output for 'Breakpoint N at ...'
            if msg.get("type") == "console":
                m = re.search(r"Breakpoint\s+(\d+)", msg.get("payload", ""))
                if m:
                    return m.group(1)
        return None

    def _require_connected(self) -> bool:
        return self._controller is not None

    @staticmethod
    def _not_connected() -> dict:
        return {"ok": False, "error": "GDB client is not connected. Call connect() first."}
