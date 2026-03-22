from __future__ import annotations

import io
import wave


def _silent_wav_bytes(duration_sec: float = 0.4, sample_rate: int = 16000) -> bytes:
    num_samples = int(duration_sec * sample_rate)
    buf = io.BytesIO()
    with wave.open(buf, "wb") as wav_file:
        wav_file.setnchannels(1)
        wav_file.setsampwidth(2)
        wav_file.setframerate(sample_rate)
        wav_file.writeframes(b"\x00\x00" * num_samples)
    return buf.getvalue()


def test_meeting_agreements_and_workspace_items_api(client):
    upload = client.post(
        "/api/meetings/upload-audio",
        files={"file": ("planning.wav", _silent_wav_bytes(), "audio/wav")},
        data={"title": "Planning meeting"},
    )
    assert upload.status_code == 201
    meeting_id = upload.json()["id"]

    create_agr = client.post(
        f"/api/meetings/{meeting_id}/agreements",
        json={
            "text": "Согласовали релиз в пятницу",
            "owner": "Маша",
            "status": "open",
        },
    )
    assert create_agr.status_code == 200
    agreement_id = create_agr.json()["id"]

    update_agr = client.patch(
        f"/api/meetings/{meeting_id}/agreements/{agreement_id}",
        json={"status": "done"},
    )
    assert update_agr.status_code == 200
    assert update_agr.json()["status"] == "done"

    list_agr = client.get(f"/api/meetings/{meeting_id}/agreements")
    assert list_agr.status_code == 200
    assert len(list_agr.json()) >= 1

    all_agr = client.get("/api/planning/agreements")
    assert all_agr.status_code == 200
    assert any(row["meeting_id"] == meeting_id for row in all_agr.json())

    create_item = client.post(
        "/api/planning/work-items",
        json={
            "kind": "task",
            "title": "Подготовить план",
            "content": "Собрать пункты от команды",
            "status": "open",
        },
    )
    assert create_item.status_code == 200
    item_id = create_item.json()["id"]

    patch_item = client.patch(
        f"/api/planning/work-items/{item_id}",
        json={"status": "done"},
    )
    assert patch_item.status_code == 200
    assert patch_item.json()["status"] == "done"

    list_items = client.get("/api/planning/work-items")
    assert list_items.status_code == 200
    assert any(row["id"] == item_id for row in list_items.json())
