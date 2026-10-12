"""
sen0628.py -- minimal UART driver for the DFRobot SEN0628 8x8 ToF sensor

Talks to the sensor's RP2040 over UART5 (GPIO 12 TX, GPIO 13 RX) with the
request/response protocol of DFRobot's Arduino library, without that
library's Python port (which sends packets in one burst and gets no
answer over UART).

Protocol (from DFRobot_MatrixLidar.cpp):
    request   55 | lenH lenL | cmd | args...      len = len(args) + 1
    response  status | cmd | lenL lenH | data...  status 0x53 ok, 0x63 failed

Findings during commissioning (2026-10-07):
    - Request bytes must be written one at a time (write + flush each);
      a single 8-byte burst gets no answer. 0.2 ms extra gap is the default.
    - The first command after power-up can be ignored -> retry.
    - After switching the matrix mode, wait 5 s before fetching data.
    - Distances are little-endian uint16 in mm; 4000 marks an invalid zone.
    - Frame rate is set by the sensor firmware, not by the link:
      8x8 ~7.4 fps (136 ms), 4x4 25 fps (40 ms), no duplicate frames.
"""

import struct
import time

import serial

CMD_SETMODE = 0x01
CMD_ALLDATA = 0x02
STATUS_OK = 0x53
STATUS_FAILED = 0x63


class SEN0628:
    def __init__(self, port="/dev/ttyAMA5", byte_gap=0.0002, timeout=0.5):
        self.ser = serial.Serial(port, 115200, timeout=timeout)
        self.byte_gap = byte_gap
        self.size = 8

    def _send(self, cmd, args=()):
        n = len(args) + 1
        for b in bytes([0x55, n >> 8, n & 0xFF, cmd, *args]):
            self.ser.write(bytes([b]))
            self.ser.flush()
            if self.byte_gap:
                time.sleep(self.byte_gap)

    def _recv(self, cmd, timeout=2.0):
        t = time.monotonic()
        while time.monotonic() - t < timeout:
            b = self.ser.read(1)
            if b and b[0] in (STATUS_OK, STATUS_FAILED):
                hdr = self.ser.read(3)
                if len(hdr) < 3 or hdr[0] != cmd:
                    return None
                n = hdr[1] | hdr[2] << 8
                data = self.ser.read(n)
                if b[0] == STATUS_OK and len(data) == n:
                    return data
                return None
        return None

    def set_mode(self, size=8, retries=5, settle=5.0):
        """size 8 -> 8x8 zones, size 4 -> 4x4 zones."""
        self.ser.reset_input_buffer()
        for _ in range(retries):
            self._send(CMD_SETMODE, (0, 0, 0, size))
            if self._recv(CMD_SETMODE) is not None:
                self.size = size
                time.sleep(settle)
                return True
            time.sleep(1)
        return False

    def frame(self):
        """One frame as a flat tuple of distances in mm, or None."""
        self._send(CMD_ALLDATA)
        d = self._recv(CMD_ALLDATA)
        zones = self.size * self.size
        if d is None or len(d) != 2 * zones:
            return None
        return struct.unpack(f"<{zones}H", d)
