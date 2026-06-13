from pathlib import Path
import pickle

import pandas as pd
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.linear_model import LogisticRegression
from sklearn.pipeline import Pipeline

BASE_DIR = Path(__file__).resolve().parent
MODEL_PATH = BASE_DIR / "model.pkl"
SEED_PATH = BASE_DIR / "data" / "seed.csv"

_cached_model: Pipeline | None = None


def _load_seed():
    data = pd.read_csv(SEED_PATH)
    return data["text"].tolist(), data["category"].tolist()


def load_seed_samples() -> tuple[list[str], list[str]]:
    return _load_seed()


def train_model(texts: list[str], labels: list[str]) -> Pipeline:
    pipeline = Pipeline(
        [
            ("tfidf", TfidfVectorizer()),
            ("clf", LogisticRegression(max_iter=1000)),
        ]
    )
    pipeline.fit(texts, labels)
    return pipeline


def save_model(model: Pipeline) -> None:
    with open(MODEL_PATH, "wb") as f:
        pickle.dump(model, f)


def load_model() -> Pipeline:
    global _cached_model
    if _cached_model is not None:
        return _cached_model

    if MODEL_PATH.exists() and MODEL_PATH.stat().st_mtime >= SEED_PATH.stat().st_mtime:
        with open(MODEL_PATH, "rb") as f:
            _cached_model = pickle.load(f)
            return _cached_model

    texts, labels = _load_seed()
    model = train_model(texts, labels)
    save_model(model)
    _cached_model = model
    return model


def predict_category(description: str) -> str:
    model = load_model()
    return model.predict([description])[0]


def retrain_model(new_texts: list[str], new_labels: list[str]) -> None:
    seed_texts, seed_labels = _load_seed()
    texts = seed_texts + new_texts
    labels = seed_labels + new_labels
    model = train_model(texts, labels)
    save_model(model)
    global _cached_model
    _cached_model = model
