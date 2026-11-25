"""Host driver for the Arty A7 neural accelerator's framed UART protocol.

Install pyserial to open a real port; the packet/response encoding itself needs
no third-party packages, so it can be unit-tested with a fake serial transport.
"""
from __future__ import annotations

from dataclasses import dataclass

SOF_REQUEST = 0xA5
SOF_REPLY = 0x5A
REPLY_BYTES = 13
WEIGHT = 0x57
BIAS = 0x42
CONFIGURE = 0x43
INFER = 0x49
PING = 0x50
CYCLES = 0x54


class ProtocolError(RuntimeError):
    pass


def signed_byte(number: int) -> int:
    if not -128 <= number <= 127:
        raise ValueError(f"INT8 out of range: {number}")
    return number & 255


def pack_request(command: int, payload: bytes = b"") -> bytes:
    check = command
    for b in payload:
        check ^= b
    return bytes((SOF_REQUEST, command)) + payload + bytes((check,))


@dataclass(frozen=True)
class Prediction:
    class_index: int
    scores: tuple[int, ...]


def decode_reply(data: bytes, command: int) -> tuple[int, Prediction]:
    if len(data) != REPLY_BYTES:
        raise ProtocolError(f"Expected {REPLY_BYTES} response bytes; got {len(data)}")
    if data[0] != SOF_REPLY or data[1] != command:
        raise ProtocolError(f"Wrong response header or command: {data.hex(' ')}")
    check = 0
    for byte in data[1:-1]:
        check ^= byte
    if check != data[-1]:
        raise ProtocolError("Response checksum mismatch")
    scores = tuple(x if x < 128 else x-256 for x in data[4:12])
    return data[2], Prediction(data[3], scores)


class NpuBoard:
    def __init__(self, serial_transport):
        self.serial = serial_transport

    @classmethod
    def open(cls, port: str, baud: int = 115200, timeout: float = 2.0):
        import serial
        return cls(serial.Serial(port, baudrate=baud, timeout=timeout,
                                 write_timeout=timeout))

    def close(self):
        self.serial.close()

    def exchange(self, command: int, payload: bytes = b"") -> Prediction:
        self.serial.write(pack_request(command, payload))
        self.serial.flush()
        reply = self.serial.read(REPLY_BYTES)
        status, result = decode_reply(reply, command)
        if status:
            messages = {1: "checksum rejected", 2: "unknown command",
                        3: "invalid NPU topology"}
            raise ProtocolError(messages.get(status, f"status {status}"))
        return result

    def ping(self):
        self.exchange(PING)

    def read_cycle_count(self) -> int:
        """Return previous inference dispatch-to-valid FPGA clock cycles.

        Requires UART firmware implementing command 0x54, not legacy bitstream.
        This counter excludes UART frame transfer and host scheduling latency.
        """
        reply = self.exchange(CYCLES)
        return sum((value & 255) << (8*i) for i,value in enumerate(reply.scores[:4]))

    def write_weight(self, address: int, value: int):
        if not 0 <= address < 4096:
            raise ValueError("Weight address must be 0..4095")
        payload = bytes((address & 255, (address >> 8) & 15, signed_byte(value)))
        self.exchange(WEIGHT, payload)

    def write_bias(self, address: int, value: int):
        if not 0 <= address < 128:
            raise ValueError("Bias address must be 0..127")
        if not -(1 << 31) <= value <= (1 << 31)-1:
            raise ValueError("INT32 bias out of range")
        self.exchange(BIAS, bytes((address,)) + value.to_bytes(4,"little",signed=True))

    def configure(self, inputs: int, widths: tuple[int, ...], shift: int = 4):
        if not 1 <= inputs <= 32 or not 1 <= len(widths) <= 4:
            raise ValueError("Unsupported input or number of layers")
        if any(not 1 <= n <= 32 for n in widths) or widths[-1] > 8:
            raise ValueError("Hidden layers 1..32; final layer 1..8")
        if not 0 <= shift <= 15:
            raise ValueError("Shift must be 0..15")
        sizes = list(widths) + [1] * (4 - len(widths))
        self.exchange(CONFIGURE, bytes([len(widths), inputs, *sizes, shift]))

    def infer(self, features: list[int] | tuple[int, ...]) -> Prediction:
        if len(features) > 32:
            raise ValueError("At most 32 input features")
        packed = bytes(signed_byte(int(x)) for x in features)
        packed += bytes(32-len(features))
        return self.exchange(INFER, packed)

    def load_demo_model(self, inputs: int, widths: tuple[int, ...], progress=None):
        """Load deterministic example weights; NOT a trained anomaly detector."""
        from reference_scalable import weights, bias
        previous = inputs
        total = sum(w*previous for w,previous in zip(widths,(inputs,)+widths[:-1]))
        completed = 0
        for layer, neurons in enumerate(widths):
            for neuron in range(neurons):
                for feature in range(previous):
                    addr = layer*1024+neuron*32+feature
                    self.write_weight(addr, weights(layer, neuron, feature))
                    completed += 1
                    if progress and (completed % 32 == 0 or completed == total):
                        progress(completed,total)
                self.write_bias(layer*32+neuron, bias(layer, neuron))
            previous = neurons
        self.configure(inputs, widths, shift=4)
