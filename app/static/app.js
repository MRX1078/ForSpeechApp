(function () {
  const STATUS_LABELS_RU = {
    idle: "ожидание",
    recording: "запись",
    uploaded: "загружено",
    preprocessing: "предобработка",
    transcribing: "транскрибация",
    ready: "готово",
    failed: "ошибка",
  };

  function statusLabel(value) {
    return STATUS_LABELS_RU[value] || value;
  }

  function formatTime(seconds) {
    const value = Math.max(0, Math.floor(Number(seconds) || 0));
    const min = Math.floor(value / 60);
    const sec = value % 60;
    return `${String(min).padStart(2, "0")}:${String(sec).padStart(2, "0")}`;
  }

  const startBtn = document.getElementById("startRecordingBtn");
  const stopBtn = document.getElementById("stopRecordingBtn");
  const statusBadge = document.getElementById("recordingStatusBadge");
  const errorNode = document.getElementById("recordingError");
  const titleInput = document.getElementById("meetingTitle");
  const recordingTimerNode = document.getElementById("recordingTimer");

  let mediaRecorder = null;
  let mediaStream = null;
  let chunks = [];
  let recordingStartedAt = null;
  let recordingTimerInterval = null;

  function setStatus(value) {
    if (!statusBadge) return;
    statusBadge.textContent = statusLabel(value);
    statusBadge.className = "badge " + value;
    statusBadge.dataset.status = value;
  }

  function setError(message) {
    if (!errorNode) return;
    errorNode.textContent = message || "";
  }

  function startRecordingTimer() {
    if (!recordingTimerNode) return;
    recordingStartedAt = Date.now();
    recordingTimerNode.textContent = "00:00";
    if (recordingTimerInterval) {
      clearInterval(recordingTimerInterval);
    }
    recordingTimerInterval = setInterval(() => {
      const elapsedSec = (Date.now() - recordingStartedAt) / 1000;
      recordingTimerNode.textContent = formatTime(elapsedSec);
    }, 200);
  }

  function stopRecordingTimer(resetToZero) {
    if (recordingTimerInterval) {
      clearInterval(recordingTimerInterval);
      recordingTimerInterval = null;
    }
    if (resetToZero && recordingTimerNode) {
      recordingTimerNode.textContent = "00:00";
    }
  }

  async function startRecording() {
    setError("");
    if (!navigator.mediaDevices || !navigator.mediaDevices.getUserMedia) {
      setError("Браузер не поддерживает запись с микрофона.");
      return;
    }

    try {
      mediaStream = await navigator.mediaDevices.getUserMedia({ audio: true });
      const options = { mimeType: "audio/webm" };
      mediaRecorder = new MediaRecorder(mediaStream, options);
      chunks = [];

      mediaRecorder.ondataavailable = (event) => {
        if (event.data && event.data.size > 0) {
          chunks.push(event.data);
        }
      };

      mediaRecorder.onstop = async () => {
        try {
          setStatus("uploaded");
          const blob = new Blob(chunks, { type: "audio/webm" });
          const formData = new FormData();
          formData.append("file", blob, "meeting.webm");
          if (titleInput && titleInput.value.trim()) {
            formData.append("title", titleInput.value.trim());
          }

          const response = await fetch("/api/meetings/upload-audio", {
            method: "POST",
            body: formData,
          });

          if (!response.ok) {
            const payload = await response.json().catch(() => ({}));
            throw new Error(payload.detail || "Не удалось загрузить аудио");
          }

          const meeting = await response.json();
          window.location.href = `/meetings/${meeting.id}`;
        } catch (err) {
          setStatus("failed");
          setError(err.message || "Не удалось загрузить аудио");
        } finally {
          cleanupStream();
        }
      };

      mediaRecorder.start(500);
      startRecordingTimer();
      setStatus("recording");
      startBtn.disabled = true;
      stopBtn.disabled = false;
    } catch (err) {
      setError(err.message || "Не удалось получить доступ к микрофону");
    }
  }

  function stopRecording() {
    if (!mediaRecorder) return;
    if (mediaRecorder.state !== "inactive") {
      mediaRecorder.stop();
    }
    stopRecordingTimer(false);
    setStatus("preprocessing");
    startBtn.disabled = false;
    stopBtn.disabled = true;
  }

  function cleanupStream() {
    stopRecordingTimer(true);
    if (mediaStream) {
      mediaStream.getTracks().forEach((track) => track.stop());
    }
    mediaStream = null;
    mediaRecorder = null;
    chunks = [];
  }

  if (startBtn && stopBtn) {
    startBtn.addEventListener("click", startRecording);
    stopBtn.addEventListener("click", stopRecording);
  }

  const meetingRoot = document.getElementById("meetingDetailRoot");
  if (meetingRoot) {
    const meetingId = meetingRoot.dataset.meetingId;
    const renameForm = document.getElementById("renameForm");
    const renameInput = document.getElementById("renameInput");
    const deleteBtn = document.getElementById("deleteBtn");
    const reprocessBtn = document.getElementById("reprocessBtn");
    const audioNode = document.getElementById("meetingAudio");
    const audioCurrentTimeNode = document.getElementById("audioCurrentTime");

    if (renameForm && renameInput) {
      renameForm.addEventListener("submit", async (event) => {
        event.preventDefault();
        const title = renameInput.value.trim();
        if (!title) return;

        const response = await fetch(`/api/meetings/${meetingId}`, {
          method: "PATCH",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ title }),
        });
        if (response.ok) {
          window.location.reload();
        } else {
          alert("Не удалось переименовать встречу");
        }
      });
    }

    if (deleteBtn) {
      deleteBtn.addEventListener("click", async () => {
        if (!confirm("Удалить эту встречу?")) return;

        const response = await fetch(`/api/meetings/${meetingId}`, {
          method: "DELETE",
        });
        if (response.ok) {
          window.location.href = "/meetings";
        } else {
          alert("Не удалось удалить встречу");
        }
      });
    }

    if (reprocessBtn) {
      reprocessBtn.addEventListener("click", async () => {
        reprocessBtn.disabled = true;
        const response = await fetch(`/api/meetings/${meetingId}/reprocess`, {
          method: "POST",
        });
        if (response.ok) {
          window.location.reload();
        } else {
          reprocessBtn.disabled = false;
          alert("Не удалось запустить переобработку");
        }
      });
    }

    if (audioNode && audioCurrentTimeNode) {
      audioNode.addEventListener("timeupdate", () => {
        audioCurrentTimeNode.textContent = formatTime(audioNode.currentTime);
      });

      document.querySelectorAll("button[data-seek]").forEach((button) => {
        button.addEventListener("click", () => {
          const delta = Number(button.dataset.seek || 0);
          audioNode.currentTime = Math.max(0, audioNode.currentTime + delta);
        });
      });

      document.querySelectorAll(".jump-btn").forEach((button) => {
        button.addEventListener("click", () => {
          const start = Number(button.dataset.start || 0);
          audioNode.currentTime = Math.max(0, start);
          audioNode.play().catch(() => null);
        });
      });
    }

    document.querySelectorAll(".speaker-select").forEach((selectNode) => {
      selectNode.addEventListener("change", async () => {
        const segmentId = Number(selectNode.dataset.segmentId || 0);
        if (!segmentId) return;

        const speakerLabel = String(selectNode.value || "").trim();
        const response = await fetch(`/api/meetings/${meetingId}/segments/${segmentId}`, {
          method: "PATCH",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ speaker_label: speakerLabel || null }),
        });

        if (!response.ok) {
          alert("Не удалось сохранить метку говорящего");
        }
      });
    });

    const statusBadgeNode = meetingRoot.querySelector(".badge");
    if (statusBadgeNode) {
      const statusText = (statusBadgeNode.dataset.status || statusBadgeNode.textContent || "").trim();
      if (statusText === "uploaded" || statusText === "preprocessing" || statusText === "transcribing") {
        setTimeout(() => window.location.reload(), 4000);
      }
    }
  }
})();
