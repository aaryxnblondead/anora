from __future__ import annotations

import glob
import shutil
import subprocess
import sys
from pathlib import Path

import tensorflow as tf

SCRIPT_DIR = Path(__file__).resolve().parent
ONNX_PATH = SCRIPT_DIR / "mobilebert_anora.onnx"
TFLITE_OUTPUT = SCRIPT_DIR / "mobilebert_quant.tflite"
FLUTTER_ASSET = SCRIPT_DIR.parent.parent / "anora_frontend" / "anora" / "assets" / "models" / "mobilebert_quant.tflite"
AUTO_REPLACEMENT_JSON = SCRIPT_DIR / "mobilebert_anora_auto.json"
CHECKPOINT = (SCRIPT_DIR.parent.parent / "checkpoints" / "mobilebert-anora").as_posix()
MAX_LEN = 128


def resolve_tf_auto_model_class():
    try:
        from transformers import TFAutoModelForSequenceClassification  # type: ignore

        return TFAutoModelForSequenceClassification
    except Exception as exc:
        raise RuntimeError(
            "TensorFlow fallback requires Hugging Face transformers with TensorFlow model classes. "
            "Install a compatible package, for example: "
            "py -3 -m pip install \"transformers>=4.40,<5\" tf-keras"
        ) from exc


def resolve_onnx2tf_command() -> list[str]:
    try:
        import onnx2tf  # noqa: F401

        return [sys.executable, "-m", "onnx2tf"]
    except Exception:
        executable = shutil.which("onnx2tf")
        if executable:
            return [executable]

    raise RuntimeError(
        "onnx2tf is not installed in this Python environment. "
        "Install it with `py -3 -m pip install onnx2tf` and rerun quantize.py."
    )


def find_generated_tflite() -> Path:
    generated_tflites = sorted(
        Path(path) for path in glob.glob(str(SCRIPT_DIR / "*_int8.tflite"))
    )
    if not generated_tflites:
        generated_tflites = sorted(Path(path) for path in glob.glob(str(SCRIPT_DIR / "*.tflite")))

    if not generated_tflites:
        raise FileNotFoundError(
            "onnx2tf completed without producing a TFLite file in the quantization folder."
        )

    return generated_tflites[0]


def convert_with_onnx2tf() -> Path:
    print("Converting ONNX to quantized TFLite with onnx2tf...")
    onnx2tf_command = resolve_onnx2tf_command()
    conversion_args = [
        "-i",
        ONNX_PATH.as_posix(),
        "-o",
        SCRIPT_DIR.as_posix(),
        "-odrqt",
        "-b",
        "1",
        "-agje",
        "--non_verbose",
    ]

    if AUTO_REPLACEMENT_JSON.exists():
        conversion_args += [
            "-prf",
            AUTO_REPLACEMENT_JSON.as_posix(),
        ]

    subprocess.run(
        onnx2tf_command + conversion_args,
        check=True,
    )
    return find_generated_tflite()


def convert_with_tf_fallback() -> Path:
    print("onnx2tf conversion failed; falling back to TensorFlow conversion from checkpoint...")
    saved_model_dir = SCRIPT_DIR / "mentalbert_tf_saved_model"
    fallback_tflite = SCRIPT_DIR / "mentalbert_quant_fallback.tflite"
    tf_auto_model_class = resolve_tf_auto_model_class()

    if saved_model_dir.exists():
        shutil.rmtree(saved_model_dir)

    model = tf_auto_model_class.from_pretrained(
        CHECKPOINT,
        from_pt=True,
    )

    @tf.function(
        input_signature=[
            tf.TensorSpec(shape=(1, MAX_LEN), dtype=tf.int32, name="input_ids"),
            tf.TensorSpec(shape=(1, MAX_LEN), dtype=tf.int32, name="attention_mask"),
        ]
    )
    def serving(input_ids: tf.Tensor, attention_mask: tf.Tensor) -> dict[str, tf.Tensor]:
        outputs = model(
            input_ids=input_ids,
            attention_mask=attention_mask,
            training=False,
        )
        return {"logits": outputs.logits}

    tf.saved_model.save(
        model,
        saved_model_dir.as_posix(),
        signatures={"serving_default": serving.get_concrete_function()},
    )

    converter = tf.lite.TFLiteConverter.from_saved_model(saved_model_dir.as_posix())
    converter.optimizations = [tf.lite.Optimize.DEFAULT]
    converter.target_spec.supported_ops = [
        tf.lite.OpsSet.TFLITE_BUILTINS,
        tf.lite.OpsSet.SELECT_TF_OPS,
    ]

    tflite_model = converter.convert()
    fallback_tflite.write_bytes(tflite_model)
    return fallback_tflite

source_tflite = convert_with_tf_fallback()

TFLITE_OUTPUT.write_bytes(source_tflite.read_bytes())
FLUTTER_ASSET.parent.mkdir(parents=True, exist_ok=True)
FLUTTER_ASSET.write_bytes(source_tflite.read_bytes())

size_mb = TFLITE_OUTPUT.stat().st_size / 1e6
print(f"TFLite INT8 model saved to {TFLITE_OUTPUT} ({size_mb:.1f} MB)")
print(f"Flutter asset updated at {FLUTTER_ASSET}")
print(f"Source artifact: {source_tflite}")
print(f"Target <50MB -> {'PASS' if size_mb < 50 else 'FAIL'}")