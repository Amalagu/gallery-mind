# GalleryMind Legacy - TIDY ViT-B/32 Baseline

This branch preserves the earlier GalleryMind implementation that bundled the
quantized CLIP/OpenCLIP ONNX model files copied from
[TIDY - Text-to-Image Discovery](https://github.com/slavabarkov/tidy).

It is kept as a fallback/reference branch before moving the newer GalleryMind
implementation to `main`.

## What This Branch Uses

- **Model source:** [slavabarkov/tidy](https://github.com/slavabarkov/tidy)
- **Model family:** CLIP/OpenCLIP ViT-B/32-style TIDY ONNX assets
- **Pretraining source described by TIDY:** OpenCLIP pretrained on
  [LAION-2B](https://huggingface.co/datasets/laion/laion2B-en), a subset of
  [LAION-5B](https://laion.ai/blog/laion-5b/)
- **Runtime:** Android ONNX Runtime
- **App stack:** Flutter UI with native Kotlin Android inference/indexing

The bundled model files live in:

```text
assets/models/tidy/
```

Included files:

- `visual_quant.onnx`
- `textual_quant.onnx`
- `vocab.json`
- `merges.txt`
- `TIDY_LICENSE.txt`

## Why This Branch Exists

The `main` branch is intended to carry the newer GalleryMind implementation that
uses a separately exported and Android-cleaned OpenCLIP ViT-B/16
`laion2b_s34b_b88k` model. This branch keeps the older TIDY-based baseline
available in case the newer model path needs comparison, debugging, or rollback.

## Credits

This branch depends on model assets copied from:

- [TIDY - Text-to-Image Discovery](https://github.com/slavabarkov/tidy)
- [OpenCLIP](https://github.com/mlfoundations/open_clip)
- [OpenAI CLIP](https://github.com/openai/CLIP)
- [LAION](https://laion.ai/)
- [ONNX Runtime](https://onnxruntime.ai/)

## TIDY Citation

```bibtex
@Misc{tidy,
  title =        {TIDY (Text-to-Image Discovery): Offline Semantic Text-to-Image and Image-to-Image Search on Android Powered by the Vision-Language Pretrained CLIP Model.},
  author =       {Viacheslav Barkov},
  howpublished = {\url{https://github.com/slavabarkov/tidy}},
  year =         {2023}
}
```

