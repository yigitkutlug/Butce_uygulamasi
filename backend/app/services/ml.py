from datetime import datetime
import logging
from collections import Counter

from sklearn.metrics import accuracy_score, precision_recall_fscore_support
from sklearn.model_selection import train_test_split

from app.db.mongo import get_db
from app.ml.model import load_seed_samples, retrain_model, train_model

logger = logging.getLogger(__name__)


async def retrain_from_db(user_id: str) -> dict:
    db = get_db()
    # Kullanıcıya ait geri bildirimler seed verilerle birlikte alınır; böylece
    # model hem başlangıç bilgisini korur hem de kişiselleşir.
    cursor = db.training_data.find(
        {
            "$or": [
                {"user_id": user_id},
                {"user_id": {"$exists": False}},
            ]
        }
    )

    texts: list[str] = []
    labels: list[str] = []
    async for item in cursor:
        texts.append(item["text"])
        labels.append(item["category"])

    if not texts:
        return {"status": "no_data", "message": "No new training data found."}

    retrain_model(texts, labels)
    await db.ml_metadata.update_one(
        {"user_id": user_id},
        {
            "$set": {
                "last_retrain_at": datetime.utcnow(),
                "samples_used": len(texts),
            }
        },
        upsert=True,
    )
    return {"status": "ok", "samples_used": len(texts)}


async def get_ml_metrics(user_id: str) -> dict:
    db = get_db()
    seed_texts, seed_labels = load_seed_samples()
    cursor = db.training_data.find(
        {
            "$or": [
                {"user_id": user_id},
                {"user_id": {"$exists": False}},
            ]
        }
    )

    texts: list[str] = list(seed_texts)
    labels: list[str] = list(seed_labels)
    source_counts = {"seed": len(seed_texts), "manual": 0, "corrected": 0, "other": 0}
    per_category_counts: dict[str, int] = {}
    for label in seed_labels:
        per_category_counts[label] = per_category_counts.get(label, 0) + 1

    async for item in cursor:
        text = item.get("text")
        label = item.get("category")
        if isinstance(text, str) and isinstance(label, str):
            texts.append(text)
            labels.append(label)
            per_category_counts[label] = per_category_counts.get(label, 0) + 1
            source = str(item.get("source", "seed")).lower()
            if source in source_counts:
                source_counts[source] += 1
            else:
                source_counts["other"] += 1

    accuracy: float | None = None
    precision: float | None = None
    recall: float | None = None
    f1: float | None = None
    unique_labels = len(set(labels))
    if len(texts) >= 10 and unique_labels >= 2:
        try:
            label_counts = Counter(labels)
            # Her kategoriden yeterli örnek varsa stratify kullanılır; az veri
            # olduğunda metrik hesabının kırılmaması için normal bölme yapılır.
            stratify = labels if min(label_counts.values()) >= 2 else None
            x_train, x_test, y_train, y_test = train_test_split(
                texts,
                labels,
                test_size=0.2,
                random_state=42,
                stratify=stratify,
            )
            model = train_model(x_train, y_train)
            preds = model.predict(x_test)
            accuracy = float(accuracy_score(y_test, preds))
            precision, recall, f1, _ = precision_recall_fscore_support(
                y_test,
                preds,
                average="weighted",
                zero_division=0,
            )
            precision = float(precision)
            recall = float(recall)
            f1 = float(f1)
        except Exception:
            logger.exception("ML validation metric computation failed.")
            accuracy = None
            precision = None
            recall = None
            f1 = None

    corrected_count = await db.training_data.count_documents(
        {"user_id": user_id, "source": "corrected"}
    )
    metadata = await db.ml_metadata.find_one({"user_id": user_id}) or {}
    sorted_categories = sorted(
        [{"category": k, "count": v} for k, v in per_category_counts.items()],
        key=lambda x: x["count"],
        reverse=True,
    )

    return {
        "total_samples": len(texts),
        "corrected_samples": int(corrected_count),
        "unique_categories": unique_labels,
        "validation_accuracy": round(accuracy, 4) if accuracy is not None else None,
        "validation_precision": round(precision, 4) if precision is not None else None,
        "validation_recall": round(recall, 4) if recall is not None else None,
        "validation_f1": round(f1, 4) if f1 is not None else None,
        "last_retrain_at": metadata.get("last_retrain_at"),
        "last_retrain_samples": int(metadata.get("samples_used", 0)),
        "source_counts": source_counts,
        "per_category_counts": sorted_categories,
        "thesis_ready_summary": {
            # Tez ve demo ekranı için metrikler ayrıca sade bir özet halinde
            # döndürülür; frontend hesap yapmak zorunda kalmaz.
            "dataset_total": len(texts),
            "dataset_seed": source_counts["seed"],
            "dataset_user_labeled": source_counts["manual"] + source_counts["corrected"],
            "model_accuracy_percent": round((accuracy or 0.0) * 100, 2) if accuracy is not None else None,
            "model_precision_percent": round((precision or 0.0) * 100, 2) if precision is not None else None,
            "model_recall_percent": round((recall or 0.0) * 100, 2) if recall is not None else None,
            "model_f1_percent": round((f1 or 0.0) * 100, 2) if f1 is not None else None,
            "retrain_events_enabled": True,
            "auto_retrain_rule": "Every 5 labeled feedback samples",
        },
    }
