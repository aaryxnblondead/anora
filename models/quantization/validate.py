from __future__ import annotations

from pathlib import Path

import numpy as np
import tensorflow as tf
from transformers import AutoTokenizer


SCRIPT_DIR = Path(__file__).resolve().parent
TFLITE_PATH = SCRIPT_DIR / "mobilebert_quant.tflite"
CHECKPOINT = (SCRIPT_DIR.parent.parent / "checkpoints" / "mentalbert-anora").as_posix()
MAX_LEN = 128

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


tokenizer = AutoTokenizer.from_pretrained(CHECKPOINT)
interpreter = tf.lite.Interpreter(model_path=TFLITE_PATH.as_posix())
interpreter.allocate_tensors()

input_details = interpreter.get_input_details()
output_details = interpreter.get_output_details()

test_cases = [
    (
        "I feel hopeless and I can't see a reason to go on",
        ["risk_depression", "risk_selfharm"],
    ),
    ("What a beautiful day, I feel so grateful", ["joy"]),
    ("I've been anxious all week, can't sleep", ["risk_anxiety", "fear"]),
]

print(f"Model inputs: {[details['name'] for details in input_details]}")
print(f"Model outputs: {[details['name'] for details in output_details]}\n")

for text, expected in test_cases:
    encoded = tokenizer(
        text,
        max_length=MAX_LEN,
        padding="max_length",
        truncation=True,
        return_tensors="np",
    )

    # Dynamically find the correct index for each input by name
    input_ids_idx = next(i["index"] for i in input_details if "input_ids" in i["name"])
    mask_idx = next(i["index"] for i in input_details if "attention_mask" in i["name"])

    interpreter.set_tensor(input_ids_idx, encoded["input_ids"].astype(np.int32))
    interpreter.set_tensor(mask_idx, encoded["attention_mask"].astype(np.int32))
    interpreter.invoke()

    logits = interpreter.get_tensor(output_details[0]["index"])[0]
    probabilities = 1 / (1 + np.exp(-logits))
    top_predictions = sorted(zip(LABELS, probabilities), key=lambda item: -item[1])[:3]

    print(f'Text:     "{text[:60]}..."')
    print(f"Expected: {expected}")
    print(f"Top-3:    {[(label, f'{prob:.2f}') for label, prob in top_predictions]}")
    print()