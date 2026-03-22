# ForSpeechApp

Локальное приложение для записи рабочих встреч, транскрибации речи и ведения договоренностей/рабочих заметок.  
Работает на `macOS` (целевая машина: `MacBook Air M3`) и не требует облачных speech API.

## Что делает приложение

- записывает встречу с микрофона в браузере
- сохраняет оригинал и сжатую копию аудио локально
- обрабатывает запись пайплайном `ffmpeg + Silero VAD + whisper.cpp`
- формирует транскрипт с таймкодами сегментов
- хранит всё в `SQLite` и дает полнотекстовый поиск через `FTS5`
- позволяет вести договоренности по встречам
- содержит отдельную вкладку планирования: ключевые договоренности, дела, заметки

## Ключевые возможности

### 1) Запись
- кнопки: `Начать запись`, `Пауза`, `Продолжить`, `Завершить`
- хоткеи:
  - `Space` — старт/пауза/продолжить
  - `Enter` — завершить и отправить в обработку
- визуальная wave-полоса и индикаторы статуса

### 2) Встреча
- полная карточка встречи (`/meetings/{id}`)
- статус обработки: `recording`, `preprocessing`, `transcribing`, `ready`, `failed`
- транскрипт и сегменты с таймкодами
- плеер встречи (если есть сжатое аудио) + перемотка
- ручные метки говорящих по сегментам
- раздел «Договоренности с командой» (CRUD)
- экспорт в `TXT` и `Markdown`

### 3) Планирование
- страница `/planning`
- общий список ключевых договоренностей из всех встреч
- локальный список дел и заметок (`task` / `note`) с редактированием статуса

### 4) Поиск
- глобальный поиск по всем встречам: `/search`
- поиск внутри встречи: `/meetings/{id}?q=...`
- только локальный `SQLite FTS5`

## Архитектура (local-first)

- `FastAPI` поднимается локально на `127.0.0.1`
- UI: серверные шаблоны `Jinja2` + `Vanilla JS`
- БД: `SQLite` (`./data/app.db`)
- аудио и экспорты: локальная файловая система
- STT-бэкенд: `whisper.cpp` через отдельный адаптер

Пайплайн обработки аудио:
1. Принять файл от `MediaRecorder`
2. Сохранить оригинал
3. Сделать сжатую архивную копию (`.m4a`)
4. Нормализовать в mono/16kHz/PCM WAV
5. Выделить речь через `Silero VAD`
6. Прогнать сегменты в `whisper.cpp`
7. Склеить транскрипт и сохранить сегменты в БД
8. Обновить индекс `FTS5`

## Структура данных

Основные таблицы:
- `meetings`
- `transcript_segments`
- `meeting_agreements`
- `workspace_items`
- `transcript_fts` (виртуальная таблица `FTS5`)

Локальные папки:
- `./data/app.db`
- `./data/recordings/`
- `./data/processed/`
- `./data/exports/`
- `./models/`

## Быстрый запуск на macOS

### 1) Подготовка окружения

```bash
cd "/Users/maksimshatokhin/Documents/New project"
python3.11 -m venv .venv
source .venv/bin/activate
pip install --upgrade pip
pip install -r requirements.txt
```

Если `python3.11` не установлен:
```bash
brew install python@3.11
```

### 2) Установить системные зависимости

```bash
brew install ffmpeg sox cmake git
ffmpeg -version
ffprobe -version
```

### 3) Собрать `whisper.cpp` и скачать модель

Рекомендуемый способ:
```bash
./scripts/setup_whisper_cpp.sh
```

Для лучшего качества русского:
```bash
WHISPER_MODEL_NAME=medium ./scripts/setup_whisper_cpp.sh
# или максимум качества (медленнее):
# WHISPER_MODEL_NAME=large-v3 ./scripts/setup_whisper_cpp.sh
```

### 4) Запустить приложение

```bash
source .venv/bin/activate
export WHISPER_CPP_BIN="/Users/maksimshatokhin/Documents/New project/models/whisper.cpp/build/bin/whisper-cli"
export WHISPER_LANGUAGE="ru"
export WHISPER_MODEL_PRIORITY="large-v3,large-v2,medium,small,base"
export WHISPER_BEAM_SIZE="8"
export WHISPER_BEST_OF="8"
uvicorn app.main:app --host 127.0.0.1 --port 8000 --reload
```

Открыть в браузере:
- [http://127.0.0.1:8000](http://127.0.0.1:8000)

## Основные страницы

- `/` — запись + последние встречи
- `/meetings` — архив встреч
- `/meetings/{id}` — карточка встречи, плеер, сегменты, договоренности, экспорт
- `/planning` — ключевые договоренности, дела и заметки
- `/search` — глобальный полнотекстовый поиск

## Пользовательский сценарий

1. Открыть главную страницу.
2. Нажать `Начать запись`.
3. Во время встречи использовать `Пауза/Продолжить` при необходимости.
4. Нажать `Завершить`.
5. Дождаться статуса `ready`.
6. Открыть карточку встречи, проверить транскрипт и сегменты.
7. Добавить договоренности команды.
8. Перейти в `/planning` и вести общие задачи/заметки.
9. Найти нужные фразы через `/search`.

## Конфигурация через переменные окружения

| Переменная | Назначение | Пример |
|---|---|---|
| `WHISPER_CPP_BIN` | путь до бинарника `whisper-cli` | `/.../models/whisper.cpp/build/bin/whisper-cli` |
| `WHISPER_MODEL_PATH` | фиксированный путь до модели (опционально) | `/.../models/ggml-medium.bin` |
| `WHISPER_MODEL_PRIORITY` | приоритет подбора модели | `large-v3,large-v2,medium,small,base` |
| `WHISPER_LANGUAGE` | язык распознавания | `ru` |
| `WHISPER_BEAM_SIZE` | параметр beam search | `8` |
| `WHISPER_BEST_OF` | число гипотез декодирования | `8` |
| `COMPRESSED_AUDIO_BITRATE_KBPS` | битрейт сжатой копии | `24` или `32` |

## API (кратко)

- `GET /api/health`
- `POST /api/meetings/upload-audio`
- `GET /api/meetings`
- `GET /api/meetings/{meeting_id}`
- `PATCH /api/meetings/{meeting_id}`
- `DELETE /api/meetings/{meeting_id}`
- `POST /api/meetings/{meeting_id}/reprocess`
- `GET /api/meetings/{meeting_id}/transcript`
- `PATCH /api/meetings/{meeting_id}/segments/{segment_id}`
- `GET /api/meetings/{meeting_id}/agreements`
- `POST /api/meetings/{meeting_id}/agreements`
- `PATCH /api/meetings/{meeting_id}/agreements/{agreement_id}`
- `DELETE /api/meetings/{meeting_id}/agreements/{agreement_id}`
- `GET /api/planning/agreements`
- `GET /api/planning/work-items`
- `POST /api/planning/work-items`
- `PATCH /api/planning/work-items/{item_id}`
- `DELETE /api/planning/work-items/{item_id}`
- `GET /api/search?q=...`
- `GET /api/meetings/{meeting_id}/search?q=...`
- `GET /api/meetings/{meeting_id}/export.txt`
- `GET /api/meetings/{meeting_id}/export.md`
- `GET /api/meetings/{meeting_id}/audio-compressed`

## Типовые проблемы и решения

### 1) Ошибка SSL при скачивании модели (`curl: (60) SSL certificate problem`)

Вариант A:
```bash
brew install ca-certificates
```

Вариант B (в корпоративной сети с собственным root CA):
- добавить корпоративный сертификат в системное хранилище Keychain
- либо передать `curl` путь к CA-bundle через `CURL_CA_BUNDLE`

### 2) Ошибка `The list of available backends is empty`

Обычно не хватает аудио-бэкендов для чтения/обработки:
```bash
brew install ffmpeg sox
source .venv/bin/activate
pip install soundfile
```

### 3) Не работает запись микрофона

- проверить разрешение на микрофон для браузера в `System Settings`
- использовать `http://127.0.0.1:8000` (не другой хост)

### 4) `whisper-cli` не найден

- проверить путь в `WHISPER_CPP_BIN`
- убедиться, что бинарник реально существует и исполняемый

## Ограничения MVP

- нет автоматической diarization (кто говорит определяется вручную)
- точность зависит от качества микрофона и размера модели
- длинные встречи обрабатываются не мгновенно
- VAD может ошибаться в границах сегментов
- это локальный single-user MVP, а не production-grade suite

## Как заменить STT-бэкенд в будущем

Текущий слой абстракции:
- интерфейс: `app/services/transcriber.py` (`SpeechTranscriber`)
- реализация: `WhisperCppTranscriber`

Чтобы перейти на `WhisperKit` или `MLX`:
1. добавить новую реализацию `SpeechTranscriber`
2. подключить её в `app/deps.py` (`get_transcriber`)
3. не менять остальной пайплайн (`TranscriptPipeline`)

## Структура проекта

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
    planning.py
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
    planning.html
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
