from __future__ import annotations

import os
os.environ["CUDA_VISIBLE_DEVICES"] = "0"
os.environ["TF_FORCE_GPU_ALLOW_GROWTH"] = "true"
os.environ["TF_CPP_MIN_LOG_LEVEL"] = "3"
os.environ["CUDA_VISIBLE_DEVICES_FOR_TF"] = "-1"  # TF uses CPU
os.environ["TF_VISIBLE_DEVICES"] = "-1"   

import torch
torch.cuda.init()
try:
    import tensorflow as tf
    tf.config.set_visible_devices([], 'GPU')
    print("TensorFlow GPU access disabled — PyTorch owns the GPU exclusively")
except Exception:
    pass

from dataclasses import dataclass
from pathlib import Path

import numpy as np
import torch.nn.functional as F
from datasets import load_dataset
from sklearn.metrics import f1_score
from torch.utils.data import DataLoader
from transformers import AutoConfig, AutoModelForSequenceClassification, AutoTokenizer

# ── Paths ─────────────────────────────────────────────────────────────────────
SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parent.parent
TEACHER_CHECKPOINT = (REPO_ROOT / "checkpoints" / "mentalbert-anora").as_posix()
STUDENT_OUTPUT_DIR = REPO_ROOT / "checkpoints" / "mobilebert-anora"
STUDENT_BASE = "google/mobilebert-uncased"

print(f"REPO_ROOT resolved to: {REPO_ROOT}")
print(f"Teacher checkpoint: {TEACHER_CHECKPOINT}")
print(f"Student output: {STUDENT_OUTPUT_DIR}")

# ── Hyperparameters ───────────────────────────────────────────────────────────
MAX_LEN = 128
BATCH_SIZE = 32      # Pushes much more data to the GPU VRAM at once
GRAD_ACCUM_STEPS = 1 # Reduced to keep the effective batch size identical (32x1 = 32)
EPOCHS = 6
LEARNING_RATE = 1e-5
TEMPERATURE = 2.0
ALPHA = 0.7

# ── Labels ────────────────────────────────────────────────────────────────────
LABELS = [
    "joy", "sadness", "anger", "fear", "disgust", "surprise", "neutral",
    "risk_selfharm", "risk_anxiety", "risk_depression", "risk_mania",
]
NUM_LABELS = len(LABELS)
LABEL2ID = {label: idx for idx, label in enumerate(LABELS)}
ID2LABEL = {idx: label for label, idx in LABEL2ID.items()}


def resolve_device() -> torch.device:
    if torch.cuda.is_available():
        return torch.device("cuda")
    return torch.device("cpu")


@dataclass(frozen=True)
class Metrics:
    loss: float
    f1_macro: float


# ── Tokenizer ─────────────────────────────────────────────────────────────────
print("Loading tokenizer from teacher checkpoint...")
tokenizer = AutoTokenizer.from_pretrained(TEACHER_CHECKPOINT)


# ── Dataset ───────────────────────────────────────────────────────────────────
def _to_label_ids(raw_labels: object) -> list[int]:
    if isinstance(raw_labels, (int, np.integer)):
        return [int(raw_labels)]
    if isinstance(raw_labels, (list, tuple)):
        return [int(l) for l in raw_labels]
    return []


def preprocess(batch: dict) -> dict:
    encoding = tokenizer(
        batch["text"],
        truncation=True,
        padding="max_length",
        max_length=MAX_LEN,
    )
    multi_hot = []
    for raw in batch["labels"]:
        vec = [0.0] * NUM_LABELS
        for lid in _to_label_ids(raw):
            if 0 <= lid < 7:
                vec[lid] = 1.0
        multi_hot.append(vec)
    encoding["labels"] = multi_hot
    return encoding


print("Loading GoEmotions dataset...")
raw_dataset = load_dataset("go_emotions", "simplified")
tokenized = raw_dataset.map(
    preprocess, batched=True,
    remove_columns=raw_dataset["train"].column_names,
)
tokenized.set_format("torch")


def make_loader(split: str, shuffle: bool) -> DataLoader:
    return DataLoader(
        tokenized[split], 
        batch_size=BATCH_SIZE, 
        shuffle=shuffle,
        pin_memory=True # Creates a fast-lane for data transfer to the GPU
    )


# ── Models ────────────────────────────────────────────────────────────────────
device = resolve_device()
print(f"Using device: {device}")
if device.type == "cuda":
    print(f"GPU: {torch.cuda.get_device_name(0)}")

print("Loading teacher (MentalBERT)...")
teacher = AutoModelForSequenceClassification.from_pretrained(TEACHER_CHECKPOINT)
teacher = teacher.half()
teacher.to(device)
print(f"VRAM after teacher load: {torch.cuda.memory_allocated() / 1e9:.2f} GB")
teacher.eval()
for param in teacher.parameters():
    param.requires_grad = False
print(f"Teacher loaded. Parameters: {sum(p.numel() for p in teacher.parameters()):,}")

print("Loading student base (MobileBERT)...")
student_config = AutoConfig.from_pretrained(
    STUDENT_BASE,
    num_labels=NUM_LABELS,
    problem_type="multi_label_classification",
    label2id=LABEL2ID,
    id2label=ID2LABEL,
)
student = AutoModelForSequenceClassification.from_pretrained(
    STUDENT_BASE,
    config=student_config,
)
student.to(device)
print(f"VRAM after student load: {torch.cuda.memory_allocated() / 1e9:.2f} GB")
print(f"Student loaded. Parameters: {sum(p.numel() for p in student.parameters()):,}")


# ── KD Loss ───────────────────────────────────────────────────────────────────
def knowledge_distillation_loss(
    student_logits: torch.Tensor,
    teacher_logits: torch.Tensor,
    hard_labels: torch.Tensor,
    temperature: float,
    alpha: float,
) -> torch.Tensor:
    T = temperature
    soft_student = torch.sigmoid(student_logits / T)
    soft_teacher = torch.sigmoid(teacher_logits.float() / T)

    # Clamp to avoid log(0) in BCE
    soft_student = soft_student.clamp(1e-6, 1 - 1e-6)
    soft_teacher = soft_teacher.clamp(1e-6, 1 - 1e-6)

    # KD loss without T² scaling — T² causes explosion with sigmoid/BCE
    kd_loss = F.binary_cross_entropy(
        soft_student, soft_teacher.detach()
    )

    # Hard loss
    hard_loss = F.binary_cross_entropy_with_logits(
        student_logits, hard_labels
    )

    return alpha * kd_loss + (1.0 - alpha) * hard_loss


# ── Training loop ─────────────────────────────────────────────────────────────
def run_epoch(
    loader: DataLoader,
    training: bool,
    optimizer: torch.optim.Optimizer | None,
    scheduler: object | None,
) -> Metrics:
    total_loss = 0.0
    total_examples = 0
    all_preds: list[np.ndarray] = []
    all_targets: list[np.ndarray] = []

    student.train(training)

    if training and optimizer:
        optimizer.zero_grad(set_to_none=True)

    total_batches = len(loader)
    for step, batch in enumerate(loader):
        # Progress print every 100 steps during training
        if training and step % 100 == 0:
            print(
                f"    step {step}/{total_batches} | "
                f"loss so far: {total_loss / max(total_examples, 1):.4f}",
                flush=True,
            )

        input_ids = batch["input_ids"].to(device)
        attention_mask = batch["attention_mask"].to(device)
        labels = batch["labels"].float().to(device)

        with torch.no_grad():
            teacher_out = teacher(
                input_ids=input_ids,
                attention_mask=attention_mask,
            )
            teacher_logits = teacher_out.logits

        with torch.set_grad_enabled(training):
            student_out = student(
                input_ids=input_ids,
                attention_mask=attention_mask,
            )
            student_logits = student_out.logits

            loss = knowledge_distillation_loss(
                student_logits, teacher_logits, labels,
                TEMPERATURE, ALPHA,
            )

            if training:
                (loss / GRAD_ACCUM_STEPS).backward()

                if (step + 1) % GRAD_ACCUM_STEPS == 0:
                    torch.nn.utils.clip_grad_norm_(student.parameters(), 1.0)
                    optimizer.step()
                    if scheduler:
                        scheduler.step()
                    optimizer.zero_grad(set_to_none=True)

        bsz = input_ids.size(0)
        total_loss += loss.item() * bsz
        total_examples += bsz

        preds = (torch.sigmoid(student_logits) > 0.5).int().cpu().numpy()
        tgts = labels.int().cpu().numpy()
        all_preds.append(preds)
        all_targets.append(tgts)

    f1 = f1_score(
        np.concatenate(all_targets),
        np.concatenate(all_preds),
        average="macro",
        zero_division=0,
    )
    return Metrics(loss=total_loss / max(total_examples, 1), f1_macro=float(f1))


# ── Optimizer + scheduler ─────────────────────────────────────────────────────
optimizer = torch.optim.AdamW(student.parameters(), lr=LEARNING_RATE)

train_loader = make_loader("train", shuffle=True)
val_loader = make_loader("validation", shuffle=False)

total_steps = (len(train_loader) // GRAD_ACCUM_STEPS) * EPOCHS
warmup_steps = total_steps // 10

if total_steps == 0:
    raise RuntimeError(
        f"total_steps is 0. train_loader has {len(train_loader)} batches, "
        f"GRAD_ACCUM_STEPS={GRAD_ACCUM_STEPS}, EPOCHS={EPOCHS}."
    )

scheduler = torch.optim.lr_scheduler.OneCycleLR(
    optimizer,
    max_lr=LEARNING_RATE,
    total_steps=total_steps,
    pct_start=warmup_steps / total_steps,
)

# ── Run ───────────────────────────────────────────────────────────────────────
print(f"\nDistilling MentalBERT -> MobileBERT")
print(f"Epochs: {EPOCHS} | Batch: {BATCH_SIZE} | Grad accum: {GRAD_ACCUM_STEPS} | Effective batch: {BATCH_SIZE * GRAD_ACCUM_STEPS}")
print(f"Temperature: {TEMPERATURE} | Alpha: {ALPHA}")
print(f"Total steps: {total_steps} | Warmup steps: {warmup_steps}\n")

best_f1 = float("-inf")

for epoch in range(1, EPOCHS + 1):
    print(f"\n── Epoch {epoch}/{EPOCHS} ──────────────────────────────")
    train_metrics = run_epoch(train_loader, training=True, optimizer=optimizer, scheduler=scheduler)
    val_metrics = run_epoch(val_loader, training=False, optimizer=None, scheduler=None)

    print(
        f"Epoch {epoch}/{EPOCHS} | "
        f"train_loss={train_metrics.loss:.4f} | train_f1={train_metrics.f1_macro:.4f} | "
        f"val_loss={val_metrics.loss:.4f} | val_f1={val_metrics.f1_macro:.4f}"
    )

    if val_metrics.f1_macro > best_f1:
        best_f1 = val_metrics.f1_macro
        STUDENT_OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
        student.save_pretrained(STUDENT_OUTPUT_DIR.as_posix())
        tokenizer.save_pretrained(STUDENT_OUTPUT_DIR.as_posix())
        print(f"  ✓ Saved best checkpoint (val_f1={best_f1:.4f}) -> {STUDENT_OUTPUT_DIR}")

print(f"\nDistillation complete. Best validation F1: {best_f1:.4f}")
print(f"Student checkpoint saved to: {STUDENT_OUTPUT_DIR}")