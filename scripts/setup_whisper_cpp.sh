#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
MODELS_DIR="$ROOT_DIR/models"
WHISPER_DIR="$MODELS_DIR/whisper.cpp"

mkdir -p "$MODELS_DIR"

if [[ ! -d "$WHISPER_DIR/.git" ]]; then
  git clone https://github.com/ggerganov/whisper.cpp.git "$WHISPER_DIR"
fi

cd "$WHISPER_DIR"
cmake -B build
cmake --build build --config Release -j

if [[ ! -f "$MODELS_DIR/ggml-base.bin" ]]; then
  ./models/download-ggml-model.sh base
  cp -f "$WHISPER_DIR/models/ggml-base.bin" "$MODELS_DIR/ggml-base.bin"
fi

echo "whisper.cpp setup complete"
echo "Binary: $WHISPER_DIR/build/bin/whisper-cli"
echo "Model:  $MODELS_DIR/ggml-base.bin"
