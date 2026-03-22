from __future__ import annotations

import io
import wave


def _silent_wav_bytes(duration_sec: float = 0.5, sample_rate: int = 16000) -> bytes:
    num_samples = int(duration_sec * sample_rate)
    buf = io.BytesIO()
    with wave.open(buf, "wb") as wav_file:
        wav_file.setnchannels(1)
        wav_file.setsampwidth(2)
        wav_file.setframerate(sample_rate)
        wav_file.writeframes(b"\x00\x00" * num_samples)
    return buf.getvalue()


def test_upload_audio_creates_meeting_and_fails_without_model(client):
    audio_bytes = _silent_wav_bytes()
    files = {"file": ("meeting.wav", audio_bytes, "audio/wav")}
    data = {"title": "Test Meeting"}

    response = client.post("/api/meetings/upload-audio", files=files, data=data)
    assert response.status_code == 201

    meeting = response.json()
    meeting_id = meeting["id"]

    detail = client.get(f"/api/meetings/{meeting_id}")
    assert detail.status_code == 200
    payload = detail.json()
    assert payload["title"] == "Test Meeting"
    assert payload["status"] in {"failed", "preprocessing", "transcribing", "uploaded"}


def test_search_returns_empty_for_unknown_query(client):
    response = client.get("/api/search", params={"q": "thisquerydoesnotexist"})
    assert response.status_code == 200
    assert response.json() == []
