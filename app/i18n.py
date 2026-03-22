from __future__ import annotations


STATUS_LABELS_RU: dict[str, str] = {
    "idle": "ожидание",
    "recording": "запись",
    "uploaded": "загружено",
    "preprocessing": "предобработка",
    "transcribing": "транскрибация",
    "ready": "готово",
    "failed": "ошибка",
}

ITEM_STATUS_LABELS_RU: dict[str, str] = {
    "open": "в работе",
    "done": "выполнено",
}


def status_label_ru(status: str | None) -> str:
    if not status:
        return ""
    return STATUS_LABELS_RU.get(status, status)


def item_status_label_ru(status: str | None) -> str:
    if not status:
        return ""
    return ITEM_STATUS_LABELS_RU.get(status, status)
