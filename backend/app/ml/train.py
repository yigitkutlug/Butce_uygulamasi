import argparse

from app.ml.model import retrain_model


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--text", nargs="*", default=[])
    parser.add_argument("--label", nargs="*", default=[])
    args = parser.parse_args()

    if len(args.text) != len(args.label):
        raise SystemExit("--text and --label must have the same length")

    retrain_model(args.text, args.label)
    print("Model retrained successfully.")


if __name__ == "__main__":
    main()
