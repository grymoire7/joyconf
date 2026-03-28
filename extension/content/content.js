// Phoenix UMD build loaded before this file exposes window.Phoenix
const { Socket } = window.Phoenix;

const HOST = "wss://joyconf.fly.dev";
// const HOST = "ws://localhost:4000";

let socket = null;
let channel = null;
let slideObserver = null;
let currentSlide = 0;

// Inject animation keyframes once
const style = document.createElement("style");
style.textContent = `
  @keyframes joyconfFloat {
    0%   { transform: translateY(0);    opacity: 1; }
    100% { transform: translateY(-60px); opacity: 0; }
  }
`;
document.head.appendChild(style);

function getOrCreateOverlay() {
  let overlay = document.getElementById("joyconf-overlay");
  if (!overlay) {
    overlay = document.createElement("div");
    overlay.id = "joyconf-overlay";
    overlay.style.cssText = [
      "position: fixed",
      "bottom: 40px",
      "right: 20px",
      "width: 160px",
      "height: 200px",
      "pointer-events: none",
      "z-index: 999999",
      "overflow: hidden",
    ].join(";");
    document.body.appendChild(overlay);
  }
  return overlay;
}

// When the browser enters/exits fullscreen, the fullscreen element forms its own
// stacking context — elements appended to <body> won't appear on top of it.
// Re-parent the overlay into the fullscreen element so it remains visible.
document.addEventListener("fullscreenchange", () => {
  const overlay = document.getElementById("joyconf-overlay");
  if (!overlay) return;

  if (document.fullscreenElement) {
    document.fullscreenElement.appendChild(overlay);
  } else {
    document.body.appendChild(overlay);
  }
});

function spawnEmoji(emoji) {
  const overlay = getOrCreateOverlay();
  const el = document.createElement("span");
  el.textContent = emoji;
  el.style.cssText = [
    "position: absolute",
    "bottom: 0",
    `left: ${Math.floor(Math.random() * 70)}%`,
    "font-size: 28px",
    "animation: joyconfFloat 2.5s ease-out forwards",
    "pointer-events: none",
  ].join(";");
  overlay.appendChild(el);
  el.addEventListener("animationend", () => el.remove());
}

function connect(slug) {
  if (socket) {
    socket.disconnect();
    socket = null;
    channel = null;
    stopSlideObserver();
  }

  socket = new Socket(`${HOST}/socket`, {
    logger: (kind, msg, data) => console.debug(`[JoyConf] ${kind}: ${msg}`, data)
  });
  socket.onError(() => console.error("[JoyConf] Socket error — check HOST and that the server is running"));
  socket.connect();

  channel = socket.channel(`reactions:${slug}`, {});
  channel.on("new_reaction", ({ emoji }) => spawnEmoji(emoji));
  channel
    .join()
    .receive("ok", () => {
      console.log(`[JoyConf] Joined reactions:${slug}`);
      startSlideObserver();
    })
    .receive("error", ({ reason }) => {
      console.error(`[JoyConf] Channel join failed: ${reason}`);
      socket.disconnect();
      socket = null;
    });

  getOrCreateOverlay();
  return true;
}

function isConnected() {
  return socket !== null && socket.isConnected();
}

function startSlideObserver() {
  const registry = window.JoyconfAdapterRegistry;
  if (!registry) return;

  const adapter = registry.getAdapter(window.location.href);

  slideObserver = new MutationObserver(() => {
    const slide = adapter.getSlide();
    if (slide !== currentSlide) {
      currentSlide = slide;
      if (channel) {
        channel.push("slide_changed", { slide: currentSlide });
      }
    }
  });

  slideObserver.observe(document.body, {
    childList: true,
    subtree: true,
    attributes: true,
    attributeFilter: ["value", "aria-label"],
  });
}

function stopSlideObserver() {
  if (slideObserver) {
    slideObserver.disconnect();
    slideObserver = null;
  }
  currentSlide = 0;
}

chrome.runtime.onMessage.addListener((msg, _sender, sendResponse) => {
  if (msg.type === "SET_SLUG") {
    const connected = connect(msg.slug);
    sendResponse({ connected });
  } else if (msg.type === "GET_STATUS") {
    sendResponse({ connected: isConnected() });
  } else if (msg.type === "START_SESSION") {
    if (!channel) {
      sendResponse({ error: "not_connected" });
      return;
    }
    channel
      .push("start_session", {})
      .receive("ok", ({ session_id, label }) => sendResponse({ session_id, label }))
      .receive("error", ({ reason }) => sendResponse({ error: reason }));
    return true; // keep the message channel open for the async reply
  } else if (msg.type === "STOP_SESSION") {
    if (!channel) {
      sendResponse({ error: "not_connected" });
      return;
    }
    channel
      .push("stop_session", { session_id: msg.sessionId })
      .receive("ok", () => sendResponse({ stopped: true }))
      .receive("error", ({ reason }) => sendResponse({ error: reason }));
    return true; // keep the message channel open for the async reply
  }
});

// Auto-connect on page load if slug is saved
chrome.storage.local.get("slug", ({ slug }) => {
  if (slug) connect(slug);
});
