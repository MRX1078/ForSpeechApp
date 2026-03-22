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

  const ITEM_STATUS_LABELS_RU = {
    open: "в работе",
    done: "выполнено",
  };

  function statusLabel(value) {
    return STATUS_LABELS_RU[value] || value;
  }

  function itemStatusLabel(value) {
    return ITEM_STATUS_LABELS_RU[value] || value;
  }

  function formatTime(seconds) {
    const value = Math.max(0, Math.floor(Number(seconds) || 0));
    const min = Math.floor(value / 60);
    const sec = value % 60;
    return `${String(min).padStart(2, "0")}:${String(sec).padStart(2, "0")}`;
  }

  function isEditableTarget(target) {
    if (!target) return false;
    const tagName = String(target.tagName || "").toLowerCase();
    if (tagName === "input" || tagName === "textarea" || tagName === "select") {
      return true;
    }
    return Boolean(target.isContentEditable);
  }

  function escapeHtml(value) {
    return String(value || "")
      .replaceAll("&", "&amp;")
      .replaceAll("<", "&lt;")
      .replaceAll(">", "&gt;")
      .replaceAll('"', "&quot;")
      .replaceAll("'", "&#039;");
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
  const waveCanvas = document.getElementById("recordingWaveCanvas");

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

  let audioContext = null;
  let sourceNode = null;
  let analyserNode = null;
  let analyserData = null;
  let waveCtx = null;
  let waveFrameId = null;
  let waveWidth = 0;
  let waveHeight = 0;
  let waveformHistory = [];

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

  function setupWaveCanvas() {
    if (!waveCanvas || waveCtx) return;
    waveCtx = waveCanvas.getContext("2d");
    resizeWaveCanvas();
    window.addEventListener("resize", resizeWaveCanvas);
    drawWave();
  }

  function resizeWaveCanvas() {
    if (!waveCanvas || !waveCtx) return;
    const dpr = window.devicePixelRatio || 1;
    const rect = waveCanvas.getBoundingClientRect();
    waveWidth = Math.max(320, Math.floor(rect.width || 320));
    waveHeight = Math.max(120, Math.floor(rect.height || 150));
    waveCanvas.width = Math.floor(waveWidth * dpr);
    waveCanvas.height = Math.floor(waveHeight * dpr);
    waveCtx.setTransform(dpr, 0, 0, dpr, 0, 0);
    drawWave();
  }

  function drawWaveBackground() {
    if (!waveCtx) return;
    const gradient = waveCtx.createLinearGradient(0, 0, 0, waveHeight);
    gradient.addColorStop(0, "rgba(15, 23, 42, 0.98)");
    gradient.addColorStop(1, "rgba(10, 23, 46, 0.95)");
    waveCtx.fillStyle = gradient;
    waveCtx.fillRect(0, 0, waveWidth, waveHeight);

    waveCtx.strokeStyle = "rgba(148, 163, 184, 0.20)";
    waveCtx.lineWidth = 1;
    waveCtx.beginPath();
    const rows = 4;
    for (let i = 1; i <= rows; i += 1) {
      const y = (waveHeight / (rows + 1)) * i;
      waveCtx.moveTo(0, y);
      waveCtx.lineTo(waveWidth, y);
    }
    waveCtx.stroke();
  }

  function drawWaveBars() {
    if (!waveCtx) return;

    const maxPoints = Math.max(90, Math.floor(waveWidth / 3));
    if (waveformHistory.length > maxPoints) {
      waveformHistory = waveformHistory.slice(waveformHistory.length - maxPoints);
    }

    if (waveformHistory.length === 0) {
      waveCtx.strokeStyle = "rgba(148, 163, 184, 0.40)";
      waveCtx.beginPath();
      waveCtx.moveTo(0, waveHeight / 2);
      waveCtx.lineTo(waveWidth, waveHeight / 2);
      waveCtx.stroke();
      return;
    }

    const barStep = waveWidth / maxPoints;
    const barWidth = Math.max(1.2, barStep * 0.6);
    waveCtx.fillStyle = recordingState === "paused"
      ? "rgba(250, 204, 21, 0.88)"
      : "rgba(52, 211, 153, 0.90)";

    waveformHistory.forEach((amp, idx) => {
      const x = idx * barStep;
      const barHeight = Math.max(2, amp * (waveHeight * 0.86));
      const y = (waveHeight - barHeight) / 2;
      waveCtx.fillRect(x, y, barWidth, barHeight);
    });
  }

  function drawWaveSegments() {
    if (!waveCtx) return;
    let duration = currentElapsedSec();
    if (segments.length > 0) {
      duration = Math.max(duration, segments[segments.length - 1].end);
    }
    if (activeSegmentStartSec !== null) {
      duration = Math.max(duration, activeSegmentStartSec + 0.0001);
    }
    if (duration <= 0.0001) return;

    const marks = [];
    segments.forEach((segment) => {
      marks.push(segment.start, segment.end);
    });
    if (activeSegmentStartSec !== null) {
      marks.push(activeSegmentStartSec);
    }

    waveCtx.strokeStyle = "rgba(248, 250, 252, 0.22)";
    waveCtx.lineWidth = 1;
    marks.forEach((timeSec) => {
      if (timeSec <= 0) return;
      const x = Math.min(waveWidth - 1, (timeSec / duration) * waveWidth);
      waveCtx.beginPath();
      waveCtx.moveTo(x, 8);
      waveCtx.lineTo(x, waveHeight - 8);
      waveCtx.stroke();
    });
  }

  function drawWavePlayhead() {
    if (!waveCtx) return;
    if (!["recording", "paused"].includes(recordingState)) return;
    let duration = currentElapsedSec();
    if (segments.length > 0) {
      duration = Math.max(duration, segments[segments.length - 1].end);
    }
    if (duration <= 0.0001) return;

    const x = Math.min(waveWidth - 1, (currentElapsedSec() / duration) * waveWidth);
    waveCtx.strokeStyle = "rgba(251, 113, 133, 0.95)";
    waveCtx.lineWidth = 2;
    waveCtx.beginPath();
    waveCtx.moveTo(x, 0);
    waveCtx.lineTo(x, waveHeight);
    waveCtx.stroke();
  }

  function drawWaveOverlayText() {
    if (!waveCtx) return;
    if (recordingState === "paused") {
      waveCtx.fillStyle = "rgba(255, 255, 255, 0.9)";
      waveCtx.font = '600 12px "Avenir Next", "SF Pro Text", sans-serif';
      waveCtx.fillText("Пауза", 10, 18);
    }
  }

  function drawWave() {
    if (!waveCtx) return;
    drawWaveBackground();
    drawWaveBars();
    drawWaveSegments();
    drawWavePlayhead();
    drawWaveOverlayText();
  }

  function stopWaveAnimation() {
    if (waveFrameId !== null) {
      cancelAnimationFrame(waveFrameId);
      waveFrameId = null;
    }
  }

  function sampleAmplitude() {
    if (!analyserNode || !analyserData) return 0;
    analyserNode.getByteTimeDomainData(analyserData);
    let sum = 0;
    for (let i = 0; i < analyserData.length; i += 1) {
      const centered = (analyserData[i] - 128) / 128;
      sum += centered * centered;
    }
    const rms = Math.sqrt(sum / analyserData.length);
    return Math.min(1, rms * 3.2);
  }

  function startWaveAnimation() {
    if (!waveCtx) return;
    stopWaveAnimation();

    const loop = () => {
      if (recordingState !== "recording") {
        drawWave();
        waveFrameId = null;
        return;
      }

      waveformHistory.push(sampleAmplitude());
      drawWave();
      waveFrameId = requestAnimationFrame(loop);
    };

    waveFrameId = requestAnimationFrame(loop);
  }

  async function setupWaveInput(stream) {
    if (!waveCanvas) return;
    setupWaveCanvas();

    const AudioContextClass = window.AudioContext || window.webkitAudioContext;
    if (!AudioContextClass) {
      setError("В этом браузере недоступна визуализация аудио.");
      return;
    }

    if (!audioContext || audioContext.state === "closed") {
      audioContext = new AudioContextClass();
    }

    if (audioContext.state === "suspended") {
      await audioContext.resume();
    }

    if (sourceNode) {
      sourceNode.disconnect();
      sourceNode = null;
    }

    sourceNode = audioContext.createMediaStreamSource(stream);
    analyserNode = audioContext.createAnalyser();
    analyserNode.fftSize = 1024;
    analyserNode.smoothingTimeConstant = 0.83;
    analyserData = new Uint8Array(analyserNode.fftSize);
    sourceNode.connect(analyserNode);
    startWaveAnimation();
  }

  async function teardownWaveInput() {
    stopWaveAnimation();

    if (sourceNode) {
      sourceNode.disconnect();
      sourceNode = null;
    }
    analyserNode = null;
    analyserData = null;

    if (audioContext) {
      try {
        await audioContext.close();
      } catch (_) {
        // ignore close errors
      }
      audioContext = null;
    }
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
      drawWave();
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
    drawWave();
  }

  function startRecordingTimer() {
    if (!recordingTimerNode) return;
    if (recordingTimerInterval) {
      clearInterval(recordingTimerInterval);
    }
    recordingTimerInterval = setInterval(() => {
      recordingTimerNode.textContent = formatTime(currentElapsedSec());
      renderSegmentList();
      if (recordingState !== "recording") {
        drawWave();
      }
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

    primaryBtn.classList.remove("recording", "paused", "loading", "idle");
    if (recordingState === "idle") {
      primaryBtn.textContent = "Начать запись";
      primaryBtn.classList.add("idle");
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
    waveformHistory = [];
    stopRecordingTimer(true);
    renderSegmentList();
    renderRecordingControls();
    drawWave();
  }

  async function beginRecordingSession() {
    setError("");
    if (!navigator.mediaDevices || !navigator.mediaDevices.getUserMedia) {
      setError("Браузер не поддерживает запись с микрофона.");
      return;
    }

    try {
      mediaStream = await navigator.mediaDevices.getUserMedia({ audio: true });
      const mimeCandidates = ["audio/webm;codecs=opus", "audio/webm", "audio/mp4"];
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
      waveformHistory = [];

      mediaRecorder.ondataavailable = (event) => {
        if (event.data && event.data.size > 0) {
          chunks.push(event.data);
        }
      };

      mediaRecorder.onstop = async () => {
        if (discardCurrentRecording) {
          await cleanupStream();
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
          await cleanupStream();
          resetSessionState();
        }
      };

      mediaRecorder.start(500);
      await setupWaveInput(mediaStream);
      openActiveSegment();
      startRecordingTimer();
      recordingState = "recording";
      renderRecordingControls();
      drawWave();
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
    stopWaveAnimation();
    renderRecordingControls();
    drawWave();
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
    startWaveAnimation();
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
      stopWaveAnimation();
      drawWave();
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
      stopWaveAnimation();
      mediaRecorder.stop();
    } else {
      cleanupStream().finally(resetSessionState);
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

  async function cleanupStream() {
    stopRecordingTimer(false);
    stopWaveAnimation();

    if (mediaStream) {
      mediaStream.getTracks().forEach((track) => track.stop());
    }
    mediaStream = null;
    mediaRecorder = null;
    await teardownWaveInput();
  }

  function handleRecorderHotkeys(event) {
    if (!primaryBtn || !finishBtn || !resetBtn) return;
    if (event.repeat) return;
    if (isEditableTarget(event.target)) return;
    if (recordingState === "uploading") return;

    const code = event.code || "";
    const key = event.key || "";

    if (code === "Space" || key === " ") {
      event.preventDefault();
      handlePrimaryButton();
      return;
    }

    if (key === "Enter") {
      if (recordingState === "recording" || recordingState === "paused") {
        event.preventDefault();
        finishRecording();
      }
    }
  }

  if (primaryBtn && finishBtn && resetBtn) {
    setupWaveCanvas();
    renderSegmentList();
    renderRecordingControls();
    primaryBtn.addEventListener("click", handlePrimaryButton);
    finishBtn.addEventListener("click", finishRecording);
    resetBtn.addEventListener("click", discardRecording);
    document.addEventListener("keydown", handleRecorderHotkeys);
  }

  function agreementItemHtml(agreement) {
    const selectedOpen = agreement.status === "open" ? "selected" : "";
    const selectedDone = agreement.status === "done" ? "selected" : "";
    return `
      <li class="work-item" data-agreement-id="${agreement.id}">
        <div class="work-item-head">
          <span class="badge item-status ${escapeHtml(agreement.status)}">${escapeHtml(itemStatusLabel(agreement.status))}</span>
          <select class="input agreement-status-select inline-input">
            <option value="open" ${selectedOpen}>в работе</option>
            <option value="done" ${selectedDone}>выполнено</option>
          </select>
          <button class="btn agreement-save-btn" type="button">Сохранить</button>
          <button class="btn btn-danger agreement-delete-btn" type="button">Удалить</button>
        </div>
        <input class="input agreement-text-input" type="text" maxlength="2000" value="${escapeHtml(agreement.text)}" />
        <input class="input agreement-owner-input inline-input" type="text" maxlength="128" placeholder="Ответственный" value="${escapeHtml(agreement.owner || "")}" />
        <div class="muted">Обновлено: ${escapeHtml(agreement.updated_at || "")}</div>
      </li>
    `;
  }

  function bindAgreementItemNode(itemNode, meetingId) {
    const saveBtn = itemNode.querySelector(".agreement-save-btn");
    const deleteBtn = itemNode.querySelector(".agreement-delete-btn");
    const statusSelect = itemNode.querySelector(".agreement-status-select");
    const textInput = itemNode.querySelector(".agreement-text-input");
    const ownerInput = itemNode.querySelector(".agreement-owner-input");
    const badgeNode = itemNode.querySelector(".item-status");
    const agreementId = Number(itemNode.dataset.agreementId || 0);
    if (!agreementId) return;

    if (saveBtn && statusSelect && textInput && ownerInput) {
      saveBtn.addEventListener("click", async () => {
        const payload = {
          text: textInput.value.trim(),
          owner: ownerInput.value.trim() || null,
          status: statusSelect.value,
        };
        if (!payload.text) {
          alert("Текст договоренности не может быть пустым");
          return;
        }

        const response = await fetch(`/api/meetings/${meetingId}/agreements/${agreementId}`, {
          method: "PATCH",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify(payload),
        });
        if (!response.ok) {
          alert("Не удалось обновить договоренность");
          return;
        }
        const updated = await response.json();
        if (badgeNode) {
          badgeNode.textContent = itemStatusLabel(updated.status);
          badgeNode.className = `badge item-status ${updated.status}`;
        }
      });
    }

    if (deleteBtn) {
      deleteBtn.addEventListener("click", async () => {
        if (!confirm("Удалить договоренность?")) return;
        const response = await fetch(`/api/meetings/${meetingId}/agreements/${agreementId}`, {
          method: "DELETE",
        });
        if (!response.ok) {
          alert("Не удалось удалить договоренность");
          return;
        }
        itemNode.remove();
        const listNode = document.getElementById("meetingAgreementsList");
        const emptyStateNode = document.getElementById("agreementEmptyState");
        if (listNode && listNode.children.length === 0 && !emptyStateNode) {
          const p = document.createElement("p");
          p.id = "agreementEmptyState";
          p.className = "muted";
          p.textContent = "Пока нет договоренностей.";
          listNode.insertAdjacentElement("beforebegin", p);
        }
      });
    }
  }

  function workspaceItemHtml(item) {
    const kindLabel = item.kind === "task" ? "дело" : "заметка";
    const selectedOpen = item.status === "open" ? "selected" : "";
    const selectedDone = item.status === "done" ? "selected" : "";
    return `
      <li class="work-item" data-item-id="${item.id}" data-kind="${escapeHtml(item.kind)}">
        <div class="work-item-head">
          <span class="badge kind ${escapeHtml(item.kind)}">${kindLabel}</span>
          <select class="input workspace-status-select">
            <option value="open" ${selectedOpen}>в работе</option>
            <option value="done" ${selectedDone}>выполнено</option>
          </select>
          <button class="btn workspace-save-btn" type="button">Сохранить</button>
          <button class="btn btn-danger workspace-delete-btn" type="button">Удалить</button>
        </div>
        <input class="input workspace-title-input" type="text" maxlength="255" value="${escapeHtml(item.title)}" />
        <textarea class="input workspace-content-input">${escapeHtml(item.content || "")}</textarea>
        <div class="muted">Обновлено: ${escapeHtml(item.updated_at || "")}</div>
      </li>
    `;
  }

  function bindWorkspaceItemNode(itemNode) {
    const itemId = Number(itemNode.dataset.itemId || 0);
    if (!itemId) return;

    const saveBtn = itemNode.querySelector(".workspace-save-btn");
    const deleteBtn = itemNode.querySelector(".workspace-delete-btn");
    const statusSelect = itemNode.querySelector(".workspace-status-select");
    const titleInput = itemNode.querySelector(".workspace-title-input");
    const contentInput = itemNode.querySelector(".workspace-content-input");

    if (saveBtn && statusSelect && titleInput && contentInput) {
      saveBtn.addEventListener("click", async () => {
        const payload = {
          title: titleInput.value.trim(),
          content: contentInput.value.trim(),
          status: statusSelect.value,
        };
        if (!payload.title) {
          alert("Заголовок не может быть пустым");
          return;
        }

        const response = await fetch(`/api/planning/work-items/${itemId}`, {
          method: "PATCH",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify(payload),
        });
        if (!response.ok) {
          alert("Не удалось обновить запись");
        }
      });
    }

    if (deleteBtn) {
      deleteBtn.addEventListener("click", async () => {
        if (!confirm("Удалить запись?")) return;
        const response = await fetch(`/api/planning/work-items/${itemId}`, {
          method: "DELETE",
        });
        if (!response.ok) {
          alert("Не удалось удалить запись");
          return;
        }
        itemNode.remove();
        const listNode = document.getElementById("workspaceItemsList");
        const emptyStateNode = document.getElementById("workspaceItemsEmpty");
        if (listNode && listNode.children.length === 0 && !emptyStateNode) {
          const p = document.createElement("p");
          p.id = "workspaceItemsEmpty";
          p.className = "muted";
          p.textContent = "Пока нет дел и заметок.";
          listNode.insertAdjacentElement("beforebegin", p);
        }
      });
    }
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

    const agreementsRoot = document.getElementById("meetingAgreementsRoot");
    if (agreementsRoot) {
      const listNode = document.getElementById("meetingAgreementsList");
      const createForm = document.getElementById("meetingAgreementCreateForm");
      const textNode = document.getElementById("agreementText");
      const ownerNode = document.getElementById("agreementOwner");
      const statusNode = document.getElementById("agreementStatus");
      const createErrorNode = document.getElementById("agreementCreateError");

      if (listNode) {
        listNode.querySelectorAll(".work-item").forEach((node) => bindAgreementItemNode(node, meetingId));
      }

      if (createForm && textNode && ownerNode && statusNode) {
        createForm.addEventListener("submit", async (event) => {
          event.preventDefault();
          if (createErrorNode) createErrorNode.textContent = "";
          const payload = {
            text: textNode.value.trim(),
            owner: ownerNode.value.trim() || null,
            status: statusNode.value,
          };
          if (!payload.text) {
            if (createErrorNode) createErrorNode.textContent = "Введите текст договоренности";
            return;
          }

          const response = await fetch(`/api/meetings/${meetingId}/agreements`, {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify(payload),
          });
          if (!response.ok) {
            if (createErrorNode) createErrorNode.textContent = "Не удалось добавить договоренность";
            return;
          }
          const agreement = await response.json();
          if (listNode) {
            const emptyStateNode = document.getElementById("agreementEmptyState");
            if (emptyStateNode) emptyStateNode.remove();
            listNode.insertAdjacentHTML("afterbegin", agreementItemHtml(agreement));
            const newNode = listNode.firstElementChild;
            if (newNode) bindAgreementItemNode(newNode, meetingId);
          }
          textNode.value = "";
          ownerNode.value = "";
          statusNode.value = "open";
        });
      }
    }

    const statusBadgeNode = meetingRoot.querySelector(".section-head > .badge");
    if (statusBadgeNode) {
      const statusText = (statusBadgeNode.dataset.status || statusBadgeNode.textContent || "").trim();
      if (statusText === "uploaded" || statusText === "preprocessing" || statusText === "transcribing") {
        setTimeout(() => window.location.reload(), 4000);
      }
    }
  }

  const planningRoot = document.getElementById("planningRoot");
  if (planningRoot) {
    const listNode = document.getElementById("workspaceItemsList");
    const createForm = document.getElementById("workspaceItemCreateForm");
    const kindNode = document.getElementById("workspaceKind");
    const titleNode = document.getElementById("workspaceTitle");
    const contentNode = document.getElementById("workspaceContent");
    const createErrorNode = document.getElementById("workspaceCreateError");

    if (listNode) {
      listNode.querySelectorAll(".work-item").forEach((node) => bindWorkspaceItemNode(node));
    }

    if (createForm && kindNode && titleNode && contentNode) {
      createForm.addEventListener("submit", async (event) => {
        event.preventDefault();
        if (createErrorNode) createErrorNode.textContent = "";

        const payload = {
          kind: kindNode.value,
          title: titleNode.value.trim(),
          content: contentNode.value.trim(),
          status: "open",
        };
        if (!payload.title) {
          if (createErrorNode) createErrorNode.textContent = "Введите заголовок";
          return;
        }

        const response = await fetch("/api/planning/work-items", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify(payload),
        });
        if (!response.ok) {
          if (createErrorNode) createErrorNode.textContent = "Не удалось добавить запись";
          return;
        }

        const item = await response.json();
        if (listNode) {
          const emptyStateNode = document.getElementById("workspaceItemsEmpty");
          if (emptyStateNode) emptyStateNode.remove();
          listNode.insertAdjacentHTML("afterbegin", workspaceItemHtml(item));
          const newNode = listNode.firstElementChild;
          if (newNode) bindWorkspaceItemNode(newNode);
        }

        kindNode.value = "task";
        titleNode.value = "";
        contentNode.value = "";
      });
    }
  }
})();
