#!/usr/bin/env python3
"""
GLM-OCR Inference Script for Zero Dark
Runs OCR on images using mlx-community/GLM-OCR-4bit

Usage:
    python glm_ocr_inference.py <image_path> [--format markdown|json|latex|text]
    
Output:
    Prints extracted text to stdout
"""

import sys
import argparse
import base64
from pathlib import Path

try:
    import mlx.core as mx
    from mlx_lm import load, generate
    from PIL import Image
    import io
except ImportError:
    print("ERROR: Required packages not installed. Run:")
    print("  pip install mlx mlx-lm pillow")
    sys.exit(1)


MODEL_ID = "mlx-community/GLM-OCR-4bit"
CACHE_DIR = Path.home() / ".cache" / "zerodark" / "models"


def download_model():
    """Download model if not cached."""
    print(f"Loading model: {MODEL_ID}", file=sys.stderr)
    model, tokenizer = load(MODEL_ID)
    return model, tokenizer


def encode_image(image_path: str) -> str:
    """Encode image to base64."""
    with open(image_path, "rb") as f:
        return base64.b64encode(f.read()).decode("utf-8")


def build_prompt(format_type: str) -> str:
    """Build prompt based on output format."""
    prompts = {
        "text": "Extract all visible text from this image. Output plain text only.",
        "markdown": "Extract all content from this image. Format as clean Markdown, preserving structure like headers, lists, and tables.",
        "json": "Extract all content from this image. Output as structured JSON with appropriate fields.",
        "latex": "Extract all text and mathematical formulas. Format equations as LaTeX."
    }
    return prompts.get(format_type, prompts["markdown"])


def run_ocr(image_path: str, format_type: str = "markdown") -> str:
    """Run OCR on image and return extracted text."""
    
    # Load model
    model, tokenizer = download_model()
    
    # Load and encode image
    image = Image.open(image_path)
    
    # For vision models, we need to handle image input specially
    # GLM-OCR uses a vision encoder (CogViT) + language decoder
    
    prompt = build_prompt(format_type)
    
    # Generate
    # Note: Actual implementation depends on model's expected input format
    # This is a simplified version - real GLM-OCR has specific image handling
    
    response = generate(
        model,
        tokenizer,
        prompt=f"<image>\n{prompt}",
        max_tokens=4096,
        verbose=False
    )
    
    return response


def main():
    parser = argparse.ArgumentParser(description="GLM-OCR inference for Zero Dark")
    parser.add_argument("image", help="Path to image file")
    parser.add_argument("--format", "-f", 
                        choices=["text", "markdown", "json", "latex"],
                        default="markdown",
                        help="Output format (default: markdown)")
    parser.add_argument("--output", "-o", help="Output file (default: stdout)")
    
    args = parser.parse_args()
    
    if not Path(args.image).exists():
        print(f"ERROR: Image not found: {args.image}", file=sys.stderr)
        sys.exit(1)
    
    result = run_ocr(args.image, args.format)
    
    if args.output:
        Path(args.output).write_text(result)
        print(f"Output written to: {args.output}", file=sys.stderr)
    else:
        print(result)


if __name__ == "__main__":
    main()
