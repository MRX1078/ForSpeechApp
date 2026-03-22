#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
MODELS_DIR="$ROOT_DIR/models"
WHISPER_DIR="$MODELS_DIR/whisper.cpp"
MODEL_NAME="${WHISPER_MODEL_NAME:-base}"
MODEL_FILE="ggml-${MODEL_NAME}.bin"
MODEL_PATH="$MODELS_DIR/$MODEL_FILE"
MODEL_URL="https://huggingface.co/ggerganov/whisper.cpp/resolve/main/${MODEL_FILE}?download=true"

# Set ALLOW_INSECURE_DOWNLOAD=1 only when corporate MITM/proxy blocks TLS chain validation.
ALLOW_INSECURE_DOWNLOAD="${ALLOW_INSECURE_DOWNLOAD:-0}"

mkdir -p "$MODELS_DIR"

if [[ ! -d "$WHISPER_DIR/.git" ]]; then
  git clone https://github.com/ggerganov/whisper.cpp.git "$WHISPER_DIR"
fi

cd "$WHISPER_DIR"
cmake -B build
cmake --build build --config Release -j

create_macos_ca_bundle() {
  local bundle_path
  bundle_path="$(mktemp "/tmp/codex-ca-bundle.XXXXXX.pem")"
  if security find-certificate -a -p \
      /System/Library/Keychains/SystemRootCertificates.keychain \
      /Library/Keychains/System.keychain >"$bundle_path" 2>/dev/null; then
    echo "$bundle_path"
    return 0
  fi

  rm -f "$bundle_path"
  return 1
}

download_model_with_curl_fallback() {
  local tmp_model
  local ca_bundle=""
  local curl_opts=(-L --fail --retry 3 --retry-delay 2 --connect-timeout 20)

  tmp_model="$(mktemp "/tmp/${MODEL_FILE}.XXXXXX")"

  if [[ -n "${CURL_CA_BUNDLE:-}" ]]; then
    curl_opts+=(--cacert "$CURL_CA_BUNDLE")
  elif [[ "$(uname -s)" == "Darwin" ]]; then
    if ca_bundle="$(create_macos_ca_bundle)"; then
      curl_opts+=(--cacert "$ca_bundle")
    fi
  fi

  if [[ "$ALLOW_INSECURE_DOWNLOAD" == "1" ]]; then
    curl_opts+=(-k)
    echo "WARNING: insecure TLS mode enabled for model download."
  fi

  if curl "${curl_opts[@]}" "$MODEL_URL" -o "$tmp_model"; then
    mv -f "$tmp_model" "$MODEL_PATH"
  else
    rm -f "$tmp_model"
    [[ -n "$ca_bundle" ]] && rm -f "$ca_bundle"
    return 1
  fi

  [[ -n "$ca_bundle" ]] && rm -f "$ca_bundle"
  return 0
}

if [[ ! -f "$MODEL_PATH" ]]; then
  if ./models/download-ggml-model.sh "$MODEL_NAME"; then
    cp -f "$WHISPER_DIR/models/$MODEL_FILE" "$MODEL_PATH"
  else
    echo "Default whisper.cpp downloader failed, trying direct curl fallback..."
    if ! download_model_with_curl_fallback; then
      echo "Failed to download $MODEL_FILE."
      echo "Try one of:"
      echo "  1) Set CURL_CA_BUNDLE to your company CA bundle and rerun."
      echo "  2) Run with ALLOW_INSECURE_DOWNLOAD=1 as last resort."
      echo "  3) Download manually and place file at: $MODEL_PATH"
      exit 1
    fi
  fi
fi

echo "whisper.cpp setup complete"
echo "Binary: $WHISPER_DIR/build/bin/whisper-cli"
echo "Model:  $MODEL_PATH"
echo "Tip: set WHISPER_MODEL_NAME=medium or WHISPER_MODEL_NAME=large-v3 for higher accuracy."
