"""Independent scalar inference oracle. Uses unpadded model rows, no RTL helpers."""
def infer(layers, inputs):
    values = list(inputs)
    for index, layer in enumerate(layers):
        outputs = []
        for weights, bias in zip(layer["weights"], layer["bias"]):
            if len(weights) != len(values):
                raise ValueError("Input shape mismatch")
            result = sum(a * b for a, b in zip(weights, values)) + bias
            if index + 1 < len(layers):
                divisor = 2 ** layer["shift"]
                quotient, remainder = divmod(max(result, 0) * layer["multiplier"], divisor)
                result = min(127, quotient + (2 * remainder >= divisor))
            outputs.append(result)
        values = outputs
    return values
