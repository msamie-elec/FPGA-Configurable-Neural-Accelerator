"""Deterministic workloads, independent of the wire encoding."""
import random


def network(shape, seed):
    rng = random.Random(seed)
    layers = []
    for index, (ni, no) in enumerate(zip(shape, shape[1:])):
        layer = {
            "weights": [[rng.randint(-128, 127) for _ in range(ni)] for _ in range(no)],
            "bias": [rng.randint(-257, 257) for _ in range(no)],
        }
        if index < len(shape) - 2:
            layer.update(multiplier=rng.randint(1, 5), shift=rng.randint(8, 12))
        layers.append(layer)
    return layers


def vectors(width, count, seed):
    rng = random.Random(seed)
    yield [-128] * width
    yield [127] * width
    yield [0] * width
    for _ in range(count - 3):
        yield [rng.randint(-128, 127) for _ in range(width)]


A = (8, 16, 4)
B = (12, 8, 3)
BENCH = (196, 32, 10)
