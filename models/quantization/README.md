# MentalBERT Quantization Pipeline

This folder contains the scripts used to fine-tune MentalBERT, export it to ONNX, convert it to TensorFlow SavedModel, and quantize it to an INT8 TFLite artifact for Anora.

## Layout

- `train.py` fine-tunes the classifier.
- `export_onnx.py` exports the trained checkpoint to ONNX.
- `quantize.py` converts ONNX to SavedModel and then to `mentalbert_quant.tflite`.
- `validate.py` runs a quick TFLite sanity check before you copy the model into Flutter.

## Expected output

The final mobile artifact should be written to:

- `anora_frontend/anora/assets/models/mentalbert_quant.tflite`

## Notes

- The scripts assume you run them from this folder.
- Replace the GoEmotions-based training data with a clinically reviewed corpus before using the model in production.
- Keep the Flutter asset path as `assets/models/` so any future model refresh is picked up without a pubspec change.