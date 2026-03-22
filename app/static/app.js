(function () {
  const STATUS_LABELS_RU = {
    idle: "ожидание",
    recording: "запись",
    paused: "пауза",
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

  const primaryBtn = document.getElementById("recordingPrimaryBtn");
  const finishBtn = document.getElementById("finishRecordingBtn");
  const resetBtn = document.getElementById("resetRecordingBtn");
  const statusBadge = document.getElementById("recordingStatusBadge");
  const errorNode = document.getElementById("recordingError");
  const titleInput = document.getElementById("meetingTitle");
  const recordingTimerNode = document.getElementById("recordingTimer");
  const segmentsListNode = document.getElementById("recordingSegmentsList");
  const segmentCountNode = document.getElementById("segmentCountLabel");

  let mediaRecorder = null;
  let mediaStream = null;
  let chunks = [];
  let recordingState = "idle";
  let discardCurrentRecording = false;
  let elapsedMs = 0;
  let phaseStartedAtMs = null;
  let recordingTimerInterval = null;
  let segments = [];
  let activeSegmentStartSec = null;
  let currentRecordingFilename = "meeting.webm";

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

  function currentElapsedMs() {
    if (phaseStartedAtMs) {
      return elapsedMs + (Date.now() - phaseStartedAtMs);
    }
    return elapsedMs;
  }

  function currentElapsedSec() {
    return currentElapsedMs() / 1000;
  }

  function renderSegmentList() {
    if (!segmentsListNode) return;
    const rows = [];

    segments.forEach((segment, idx) => {
      rows.push(
        `<li><span>Отрезок ${idx + 1}</span><strong>${formatTime(segment.start)} - ${formatTime(segment.end)}</strong></li>`
      );
    });

    if (recordingState === "recording" && activeSegmentStartSec !== null) {
      rows.push(
        `<li class="live"><span>Текущий отрезок</span><strong>${formatTime(activeSegmentStartSec)} - ...</strong></li>`
      );
    }

    if (rows.length === 0) {
      rows.push('<li class="muted">Пока нет отрезков</li>');
    }

    segmentsListNode.innerHTML = rows.join("");
    if (segmentCountNode) {
      segmentCountNode.textContent = String(segments.length + (activeSegmentStartSec !== null ? 1 : 0));
    }
  }

  function openActiveSegment() {
    if (activeSegmentStartSec === null) {
      activeSegmentStartSec = currentElapsedSec();
      renderSegmentList();
    }
  }

  function closeActiveSegment() {
    if (activeSegmentStartSec === null) return;
    const end = currentElapsedSec();
    if (end - activeSegmentStartSec >= 0.1) {
      segments.push({
        start: activeSegmentStartSec,
        end,
      });
    }
    activeSegmentStartSec = null;
    renderSegmentList();
  }

  function startRecordingTimer() {
    if (!recordingTimerNode) return;
    if (recordingTimerInterval) {
      clearInterval(recordingTimerInterval);
    }
    recordingTimerInterval = setInterval(() => {
      recordingTimerNode.textContent = formatTime(currentElapsedSec());
      renderSegmentList();
    }, 200);
  }

  function stopRecordingTimer(resetSession) {
    if (recordingTimerInterval) {
      clearInterval(recordingTimerInterval);
      recordingTimerInterval = null;
    }
    if (resetSession && recordingTimerNode) {
      recordingTimerNode.textContent = "00:00";
    }
  }

  function renderRecordingControls() {
    if (!primaryBtn || !finishBtn || !resetBtn) return;

    primaryBtn.classList.remove("recording", "paused", "loading");
    if (recordingState === "idle") {
      primaryBtn.textContent = "Начать запись";
      primaryBtn.disabled = false;
      finishBtn.disabled = true;
      resetBtn.disabled = true;
      setStatus("idle");
    } else if (recordingState === "recording") {
      primaryBtn.textContent = "Пауза";
      primaryBtn.classList.add("recording");
      primaryBtn.disabled = false;
      finishBtn.disabled = false;
      resetBtn.disabled = false;
      setStatus("recording");
    } else if (recordingState === "paused") {
      primaryBtn.textContent = "Продолжить";
      primaryBtn.classList.add("paused");
      primaryBtn.disabled = false;
      finishBtn.disabled = false;
      resetBtn.disabled = false;
      setStatus("paused");
    } else if (recordingState === "uploading") {
      primaryBtn.textContent = "Сохранение...";
      primaryBtn.classList.add("loading");
      primaryBtn.disabled = true;
      finishBtn.disabled = true;
      resetBtn.disabled = true;
      setStatus("preprocessing");
    }
  }

  function resetSessionState() {
    recordingState = "idle";
    discardCurrentRecording = false;
    elapsedMs = 0;
    phaseStartedAtMs = null;
    segments = [];
    activeSegmentStartSec = null;
    currentRecordingFilename = "meeting.webm";
    chunks = [];
    stopRecordingTimer(true);
    renderSegmentList();
    renderRecordingControls();
  }

  async function beginRecordingSession() {
    setError("");
    if (!navigator.mediaDevices || !navigator.mediaDevices.getUserMedia) {
      setError("Браузер не поддерживает запись с микрофона.");
      return;
    }

    try {
      mediaStream = await navigator.mediaDevices.getUserMedia({ audio: true });
      const mimeCandidates = [
        "audio/webm;codecs=opus",
        "audio/webm",
        "audio/mp4",
      ];
      const selectedMimeType = mimeCandidates.find((mime) => {
        if (!window.MediaRecorder || typeof MediaRecorder.isTypeSupported !== "function") {
          return false;
        }
        return MediaRecorder.isTypeSupported(mime);
      });

      const options = selectedMimeType ? { mimeType: selectedMimeType } : {};
      currentRecordingFilename = selectedMimeType && selectedMimeType.includes("mp4")
        ? "meeting.m4a"
        : "meeting.webm";
      mediaRecorder = new MediaRecorder(mediaStream, options);
      chunks = [];
      elapsedMs = 0;
      phaseStartedAtMs = Date.now();
      segments = [];
      activeSegmentStartSec = null;
      discardCurrentRecording = false;

      mediaRecorder.ondataavailable = (event) => {
        if (event.data && event.data.size > 0) {
          chunks.push(event.data);
        }
      };

      mediaRecorder.onstop = async () => {
        if (discardCurrentRecording) {
          cleanupStream();
          resetSessionState();
          return;
        }

        try {
          setStatus("uploaded");
          const blobType = (chunks[0] && chunks[0].type) || options.mimeType || "audio/webm";
          const blob = new Blob(chunks, { type: blobType });
          const formData = new FormData();
          formData.append("file", blob, currentRecordingFilename);
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
          resetSessionState();
        }
      };

      mediaRecorder.start(500);
      openActiveSegment();
      startRecordingTimer();
      recordingState = "recording";
      renderRecordingControls();
    } catch (err) {
      setError(err.message || "Не удалось получить доступ к микрофону");
    }
  }

  function pauseRecording() {
    if (!mediaRecorder || mediaRecorder.state !== "recording") return;
    if (typeof mediaRecorder.pause !== "function") {
      setError("Пауза не поддерживается в этом браузере.");
      return;
    }
    mediaRecorder.pause();
    if (phaseStartedAtMs) {
      elapsedMs += Date.now() - phaseStartedAtMs;
      phaseStartedAtMs = null;
    }
    closeActiveSegment();
    recordingState = "paused";
    renderRecordingControls();
  }

  function resumeRecording() {
    if (!mediaRecorder || mediaRecorder.state !== "paused") return;
    if (typeof mediaRecorder.resume !== "function") {
      setError("Продолжение записи не поддерживается в этом браузере.");
      return;
    }
    mediaRecorder.resume();
    phaseStartedAtMs = Date.now();
    openActiveSegment();
    recordingState = "recording";
    renderRecordingControls();
  }

  function finishRecording() {
    if (!mediaRecorder) return;
    if (mediaRecorder.state === "recording") {
      elapsedMs += Date.now() - phaseStartedAtMs;
      phaseStartedAtMs = null;
      closeActiveSegment();
    }
    if (mediaRecorder.state === "recording" || mediaRecorder.state === "paused") {
      recordingState = "uploading";
      renderRecordingControls();
      mediaRecorder.stop();
    }
  }

  function discardRecording() {
    if (!mediaRecorder) {
      resetSessionState();
      return;
    }
    if (!confirm("Сбросить текущую запись?")) return;
    discardCurrentRecording = true;
    if (mediaRecorder.state === "recording") {
      elapsedMs += Date.now() - phaseStartedAtMs;
      phaseStartedAtMs = null;
      closeActiveSegment();
    }
    if (mediaRecorder.state === "recording" || mediaRecorder.state === "paused") {
      mediaRecorder.stop();
    } else {
      cleanupStream();
      resetSessionState();
    }
  }

  function handlePrimaryButton() {
    if (recordingState === "idle") {
      beginRecordingSession();
      return;
    }
    if (recordingState === "recording") {
      pauseRecording();
      return;
    }
    if (recordingState === "paused") {
      resumeRecording();
    }
  }

  function cleanupStream() {
    stopRecordingTimer(false);
    if (mediaStream) {
      mediaStream.getTracks().forEach((track) => track.stop());
    }
    mediaStream = null;
    mediaRecorder = null;
  }

  if (primaryBtn && finishBtn && resetBtn) {
    renderSegmentList();
    renderRecordingControls();
    primaryBtn.addEventListener("click", handlePrimaryButton);
    finishBtn.addEventListener("click", finishRecording);
    resetBtn.addEventListener("click", discardRecording);
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
