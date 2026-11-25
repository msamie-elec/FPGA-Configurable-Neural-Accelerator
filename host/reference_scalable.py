#!/usr/bin/env python3
"""Independent INT8 fixed-point golden vectors for scalable FPGA MLP.
Bit allocation per record: [324:323] mode, [322:67] features,
[66:3] outputs, [2:0] argmax. All files use $readmemh-compatible hex.
"""
from pathlib import Path
import random
import sys

CONFIGS = [
    (4, (8, 4, 2)),
    (8, (16, 8, 2)),
    (32, (32, 32, 32, 8)),
]
SHIFT = 4


def weights(l, neuron, feature):
    return ((l * 11 + neuron * 7 + feature * 13) % 9) - 4


def bias(l, neuron):
    return ((l * 19 + neuron * 5) % 17) - 8


def infer(sample, widths):
    a = sample[:]
    for layer, output_width in enumerate(widths):
        next_a = []
        for neuron in range(output_width):
            dot = bias(layer, neuron)
            for i, v in enumerate(a):
                dot += v * weights(layer, neuron, i)
            z = max(-128, min(127, dot >> SHIFT))
            if layer != len(widths) - 1:
                z = max(0, z)
            next_a.append(z)
        a = next_a
    winner = max(range(len(a)), key=lambda i: a[i])
    return a, winner


def main(folder):
    folder = Path(folder)
    folder.mkdir(parents=True, exist_ok=True)
    with (folder / "scalable_weights.hex").open("w") as f:
        for layer in range(4):
            for neuron in range(32):
                for feature in range(32):
                    f.write(f"{weights(layer, neuron, feature) & 255:02x}\n")
    with (folder / "scalable_biases.hex").open("w") as f:
        for layer in range(4):
            for neuron in range(32):
                f.write(f"{bias(layer, neuron) & 0xffffffff:08x}\n")
    rng = random.Random(20261125)
    cases = 0
    with (folder / "scalable_vectors.hex").open("w") as f:
        for mode, (inputs, widths) in enumerate(CONFIGS):
            samples = [
                [0] * inputs,
                [127] * inputs,
                [-128] * inputs,
                [i % 7 - 3 for i in range(inputs)],
            ]
            for _ in range(12):
                samples.append([rng.randrange(-128, 128) for _ in range(inputs)])
            for sample in samples:
                score, winner = infer(sample, widths)
                packed_input = sum((x & 255) << (8 * i) for i, x in enumerate(sample))
                packed_output = sum((x & 255) << (8 * i) for i, x in enumerate(score))
                record = (mode << 323) | (packed_input << 67) | (packed_output << 3) | winner
                f.write(f"{record:082x}\n")
                cases += 1
    print(f"GOLDEN MODEL: generated {cases} cases, 4096 weights and 128 biases")


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "build")
