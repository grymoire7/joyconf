const slugInput = document.getElementById("slug-input");
const connectBtn = document.getElementById("connect-btn");
const dot = document.getElementById("dot");
const statusText = document.getElementById("status-text");

chrome.storage.local.get("slug", ({ slug }) => {
  if (slug) slugInput.value = slug;
});

function setStatus(connected) {
  dot.className = "dot" + (connected ? " connected" : "");
  statusText.textContent = connected ? "Connected" : "Disconnected";
  connectBtn.textContent = connected ? "Disconnect" : "Connect";
}

connectBtn.addEventListener("click", () => {
  const slug = slugInput.value.trim();
  if (!slug) return;

  chrome.storage.local.set({ slug });

  chrome.tabs.query({ active: true, currentWindow: true }, ([tab]) => {
    chrome.tabs.sendMessage(tab.id, { type: "SET_SLUG", slug }, (response) => {
      setStatus(response?.connected ?? false);
    });
  });
});

// Check current status on popup open
chrome.tabs.query({ active: true, currentWindow: true }, ([tab]) => {
  chrome.tabs.sendMessage(tab.id, { type: "GET_STATUS" }, (response) => {
    setStatus(response?.connected ?? false);
  });
});
