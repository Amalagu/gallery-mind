OpenCLIP ViT-B/16 ONNX assets
================================

Source: https://huggingface.co/laion/CLIP-ViT-B-16-laion2B-s34B-b88K
Model: ViT-B-16
Pretrained checkpoint: laion2b_s34b_b88k

These files were exported from open_clip_model.safetensors and optimized for
GalleryMind Android ONNX Runtime usage:

- visual_quant.onnx: ViT-B/16 image encoder, 224x224 input, 512-dim output.
- textual_quant.onnx: ViT-B/16 text encoder, input_ids + attention_mask, 512-dim output.
- vocab.json / merges.txt: CLIP BPE tokenizer files.

Conversion notebook:
C:\Users\Chike\Downloads\smartgallery\clip-vit-b16-laion2b-s34b-b88k\export_quantize_openclip_vit_b16.ipynb

The previous TIDY ViT-B/32 assets were moved to:
C:\Users\Chike\Downloads\smartgallery\clip-vit-b16-laion2b-s34b-b88k\old_tidy_b32_models

Important: replacing B/32 with B/16 requires rebuilding local gallery embeddings.
The app database version was bumped for this swap.
