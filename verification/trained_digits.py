"""Train/export a small optional deployment fixture from sklearn's UCI digits data."""
def train():
    import numpy as np
    from sklearn.datasets import load_digits
    from sklearn.linear_model import LogisticRegression
    from sklearn.model_selection import train_test_split

    digits = load_digits()
    # Integer centring, with the exact same host input transform at train and test.
    data = digits.data.astype(np.int32) - 8
    x_train, x_test, y_train, y_test = train_test_split(
        data, digits.target, test_size=0.25, random_state=42, stratify=digits.target)
    classifier = LogisticRegression(max_iter=2000, random_state=42).fit(x_train, y_train)
    scale = 127 / np.max(np.abs(classifier.coef_))
    layer = {
        "weights": np.clip(np.rint(classifier.coef_ * scale), -127, 127).astype(int).tolist(),
        "bias": np.rint(classifier.intercept_ * scale).astype(int).tolist(),
    }
    from host.reference import infer

    q_predictions = [max(range(10), key=infer([layer], x).__getitem__) for x in x_test.tolist()]
    float_correct = int(np.count_nonzero(classifier.predict(x_test) == y_test))
    quant_correct = int(np.count_nonzero(np.asarray(q_predictions) == y_test))
    return [layer], x_test.tolist(), {
        "dataset": "UCI Optical Recognition of Handwritten Digits via sklearn load_digits",
        "sklearn_version": __import__("sklearn").__version__,
        "train_size": len(x_train), "test_size": len(x_test), "split_seed": 42,
        "float_correct": float_correct, "quant_correct": quant_correct,
    }
