from __future__ import annotations

import os
import sys
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

ROOT_DIR = Path(__file__).resolve().parents[1]
if str(ROOT_DIR) not in sys.path:
    sys.path.insert(0, str(ROOT_DIR))


@pytest.fixture()
def client(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> TestClient:
    data_dir = tmp_path / "data"
    models_dir = tmp_path / "models"
    data_dir.mkdir(parents=True, exist_ok=True)
    models_dir.mkdir(parents=True, exist_ok=True)

    monkeypatch.setenv("APP_DATA_DIR", str(data_dir))
    monkeypatch.setenv("APP_MODELS_DIR", str(models_dir))
    monkeypatch.setenv("WHISPER_CPP_BIN", str(models_dir / "missing-whisper-cli"))
    monkeypatch.setenv("WHISPER_MODEL_PATH", str(models_dir / "missing-model.bin"))

    from app import deps

    deps.clear_caches()
    from app.main import create_app

    app = create_app()

    with TestClient(app) as test_client:
        yield test_client

    deps.clear_caches()
