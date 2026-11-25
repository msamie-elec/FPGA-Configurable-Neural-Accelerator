#!/usr/bin/env python3
"""Independent signed INT8 MLP golden model and deterministic RTL test vectors."""
from pathlib import Path
import random

def clamp_i8(value):
    return max(-128, min(127, value))

def infer(inputs, sizes, weights, biases, shift=0):
    """Weights/biases use [layer][output_neuron][input_feature] layout."""
    activation = list(inputs)
    assert 1 <= len(sizes) <= 3 and 1 <= len(inputs) <= 8
    for layer, width in enumerate(sizes):
        assert 1 <= width <= 8
        result = []
        for neuron in range(width):
            accum = biases[layer][neuron]
            for feature, weight in zip(activation, weights[layer][neuron]):
                accum += feature * weight
            val = clamp_i8(accum >> shift)
            if layer != len(sizes)-1:
                val = max(0, val)
            result.append(val)
        activation = result
    winner = max(range(len(activation)), key=lambda i: activation[i])
    return activation, winner

def fixture_model():
    sizes = [8, 4, 2]
    widths = [4] + sizes
    weights = [[[0 for _ in range(widths[l])] for _ in range(widths[l+1])]
               for l in range(3)]
    for i in range(4):
        weights[0][i][i] = 1
        weights[1][i][i] = 1
    weights[2][0][0] = 1
    weights[2][1][1] = 1
    biases = [[0] * w for w in sizes]
    return sizes, weights, biases

def write_vectors(path, count=64):
    rng = random.Random(20261125)
    sizes, weights, biases = fixture_model()
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="ascii") as out:
        for _ in range(count):
            sample = [rng.randint(-128, 127) for _ in range(4)]
            score, winner = infer(sample, sizes, weights, biases)
            packed_features = sum((x & 255) << (8*i) for i,x in enumerate(sample))
            record = packed_features | ((score[0]&255)<<64) | ((score[1]&255)<<72) | (winner<<80)
            out.write(f"{record:022x}\n")
    print(f"Generated {count} Python reference vectors in {path}")

if __name__ == "__main__":
    import sys
    write_vectors(sys.argv[1] if len(sys.argv)>1 else "build/mlp_vectors.hex")
