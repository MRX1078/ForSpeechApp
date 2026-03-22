# Local Meeting Recorder (macOS, local-first MVP)

## 1. What this app does
This app records meetings from your Mac microphone in the browser, uploads audio to a local FastAPI backend (`127.0.0.1`), runs local preprocessing/transcription, stores transcript and segments in local SQLite, and provides full-text search with SQLite FTS5.
In meeting details, you can listen to archived audio with seek controls and manually tag who speaks in each segment.

Pipeline:
1. Record audio via `MediaRecorder` in browser.
2. Save original file in `./data/recordings/`.
3. Create compressed archive copy (`.m4a`, low bitrate) in `./data/recordings/`.
4. Normalize audio with `ffmpeg` to mono/16kHz/PCM WAV.
5. Split speech windows with Silero VAD.
6. Transcribe each segment locally with `whisper.cpp`.
7. Save transcript + segments to SQLite (`./data/app.db`).
8. Index text in `transcript_fts` (FTS5).

## 2. Local components used
- Python 3.11+
- FastAPI + Jinja2
- SQLite + FTS5
- ffmpeg + ffprobe
- Silero VAD (`silero-vad` + `torch`)
- whisper.cpp CLI + GGML model

No OpenAI API, no cloud speech APIs, no remote server required for runtime.

## 3. Install Python dependencies
```bash
cd "/Users/maksimshatokhin/Documents/New project"
python3.11 -m venv .venv
source .venv/bin/activate
pip install --upgrade pip
pip install -r requirements.txt
```

## 4. Install ffmpeg on macOS
```bash
brew install ffmpeg
ffmpeg -version
ffprobe -version
```

## 5. Build and connect whisper.cpp
Option A (recommended): run helper script
```bash
./scripts/setup_whisper_cpp.sh
```

Higher accuracy profile (recommended for Russian):
```bash
WHISPER_MODEL_NAME=medium ./scripts/setup_whisper_cpp.sh
# or strongest quality (slower):
# WHISPER_MODEL_NAME=large-v3 ./scripts/setup_whisper_cpp.sh
```

Option B (manual):
```bash
mkdir -p models
cd models
git clone https://github.com/ggerganov/whisper.cpp.git
cd whisper.cpp
cmake -B build
cmake --build build --config Release -j
```

## 6. Download model
If you used `./scripts/setup_whisper_cpp.sh`, model is already copied to `./models/ggml-<model>.bin`.

Manual download:
```bash
cd models/whisper.cpp
./models/download-ggml-model.sh base
cp models/ggml-base.bin ../ggml-base.bin
```

For higher quality:
```bash
cd models/whisper.cpp
./models/download-ggml-model.sh medium
cp models/ggml-medium.bin ../ggml-medium.bin
```

## 7. Run the app
```bash
source .venv/bin/activate
export WHISPER_CPP_BIN="/Users/maksimshatokhin/Documents/New project/models/whisper.cpp/build/bin/whisper-cli"
export WHISPER_LANGUAGE="ru"
export WHISPER_MODEL_PRIORITY="large-v3,large-v2,medium,small,base"
export WHISPER_BEAM_SIZE="8"
export WHISPER_BEST_OF="8"
# optional: pin explicit model file
# export WHISPER_MODEL_PATH="/Users/maksimshatokhin/Documents/New project/models/ggml-medium.bin"
# optional: compressed archive bitrate in kbps (default 32)
# export COMPRESSED_AUDIO_BITRATE_KBPS="24"
uvicorn app.main:app --host 127.0.0.1 --port 8000 --reload
```

## 8. Open UI
Open in browser:
- [http://127.0.0.1:8000](http://127.0.0.1:8000)

Pages:
- `/` recording panel + latest meetings
- `/meetings` all meetings
- `/meetings/{id}` meeting detail, segments, export, rename/delete/reprocess
- `/search` global search by transcript text

## 9. Record first meeting
1. Open `/`.
2. Enter optional title.
3. Click **Начать запись**.
4. Speak into Mac microphone.
5. Use **Пауза / Продолжить** if needed.
6. Click **Завершить и обработать**.
7. App uploads audio and starts local processing.
8. Open meeting page and wait for status `ready`.

Hotkeys on `/`:
- `Space` — start/pause/resume recording
- `Enter` — finish and process recording

## 10. Search text
- Global search: `/search`
- Meeting-local search: `/meetings/{id}?q=your+phrase`

Search uses only SQLite FTS5 (`transcript_fts`).

## 11. Known MVP limitations
- No automatic speaker diarization (speaker tags are manual).
- Recognition quality depends on model size and microphone quality.
- Long meetings process with noticeable delay.
- VAD segmentation can miss or split speech incorrectly.
- Local single-user MVP, not a production dictation suite.

## 12. How to swap backend later (WhisperKit/MLX)
Current STT integration is behind abstraction:
- `SpeechTranscriber` interface: `app/services/transcriber.py`
- Current implementation: `WhisperCppTranscriber`

To switch backend:
1. Add new class (`WhisperKitTranscriber` or `MLXWhisperTranscriber`) implementing `transcribe_segment(audio_path) -> str`.
2. Update dependency wiring in `app/deps.py` (`get_transcriber`).
3. Keep `TranscriptPipeline` unchanged.

## API routes
Implemented API:
- `GET /api/health`
- `POST /api/meetings/upload-audio`
- `GET /api/meetings`
- `GET /api/meetings/{meeting_id}`
- `GET /api/meetings/{meeting_id}/transcript`
- `PATCH /api/meetings/{meeting_id}`
- `PATCH /api/meetings/{meeting_id}/segments/{segment_id}`
- `DELETE /api/meetings/{meeting_id}`
- `POST /api/meetings/{meeting_id}/reprocess`
- `GET /api/search?q=...`
- `GET /api/meetings/{meeting_id}/search?q=...`
- `GET /api/meetings/{meeting_id}/export.txt`
- `GET /api/meetings/{meeting_id}/export.md`
- `GET /api/meetings/{meeting_id}/audio-compressed`

## Project layout
```text
app/
  main.py
  config.py
  database.py
  models.py
  schemas.py
  deps.py
  routes/
    health.py
    meetings.py
    recordings.py
    search.py
    exports.py
  services/
    recorder.py
    audio_preprocess.py
    vad.py
    transcriber.py
    transcript_pipeline.py
    storage.py
    search.py
    exports.py
  templates/
    base.html
    index.html
    meetings.html
    meeting_detail.html
    search.html
  static/
    app.css
    app.js
data/
models/
scripts/
tests/
requirements.txt
README.md
```
