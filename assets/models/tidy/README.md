TIDY OpenCLIP ONNX assets
=========================

Source: https://github.com/slavabarkov/tidy
Upstream commit inspected: eb4aed45656909b72992c51f3f11ac663759b2e7

These files were copied from TIDY's Android raw resources:

- visual_quant.onnx: quantized CLIP/OpenCLIP image encoder.
- textual_quant.onnx: quantized CLIP/OpenCLIP text encoder.
- vocab.json: tokenizer vocabulary used by the text encoder.
- merges.txt: tokenizer BPE merges used by the text encoder.
- TIDY_LICENSE.txt: copy of the upstream TIDY GPL-3.0 license.

TIDY loads these models with ONNX Runtime Android from R.raw.visual_quant and
R.raw.textual_quant. In Flutter, they are registered as assets via pubspec.yaml
under assets/models/tidy/.

License note: TIDY is GPL-3.0 licensed. Check model and upstream licensing before
redistributing an app bundle that includes these files.
