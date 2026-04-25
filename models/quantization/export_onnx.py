from __future__ import annotations

from pathlib import Path

import onnx
import torch
from transformers import AutoModelForSequenceClassification, AutoTokenizer


SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parent.parent
CHECKPOINT = (REPO_ROOT / "checkpoints" / "mobilebert-anora").as_posix()
ONNX_PATH = SCRIPT_DIR / "mobilebert_anora.onnx"
MAX_LEN = 128


class OnnxExportWrapper(torch.nn.Module):
    def __init__(self, model: torch.nn.Module) -> None:
        super().__init__()
        self.model = model

    def forward(self, input_ids: torch.Tensor, attention_mask: torch.Tensor) -> torch.Tensor:
        return self.model(input_ids=input_ids, attention_mask=attention_mask).logits


tokenizer = AutoTokenizer.from_pretrained(CHECKPOINT)
model = AutoModelForSequenceClassification.from_pretrained(CHECKPOINT)
model.eval()

dummy_inputs = tokenizer(
    "I feel quite anxious and overwhelmed today",
    return_tensors="pt",
    max_length=MAX_LEN,
    padding="max_length",
    truncation=True,
)

wrapper = OnnxExportWrapper(model)

with torch.no_grad():
    torch.onnx.export(
        wrapper,
        (dummy_inputs["input_ids"], dummy_inputs["attention_mask"]),
        ONNX_PATH.as_posix(),
        input_names=["input_ids", "attention_mask"],
        output_names=["logits"],
        opset_version=14,
        do_constant_folding=True,
    )

onnx_model = onnx.load(ONNX_PATH.as_posix())
onnx.checker.check_model(onnx_model)
size_mb = ONNX_PATH.stat().st_size / 1e6
print(f"ONNX export OK -> {ONNX_PATH} ({size_mb:.1f} MB)")