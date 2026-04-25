from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

import numpy as np
import torch
from datasets import load_dataset
from sklearn.metrics import f1_score
from torch.utils.data import DataLoader
from transformers import AutoConfig, AutoModelForSequenceClassification, AutoTokenizer


MODEL_ID = "mental/mental-bert-base-uncased"
SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parent.parent
OUTPUT_DIR = REPO_ROOT / "checkpoints" / "mentalbert-anora"
MAX_LEN = 128
BATCH_SIZE = 16
EPOCHS = 4
LEARNING_RATE = 2e-5

LABELS = [
    "joy",
    "sadness",
    "anger",
    "fear",
    "disgust",
    "surprise",
    "neutral",
    "risk_selfharm",
    "risk_anxiety",
    "risk_depression",
    "risk_mania",
]
NUM_LABELS = len(LABELS)
LABEL2ID = {label: index for index, label in enumerate(LABELS)}
ID2LABEL = {index: label for label, index in LABEL2ID.items()}


def resolve_device() -> torch.device:
    if torch.cuda.is_available():
        return torch.device("cuda")
    if hasattr(torch.backends, "mps") and torch.backends.mps.is_available():
        return torch.device("mps")
    return torch.device("cpu")


@dataclass(frozen=True)
class Metrics:
    loss: float
    f1_macro: float


tokenizer = AutoTokenizer.from_pretrained(MODEL_ID)
config = AutoConfig.from_pretrained(
    MODEL_ID,
    num_labels=NUM_LABELS,
    problem_type="multi_label_classification",
    label2id=LABEL2ID,
    id2label=ID2LABEL,
)
model = AutoModelForSequenceClassification.from_pretrained(MODEL_ID, config=config)

raw_dataset = load_dataset("go_emotions", "simplified")


def _to_label_ids(raw_labels: object) -> list[int]:
    if isinstance(raw_labels, (int, np.integer)):
        return [int(raw_labels)]
    if isinstance(raw_labels, (list, tuple)):
        return [int(label_id) for label_id in raw_labels]
    return []


def preprocess(batch: dict[str, list[object]]) -> dict[str, object]:
    encoding = tokenizer(
        batch["text"],
        truncation=True,
        padding="max_length",
        max_length=MAX_LEN,
    )

    multi_hot_labels = []
    for raw_labels in batch["labels"]:
        vector = [0.0] * NUM_LABELS
        for label_id in _to_label_ids(raw_labels):
            if 0 <= label_id < 7:
                vector[label_id] = 1.0
        multi_hot_labels.append(vector)

    encoding["labels"] = multi_hot_labels
    return encoding


tokenized = raw_dataset.map(preprocess, batched=True, remove_columns=raw_dataset["train"].column_names)
tokenized.set_format("torch")


def make_loader(split_name: str, shuffle: bool) -> DataLoader:
    return DataLoader(
        tokenized[split_name],
        batch_size=BATCH_SIZE,
        shuffle=shuffle,
    )


def compute_batch_metrics(logits: torch.Tensor, labels: torch.Tensor) -> Metrics:
    loss = torch.nn.functional.binary_cross_entropy_with_logits(logits, labels)
    predictions = (torch.sigmoid(logits) > 0.5).int().cpu().numpy()
    targets = labels.int().cpu().numpy()
    f1 = f1_score(targets, predictions, average="macro", zero_division=0)
    return Metrics(loss=float(loss.item()), f1_macro=float(f1))


def run_epoch(loader: DataLoader, training: bool, optimizer: torch.optim.Optimizer | None) -> Metrics:
    total_loss = 0.0
    total_examples = 0
    all_predictions: list[np.ndarray] = []
    all_targets: list[np.ndarray] = []

    model.train(training)

    for batch in loader:
        inputs = {
            "input_ids": batch["input_ids"].to(device),
            "attention_mask": batch["attention_mask"].to(device),
            "labels": batch["labels"].float().to(device),
        }

        with torch.set_grad_enabled(training):
            outputs = model(**inputs)
            loss = outputs.loss
            logits = outputs.logits

        if training:
            if optimizer is None:
                raise RuntimeError("optimizer is required during training")
            optimizer.zero_grad(set_to_none=True)
            loss.backward()
            torch.nn.utils.clip_grad_norm_(model.parameters(), max_norm=1.0)
            optimizer.step()

        batch_size = inputs["input_ids"].size(0)
        total_loss += float(loss.item()) * batch_size
        total_examples += batch_size
        all_predictions.append((torch.sigmoid(logits) > 0.5).int().cpu().numpy())
        all_targets.append(inputs["labels"].int().cpu().numpy())

    concatenated_predictions = np.concatenate(all_predictions, axis=0)
    concatenated_targets = np.concatenate(all_targets, axis=0)
    f1 = f1_score(concatenated_targets, concatenated_predictions, average="macro", zero_division=0)
    return Metrics(
        loss=total_loss / max(total_examples, 1),
        f1_macro=float(f1),
    )


device = resolve_device()
print(f"Using device: {device}")
if device.type == "cuda":
    print(f"CUDA device: {torch.cuda.get_device_name(0)}")
    torch.backends.cuda.matmul.allow_tf32 = True
    torch.set_float32_matmul_precision("high")
model.to(device)

train_loader = make_loader("train", shuffle=True)
validation_loader = make_loader("validation", shuffle=False)

optimizer = torch.optim.AdamW(model.parameters(), lr=LEARNING_RATE)
best_f1 = float("-inf")

print(f"Training on {device} for {EPOCHS} epochs")
for epoch in range(1, EPOCHS + 1):
    train_metrics = run_epoch(train_loader, training=True, optimizer=optimizer)
    validation_metrics = run_epoch(validation_loader, training=False, optimizer=None)

    print(
        f"Epoch {epoch}/{EPOCHS} | "
        f"train_loss={train_metrics.loss:.4f} | train_f1={train_metrics.f1_macro:.4f} | "
        f"val_loss={validation_metrics.loss:.4f} | val_f1={validation_metrics.f1_macro:.4f}"
    )

    if validation_metrics.f1_macro > best_f1:
        best_f1 = validation_metrics.f1_macro
        OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
        model.save_pretrained(OUTPUT_DIR.as_posix())
        tokenizer.save_pretrained(OUTPUT_DIR.as_posix())
        print(f"Saved best checkpoint to {OUTPUT_DIR}")

print(f"Training complete. Best validation F1: {best_f1:.4f}")