"""V1 image exporter and stop-and-wait UART client."""
import argparse
import binascii
import json
import struct
import time
from pathlib import Path

STATUS = (
    "OK", "BAD_CRC", "BAD_LEN", "BAD_VERSION", "UNSUPPORTED", "BUSY",
    "NO_MODEL", "MODEL_INVALID", "OUT_OF_RANGE", "BAD_SEQUENCE",
    "INPUT_INCOMPLETE", "RESULT_NOT_READY", "INTERNAL",
)


def model_image(layers):
    """Pack already quantised dense parameters, in output-neuron-major order."""
    if not 1 <= len(layers) <= 4:
        raise ValueError("Expected one to four layers")
    descriptors, weights, biases, quants = (bytearray() for _ in range(4))
    previous = None
    first_input = None
    for i, layer in enumerate(layers):
        rows, bias = layer["weights"], layer["bias"]
        if not rows or not rows[0]:
            raise ValueError("Layer must have nonzero dimensions")
        ni, no = len(rows[0]), len(rows)
        if not 1 <= ni <= 256 or not 1 <= no <= 256 or len(bias) != no:
            raise ValueError("Layer dimensions or bias length invalid")
        if previous is not None and ni != previous:
            raise ValueError("Layer dimensions do not chain")
        if first_input is None:
            first_input = ni
        last = i == len(layers) - 1
        m, s = layer.get("multiplier", 0), layer.get("shift", 0)
        if (type(m) is not int or type(s) is not int
                or (last and (m or s))
                or (not last and not (1 <= m <= 0x7FFFFFFF and 0 <= s <= 31))):
            raise ValueError("Invalid quantisation record")
        stride = (ni + 7) // 8
        descriptors.extend(struct.pack(
            "<BBHHHIIIHHII", 2 if last else 1, 0, 0, ni, no,
            len(weights), len(biases), len(quants), stride, 0, 0, 0))
        for row, b in zip(rows, bias):
            if len(row) != ni or any(type(x) is not int or not -128 <= x <= 127 for x in row):
                raise ValueError("Invalid INT8 weight row")
            if type(b) is not int or abs(b) + 16384 * ni > 0x7FFFFFFF:
                raise ValueError("Bias exceeds conservative accumulator bound")
            weights.extend(struct.pack(f"<{ni}b", *row))
            weights.extend(bytes(8 * stride - ni))
            biases.extend(struct.pack("<i", b))
        quants.extend(struct.pack("<IB3x", m, s))
        previous = no
    if len(weights) > 16384 or len(biases) > 4096:
        raise ValueError("Model exceeds FPGA memory budget")
    return (struct.pack("<4sBBBBHHIIIII", b"NPU1", 1, 0, len(layers), 0,
                        first_input, previous, len(descriptors), len(weights),
                        len(biases), len(quants), 0)
            + descriptors + weights + biases + quants)


def frame(opcode, sequence, payload=b""):
    if len(payload) > 128:
        raise ValueError("UART payload exceeds 128 bytes")
    body = struct.pack("<BBHH", 1, opcode, sequence, len(payload)) + payload
    return b"\xa5\x5a" + body + struct.pack("<H", binascii.crc_hqx(body, 0xFFFF))


class Client:
    def __init__(self, port):
        self.port = port
        self.sequence = 0

    def read_exact(self, length):
        data = self.port.read(length)
        if len(data) != length:
            raise TimeoutError("Incomplete reply. Reset the board and reload before retrying.")
        return data

    def command(self, opcode, payload=b""):
        self.sequence = (self.sequence + 1) & 0xFFFF
        self.port.write(frame(opcode, self.sequence, payload))
        header = self.read_exact(8)
        version, response, sequence, length = struct.unpack("<BBHH", header[2:])
        if (header[:2], version, response, sequence) != (
                b"\xa5\x5a", 1, opcode | 0x80, self.sequence) or not 1 <= length <= 128:
            raise ValueError("Unexpected response header")
        body = self.read_exact(length)
        crc, = struct.unpack("<H", self.read_exact(2))
        if binascii.crc_hqx(header[2:] + body, 0xFFFF) != crc:
            raise ValueError("Response CRC mismatch")
        code = body[0]
        if code:
            raise RuntimeError(STATUS[code] if code < len(STATUS) else f"status {code}")
        return body[1:]

    def caps(self):
        names = ("version", "clock_hz", "lanes", "max_layers", "max_input",
                 "max_output", "weight_bytes", "bias_bytes", "ops")
        return dict(zip(names, struct.unpack("<BIBBHHHHB", self.command(0x01))))

    def stats(self):
        names = ("flags", "status", "cycles", "issues", "word_reads", "model_crc", "job_id")
        return dict(zip(names, struct.unpack("<BBIIIII", self.command(0x30))))

    def upload(self, image):
        self.command(0x10, struct.pack("<II", len(image), binascii.crc32(image)))
        for offset in range(0, len(image), 124):
            self.command(0x11, struct.pack("<I", offset) + image[offset:offset+124])
        self.command(0x12)
        flags, crc = struct.unpack("<BI", self.command(0x13))
        if not flags & 1 or crc != binascii.crc32(image):
            raise ValueError("Unexpected committed model fingerprint")

    def infer(self, vector, output_count):
        if not 1 <= output_count <= 256:
            raise ValueError("Invalid output count")
        data = struct.pack(f"<{len(vector)}b", *vector)
        self.command(0x20, struct.pack("<H", len(data)))
        for offset in range(0, len(data), 126):
            self.command(0x21, struct.pack("<H", offset) + data[offset:offset+126])
        self.command(0x22)
        deadline = time.monotonic() + 5
        while True:
            stats = self.stats()
            if stats["flags"] & 2:
                break
            if time.monotonic() >= deadline:
                raise TimeoutError("Inference did not complete")
        logits = []
        for offset in range(0, output_count, 30):
            count = min(30, output_count - offset)
            page = self.command(0x23, struct.pack("<HB", offset, count))
            if page[:3] != struct.pack("<HB", offset, count):
                raise ValueError("Result page metadata mismatch")
            logits.extend(struct.unpack(f"<{count}i", page[3:]))
        return logits, stats


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="action", required=True)
    pack = sub.add_parser("pack")
    pack.add_argument("model", type=Path)
    pack.add_argument("output", type=Path)
    run = sub.add_parser("run")
    run.add_argument("port")
    run.add_argument("model", type=Path)
    run.add_argument("input", type=Path)
    args = parser.parse_args()
    if args.action == "pack":
        args.output.write_bytes(model_image(json.loads(args.model.read_text())))
        return
    import serial

    image = args.model.read_bytes()
    out_dim, = struct.unpack_from("<H", image, 10)
    with serial.Serial(args.port, 115200, timeout=2, write_timeout=2) as port:
        port.reset_input_buffer()
        device = Client(port)
        caps = device.caps()
        start = time.perf_counter()
        device.upload(image)
        load_ms = (time.perf_counter() - start) * 1000
        start = time.perf_counter()
        logits, stats = device.infer(json.loads(args.input.read_text()), out_dim)
        print(json.dumps({"caps": caps, "logits": logits, "stats": stats,
                          "load_ms": load_ms, "job_ms": (time.perf_counter()-start)*1000}))


if __name__ == "__main__":
    main()
