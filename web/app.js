const createButton = document.getElementById("aws-login");
const cleanupButton = document.getElementById("aws-cleanup");
const modal = document.getElementById("progress-modal");
const titleEl = document.getElementById("progress-title");
const detailEl = document.getElementById("progress-detail");
const stepsEl = document.getElementById("progress-steps");
const closeBtn = document.getElementById("progress-close");
const jsonEl = document.getElementById("progress-json");
const errorEl = document.getElementById("progress-error");
const messageModal = document.getElementById("message-modal");
const messageTitleEl = document.getElementById("message-title");
const messageBodyEl = document.getElementById("message-body");
const messageCloseBtn = document.getElementById("message-close");

const CREATE_STEPS = [
  ["create", "Creating instance"],
  ["created", "Instance created"],
  ["waiting", "Waiting for running"],
  ["running", "Instance running"],
  ["ip_create", "Creating static IP"],
  ["ip_created", "Static IP created"],
  ["ip_attach", "Attaching static IP"],
  ["ip_attached", "Static IP attached"],
  ["ssh", "SSH into server"],
  ["outline", "Install Outline (+ Docker)"],
  ["firewall", "Open Lightsail firewall ports"],
  ["outline_manager", "Open Outline Manager + paste JSON"],
  ["access_key", "Done → share Key 0 → copy access key"],
  ["done", "Complete"],
];

const CLEANUP_STEPS = [
  ["stop", "Stopping instance"],
  ["stopped", "Instance stopped"],
  ["delete_instance", "Deleting instance"],
  ["instance_deleted", "Instance deleted"],
  ["delete_ip", "Deleting static IP"],
  ["ip_deleted", "Static IP deleted"],
  ["done", "Cleanup complete"],
];

let activeStepOrder = CREATE_STEPS.map(([id]) => id);
let activeButtons = [createButton, cleanupButton];

function setButtonsDisabled(disabled) {
  for (const button of activeButtons) {
    button.disabled = disabled;
  }
}

function renderSteps(steps) {
  activeStepOrder = steps.map(([id]) => id);
  stepsEl.innerHTML = "";
  for (const [id, label] of steps) {
    const li = document.createElement("li");
    li.dataset.step = id;
    li.dataset.state = "pending";
    li.textContent = label;
    stepsEl.appendChild(li);
  }
}

function openModal(title, steps) {
  titleEl.textContent = title;
  renderSteps(steps);
  modal.hidden = false;
  document.body.classList.add("modal-open");
  closeBtn.hidden = true;
  jsonEl.hidden = true;
  jsonEl.textContent = "";
  errorEl.hidden = true;
  errorEl.textContent = "";
  detailEl.textContent = "Starting…";
  detailEl.dataset.kind = "pending";
}

function closeModal() {
  modal.hidden = true;
  if (messageModal.hidden) {
    document.body.classList.remove("modal-open");
  }
}

function showMessagePopup(title, message) {
  messageTitleEl.textContent = title;
  messageBodyEl.textContent = message;
  messageModal.hidden = false;
  document.body.classList.add("modal-open");
}

function closeMessagePopup() {
  messageModal.hidden = true;
  if (modal.hidden) {
    document.body.classList.remove("modal-open");
  }
}

function markStep(stepId, message) {
  const index = activeStepOrder.indexOf(stepId);
  if (index === -1) return;

  for (const li of stepsEl.querySelectorAll("[data-step]")) {
    const step = li.dataset.step;
    const stepIndex = activeStepOrder.indexOf(step);
    if (stepIndex < index) {
      li.dataset.state = "done";
    } else if (stepIndex === index) {
      li.dataset.state = stepId === "done" ? "done" : "active";
    } else {
      li.dataset.state = "pending";
    }
  }

  if (message) {
    detailEl.textContent = message;
  }
}

function finishModal(ok, message, outlineJson = null, errorText = null, accessKey = null) {
  detailEl.textContent = message;
  detailEl.dataset.kind = ok ? "ok" : "error";
  closeBtn.hidden = false;
  setButtonsDisabled(false);

  if (ok && accessKey) {
    jsonEl.hidden = false;
    jsonEl.textContent = accessKey;
  }

  if (!ok) {
    const fullError = errorText || message || "Operation failed";
    errorEl.hidden = false;
    errorEl.textContent = fullError;
    const active = stepsEl.querySelector('[data-state="active"]');
    if (active) active.dataset.state = "error";
    return;
  }

  markStep("done", message);
}

function handleProgressLine(line) {
  if (!line.startsWith("PROGRESS|")) return false;
  const [, step, ...rest] = line.split("|");
  const message = rest.join("|");
  if (step === "error") {
    finishModal(false, message || "Operation failed", null, message);
    return true;
  }
  markStep(step, message);
  return true;
}

async function runJob({ endpoint, title, steps, successMessage }) {
  setButtonsDisabled(true);
  openModal(title, steps);

  try {
    const response = await fetch(endpoint, { method: "POST" });
    if (!response.ok) {
      throw new Error(`Server returned ${response.status}`);
    }

    const reader = response.body.getReader();
    const decoder = new TextDecoder();
    let buffer = "";
    let sawError = false;
    let lastMessage = successMessage;
    let errorText = null;
    let accessKey = null;

    while (true) {
      const { value, done } = await reader.read();
      if (done) break;
      buffer += decoder.decode(value, { stream: true });
      const lines = buffer.split("\n");
      buffer = lines.pop() ?? "";

      for (const raw of lines) {
        const line = raw.trim();
        if (!line) continue;
        if (line.startsWith("ERROR:")) {
          sawError = true;
          errorText = line.replace(/^ERROR:\s*/, "");
          lastMessage = errorText;
          continue;
        }
        if (line.startsWith("FAILED")) {
          sawError = true;
          // Keep a more specific ERROR:/PROGRESS|error message when present.
          if (!errorText) {
            errorText = line;
            lastMessage = line;
          }
          continue;
        }
        if (handleProgressLine(line)) {
          lastMessage = line.split("|").slice(2).join("|") || lastMessage;
          if (line.includes("|error|")) {
            sawError = true;
            errorText = lastMessage;
          }
          continue;
        }
        if (line.startsWith("ss://") || line.startsWith("ssconf://")) {
          accessKey = line;
          lastMessage = "Access key ready";
          continue;
        }
        try {
          const payload = JSON.parse(line);
          if (payload.ok === false && payload.error) {
            sawError = true;
            errorText = payload.error;
            lastMessage = payload.error.split("\n")[0];
            continue;
          }
          if (payload.ok && payload.accessKey) {
            accessKey = payload.accessKey;
            lastMessage = "Access key ready";
          }
          if (payload.ok && payload.cleaned) {
            lastMessage = "Cleanup complete";
          }
        } catch {
          // ignore non-JSON noise
        }
      }
    }

    if (buffer.trim()) {
      const line = buffer.trim();
      handleProgressLine(line);
      if (line.startsWith("ss://") || line.startsWith("ssconf://")) {
        accessKey = line;
      }
      try {
        const payload = JSON.parse(line);
        if (payload.ok === false && payload.error) {
          sawError = true;
          errorText = payload.error;
          lastMessage = payload.error.split("\n")[0];
        }
        if (payload.ok && payload.accessKey) accessKey = payload.accessKey;
        if (payload.ok && payload.cleaned) lastMessage = "Cleanup complete";
      } catch {
        // ignore
      }
    }

    if (sawError) {
      finishModal(false, lastMessage, null, errorText || lastMessage);
    } else {
      finishModal(true, lastMessage, null, null, accessKey);
    }
  } catch (error) {
    finishModal(false, error.message || "Request failed", null, error.message);
  }
}

closeBtn.addEventListener("click", closeModal);
modal.querySelector("[data-close-modal]").addEventListener("click", () => {
  if (!closeBtn.hidden) closeModal();
});
messageCloseBtn.addEventListener("click", closeMessagePopup);
messageModal.querySelector("[data-close-message]").addEventListener("click", closeMessagePopup);

createButton.addEventListener("click", () => {
  runJob({
    endpoint: "/api/create-instance",
    title: "Provisioning progress",
    steps: CREATE_STEPS,
    successMessage: "Done.",
  });
});

async function runCleanup() {
  setButtonsDisabled(true);

  try {
    const response = await fetch("/api/cleanup-instance", { method: "POST" });
    if (!response.ok) {
      throw new Error(`Server returned ${response.status}`);
    }

    const reader = response.body.getReader();
    const decoder = new TextDecoder();
    let buffer = "";
    let progressOpened = false;
    let sawError = false;
    let lastMessage = "Cleanup complete";
    let errorText = null;
    let notFoundMessage = null;

    while (true) {
      const { value, done } = await reader.read();
      if (done) break;
      buffer += decoder.decode(value, { stream: true });
      const lines = buffer.split("\n");
      buffer = lines.pop() ?? "";

      for (const raw of lines) {
        const line = raw.trim();
        if (!line) continue;

        if (line.startsWith("PROGRESS|")) {
          if (!progressOpened) {
            openModal("Cleanup progress", CLEANUP_STEPS);
            progressOpened = true;
          }
          handleProgressLine(line);
          lastMessage = line.split("|").slice(2).join("|") || lastMessage;
          if (line.includes("|error|")) {
            sawError = true;
            errorText = lastMessage;
          }
          continue;
        }

        if (line.startsWith("ERROR:")) {
          sawError = true;
          errorText = line.replace(/^ERROR:\s*/, "");
          lastMessage = errorText;
          continue;
        }
        if (line.startsWith("FAILED")) {
          sawError = true;
          if (!errorText) {
            errorText = line;
            lastMessage = line;
          }
          continue;
        }

        try {
          const payload = JSON.parse(line);
          if (payload.notFound) {
            notFoundMessage =
              payload.error || `Instance ${payload.instance || "cusor_instance"} does not exist.`;
            continue;
          }
          if (payload.ok === false && payload.error) {
            sawError = true;
            errorText = payload.error;
            lastMessage = payload.error.split("\n")[0];
            continue;
          }
          if (payload.ok && payload.cleaned) {
            lastMessage = "Cleanup complete";
          }
        } catch {
          // ignore non-JSON noise
        }
      }
    }

    if (buffer.trim()) {
      try {
        const payload = JSON.parse(buffer.trim());
        if (payload.notFound) {
          notFoundMessage =
            payload.error || `Instance ${payload.instance || "cusor_instance"} does not exist.`;
        }
      } catch {
        // ignore
      }
    }

    if (notFoundMessage) {
      setButtonsDisabled(false);
      showMessagePopup("Cleanup", notFoundMessage);
      return;
    }

    if (!progressOpened) {
      openModal("Cleanup progress", CLEANUP_STEPS);
    }

    if (sawError) {
      finishModal(false, lastMessage, null, errorText || lastMessage);
    } else {
      finishModal(true, lastMessage);
    }
  } catch (error) {
    setButtonsDisabled(false);
    showMessagePopup("Cleanup", error.message || "Request failed");
  }
}

cleanupButton.addEventListener("click", () => {
  runCleanup();
});
