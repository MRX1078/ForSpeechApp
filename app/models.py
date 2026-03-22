from enum import Enum


class MeetingStatus(str, Enum):
    RECORDING = "recording"
    UPLOADED = "uploaded"
    PREPROCESSING = "preprocessing"
    TRANSCRIBING = "transcribing"
    READY = "ready"
    FAILED = "failed"
