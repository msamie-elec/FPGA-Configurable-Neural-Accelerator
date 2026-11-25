"""Generate independently scored protocol traffic and run fast/serial RTL simulations."""
import argparse
import binascii
import os
import shutil
import struct
import subprocess
import tempfile
from pathlib import Path

from host.npu import frame, model_image
from host.reference import infer
from verification.fixtures import A, B, BENCH, network, vectors

ROOT = Path(__file__).resolve().parents[1]


class Trace:
    def __init__(self, lanes):
        self.lanes = lanes
        self.events = []
        self.sequence = 0
        self.inferences = 0
        self.jobs = 0
        self.crc = 0

    def command(self, opcode, payload=b"", result=b"\0", corrupt=False):
        self.sequence += 1
        packet = frame(opcode, self.sequence, payload)
        if corrupt:
            packet = packet[:-1] + bytes([packet[-1] ^ 1])
        self.events.extend(packet)
        self.events.extend(0x100 | value for value in frame(opcode | 0x80, self.sequence, result))

    def load(self, image, status=0, bad_crc=False):
        crc = binascii.crc32(image) ^ int(bad_crc)
        self.crc = 0 if status else crc
        self.command(0x10, struct.pack("<II", len(image), crc))
        for offset in range(0, len(image), 124):
            self.command(0x11, struct.pack("<I", offset) + image[offset:offset+124])
        self.command(0x12, result=bytes([status]))
        self.command(0x13, result=struct.pack("<BBI", 0, 4 if status else 1,
                                              0 if status else crc))

    def input(self, x):
        self.command(0x20, struct.pack("<H", len(x)))
        data = struct.pack(f"<{len(x)}b", *x)
        for offset in range(0, len(x), 126):
            self.command(0x21, struct.pack("<H", offset) + data[offset:offset+126])

    def run(self, layers, x, stress_busy=False, check_stats=False):
        self.input(x)
        self.command(0x22)
        self.jobs += 1
        if stress_busy:
            self.command(0x22, result=b"\x05")
            self.command(0x10, struct.pack("<II", 100, 0), b"\x05")
            self.command(0x23, b"\0\0\1", b"\x0b")
            self.command(0x7F, result=b"\x05")
        # Event 0x200 waits on result-valid with a finite timeout in the HDL bench.
        self.events.append(0x200)
        logits = infer(layers, x)
        for offset in range(0, len(logits), 30):
            page = logits[offset:offset+30]
            info = struct.pack("<HB", offset, len(page))
            self.command(0x23, info, b"\0" + info + struct.pack(f"<{len(page)}i", *page))
        if check_stats or stress_busy:
            words, issues, cycles = 0, 0, 0
            for index, layer in enumerate(layers):
                ni, no = len(layer["weights"][0]), len(layer["weights"])
                w, g = (ni+7)//8, (ni+self.lanes-1)//self.lanes
                words += w*no
                issues += g*no
                cycles += no*(1+g+self.lanes.bit_length()-1+4
                              +3*(index+1 < len(layers)))
            self.command(0x30, result=struct.pack("<BBBIIIII", 0, 6, 0, cycles,
                                                 issues, words, self.crc, self.jobs))
        self.inferences += 1


def traces(lanes, serial, trained=None):
    t = Trace(lanes)
    hz = 1843200 if serial == 1 else 100000000
    t.command(1, result=struct.pack("<BBIBBHHHHB", 0, 1, hz, lanes, 4,
                                   256, 256, 16384, 4096, 3))
    if not serial:
        t.command(0x22, result=b"\x06")
        t.command(0x23, b"\0\0\1", b"\x0b")
        t.command(1, result=b"\x01", corrupt=True)
        # Partial frame timeout and recovery. Fixture bench uses a 64-cycle threshold.
        t.events.extend([0xA5, 0x5A, 1, 0x201])
        t.command(0x99, result=b"\x04")
        t.command(1, b"bad", b"\x02")
    shapes = [(3, 2)] if serial == 2 else [A, B, A] if serial else [
        A, B, A, (3, 5), (9, 7, 5, 3, 2), (1, 256), (256, 64), BENCH,
    ]
    for shape in shapes:
        layers = network(shape, 15)
        image = model_image(layers)
        t.load(image)
        if not serial:
            t.command(0x22, result=b"\x0a")
            t.command(0x20, struct.pack("<H", shape[0]))
            t.command(0x21, b"\x01\0\0", b"\x09")
        for vector in vectors(shape[0], 3 if serial else 12, 42):
            t.run(layers, vector, stress_busy=not serial and shape == (256, 64),
                  check_stats=shape == BENCH)
        if not serial:
            t.command(0x22, result=b"\x0a")
            t.command(0x23, struct.pack("<HB", 65535, 2), b"\x08")
    if not serial:
        # Exact rounding tie, ReLU, saturation and signed product extremum.
        corners = [
            {"weights": [[0], [0], [-128], [0]], "bias": [1, -1, 0, 255],
             "multiplier": 1, "shift": 1},
            {"weights": [[1, 1, 1, 1], [-1, -2, -3, -4]], "bias": [0, -10]},
        ]
        image = model_image(corners)
        t.load(image)
        t.run(corners, [-128])
        for byte_index, value in ((0, 0), (56, 1), (40, 8), (52, 2), (len(image)-1, 1)):
            bad = bytearray(image)
            bad[byte_index] = value
            t.load(bad, 7)
        # Corrupt CRC and then a valid-CRC image with INT32_MIN in the bias section.
        t.load(image, 7, bad_crc=True)
        bad = bytearray(image)
        bias_begin = 32 + 64 + struct.unpack_from("<I", image, 16)[0]
        struct.pack_into("<i", bad, bias_begin, -(2**31))
        t.load(bad, 7)
        t.command(0x10, struct.pack("<II", len(image), binascii.crc32(image)))
        t.command(0x12, result=b"\x07")
        t.load(image)
        t.run(corners, [-128])
        wide = [{"weights": [[127, -128]], "bias": [183921],
                 "multiplier": 719003, "shift": 31},
                {"weights": [[1]], "bias": [0]}]
        padding = bytearray(model_image(wide))
        padding[32+64+2] = 0x7f
        t.load(padding)
        t.run(wide, [0, 0], check_stats=True)
        t.command(0x7F)
        t.command(0x22, result=b"\x06")
        t.command(0x23, b"\0\0\1", b"\x0b")
        # A physical reset aborts a long active job and invalidates its model.
        t.load(model_image(network(BENCH,15)))
        t.input([7] * BENCH[0])
        t.command(0x22)
        t.events.append(0x202)
        t.command(0x22, result=b"\x06")
    if trained and not serial:
        layers, test_inputs, _ = trained
        t.load(model_image(layers))
        for vector in test_inputs[:100]:
            t.run(layers, vector)
    return t


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lanes", nargs="+", type=int, choices=(1, 4, 8), default=[1, 4, 8])
    parser.add_argument("--skip-serial", action="store_true")
    parser.add_argument("--trained", action="store_true", help="train optional sklearn fixture")
    args = parser.parse_args()
    trained = None
    if args.trained:
        from verification.trained_digits import train
        trained = train()
        print(trained[2], flush=True)
    compiler = os.environ.get("IVERILOG", "iverilog")
    simulator = os.environ.get("VVP", "vvp")
    for exe in (compiler, simulator):
        if not shutil.which(exe):
            parser.error(f"{exe} not found")
    rtl = sorted((ROOT / "hardware/rtl").rglob("*.sv"))
    with tempfile.TemporaryDirectory() as tmp:
        temp = Path(tmp)
        for lanes in args.lanes:
            executable = temp / "dot.vvp"
            subprocess.run([compiler, "-g2012", "-Wall", "-s", "dot_tb",
                            f"-Pdot_tb.LANES={lanes}", "-o", executable,
                            ROOT / "verification/dot_tb.sv",
                            ROOT / "hardware/rtl/compute/dot_pipeline.sv"], check=True)
            subprocess.run([simulator, executable], check=True)
        for serial, lanes_list in ((0, args.lanes), (1, [] if args.skip_serial else [4]),
                                   (2, [] if args.skip_serial else [4])):
            for lanes in lanes_list:
                trace = traces(lanes, serial, trained)
                events = temp / "events.mem"
                events.write_text("".join(f"{event:03x}\n" for event in trace.events))
                executable = temp / "test.vvp"
                subprocess.run([compiler, "-g2012", "-Wall", "-s", "protocol_tb",
                    f"-Pprotocol_tb.LANES={lanes}", f"-Pprotocol_tb.SERIAL={int(serial)}",
                    "-o", executable, ROOT / "verification/protocol_tb.sv", *rtl], check=True)
                subprocess.run([simulator, executable, f"+EVENTS={events}",
                                f"+COUNT={len(trace.events)}"], check=True)
                print(f"P={lanes}, {'UART pin' if serial else 'byte link'}: "
                      f"mode {serial}: {trace.inferences} complete oracle comparisons", flush=True)


if __name__ == "__main__":
    main()
