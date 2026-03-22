(function () {
  const startBtn = document.getElementById("startRecordingBtn");
  const stopBtn = document.getElementById("stopRecordingBtn");
  const statusBadge = document.getElementById("recordingStatusBadge");
  const errorNode = document.getElementById("recordingError");
  const titleInput = document.getElementById("meetingTitle");

  let mediaRecorder = null;
  let mediaStream = null;
  let chunks = [];

  function setStatus(value) {
    if (!statusBadge) return;
    statusBadge.textContent = value;
    statusBadge.className = "badge " + value;
  }

  function setError(message) {
    if (!errorNode) return;
    errorNode.textContent = message || "";
  }

  async function startRecording() {
    setError("");
    if (!navigator.mediaDevices || !navigator.mediaDevices.getUserMedia) {
      setError("Browser does not support microphone recording.");
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
            throw new Error(payload.detail || "Upload failed");
          }

          const meeting = await response.json();
          window.location.href = `/meetings/${meeting.id}`;
        } catch (err) {
          setStatus("failed");
          setError(err.message || "Upload failed");
        } finally {
          cleanupStream();
        }
      };

      mediaRecorder.start(500);
      setStatus("recording");
      startBtn.disabled = true;
      stopBtn.disabled = false;
    } catch (err) {
      setError(err.message || "Microphone access failed");
    }
  }

  function stopRecording() {
    if (!mediaRecorder) return;
    if (mediaRecorder.state !== "inactive") {
      mediaRecorder.stop();
    }
    setStatus("preprocessing");
    startBtn.disabled = false;
    stopBtn.disabled = true;
  }

  function cleanupStream() {
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
          alert("Rename failed");
        }
      });
    }

    if (deleteBtn) {
      deleteBtn.addEventListener("click", async () => {
        if (!confirm("Delete this meeting?")) return;

        const response = await fetch(`/api/meetings/${meetingId}`, {
          method: "DELETE",
        });
        if (response.ok) {
          window.location.href = "/meetings";
        } else {
          alert("Delete failed");
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
          alert("Reprocess failed");
        }
      });
    }

    const statusBadgeNode = meetingRoot.querySelector(".badge");
    if (statusBadgeNode) {
      const statusText = statusBadgeNode.textContent.trim();
      if (statusText === "uploaded" || statusText === "preprocessing" || statusText === "transcribing") {
        setTimeout(() => window.location.reload(), 4000);
      }
    }
  }
})();
