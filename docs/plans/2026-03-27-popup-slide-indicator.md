# Popup Slide Indicator Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The extension popup displays the current slide number ("Slide 3" or "—") in real time so the speaker can immediately verify the adapter is reading the DOM correctly.

**Architecture:** The content script already tracks `currentSlide`. Two small changes close the gap: (1) `GET_STATUS` includes `currentSlide` so the popup shows the right value on open; (2) when the slide changes, the content script sends a `SLIDE_CHANGED` message to the extension so the popup updates in real time while it's open. The popup renders a `#slide-indicator` element and updates it from both sources.

**Tech Stack:** JavaScript (Chrome Manifest V3), Chrome extension message-passing (`chrome.runtime.sendMessage` / `chrome.runtime.onMessage`)

> **Note on testing:** `content.js` and `popup.js` rely on Chrome extension APIs (`chrome.runtime`, `chrome.tabs`) that require a full Chrome mock framework to unit test. The existing Jest suite covers the adapter DOM-scraping logic. Message-passing changes are verified manually (see manual verification steps in each task).

---

## File Map

**Modify:**
- `extension/content/content.js` — add `slide: currentSlide` to `GET_STATUS` response; notify popup on slide change
- `extension/popup/popup.html` — add `#slide-indicator` element
- `extension/popup/popup.js` — read slide from `GET_STATUS` response; listen for `SLIDE_CHANGED`

---

## Task 1: content.js — expose slide state to popup

**Files:**
- Modify: `extension/content/content.js`

- [ ] **Step 1: Update `GET_STATUS` handler to include `currentSlide`**

Find this block (around line 144):

```javascript
  } else if (msg.type === "GET_STATUS") {
    sendResponse({ connected: isConnected() });
  }
```

Replace with:

```javascript
  } else if (msg.type === "GET_STATUS") {
    sendResponse({ connected: isConnected(), slide: currentSlide });
  }
```

- [ ] **Step 2: Notify popup when slide changes**

In `startSlideObserver`, find this block (around line 114):

```javascript
  slideObserver = new MutationObserver(() => {
    const slide = adapter.getSlide();
    if (slide !== currentSlide) {
      currentSlide = slide;
      if (channel) {
        channel.push("slide_changed", { slide: currentSlide });
      }
    }
  });
```

Replace with:

```javascript
  slideObserver = new MutationObserver(() => {
    const slide = adapter.getSlide();
    if (slide !== currentSlide) {
      currentSlide = slide;
      if (channel) {
        channel.push("slide_changed", { slide: currentSlide });
      }
      chrome.runtime.sendMessage({ type: "SLIDE_CHANGED", slide: currentSlide }, () => {
        void chrome.runtime.lastError; // suppress "no listener" error when popup is closed
      });
    }
  });
```

- [ ] **Step 3: Manual verification**

1. Load the extension in Chrome (`chrome://extensions` → Load unpacked → `extension/`)
2. Open Google Slides and connect to a talk slug
3. Open the popup — it should show "—" (slide 0, not yet detected)
4. Advance to slide 3 in the presentation — the popup should update to "Slide 3" within ~1 second
5. Open a new popup window — it should immediately show "Slide 3" (from `GET_STATUS`)

- [ ] **Step 4: Commit**

```bash
git add extension/content/content.js
git commit -m "feat: expose current slide in GET_STATUS and notify popup on slide change"
```

---

## Task 2: popup.html + popup.js — slide indicator display

**Files:**
- Modify: `extension/popup/popup.html`
- Modify: `extension/popup/popup.js`

- [ ] **Step 1: Add `#slide-indicator` to `popup.html`**

Find this block:

```html
  <div id="session-section">
    <div id="session-status">No active session</div>
    <button id="session-btn">Start Session</button>
  </div>
```

Replace with:

```html
  <div id="session-section">
    <div id="slide-indicator" style="font-size: 12px; color: #5f6368; margin-bottom: 8px;">Slide —</div>
    <div id="session-status">No active session</div>
    <button id="session-btn">Start Session</button>
  </div>
```

- [ ] **Step 2: Add `setSlideIndicator` function and wire it up in `popup.js`**

Add the DOM reference at the top of `popup.js`, after the existing `const` declarations:

```javascript
const slideIndicator = document.getElementById("slide-indicator");
```

Add a `setSlideIndicator` function after the `setSessionUI` function:

```javascript
function setSlideIndicator(slide) {
  slideIndicator.textContent = slide > 0 ? `Slide ${slide}` : "Slide —";
}
```

- [ ] **Step 3: Read slide from `GET_STATUS` response on popup open**

Find the existing `GET_STATUS` call at the bottom of `popup.js`:

```javascript
// Check current status on popup open
chrome.tabs.query({ active: true, currentWindow: true }, ([tab]) => {
  chrome.tabs.sendMessage(tab.id, { type: "GET_STATUS" }, (response) => {
    setStatus(response?.connected ?? false);
  });
});
```

Replace with:

```javascript
// Check current status on popup open
chrome.tabs.query({ active: true, currentWindow: true }, ([tab]) => {
  chrome.tabs.sendMessage(tab.id, { type: "GET_STATUS" }, (response) => {
    setStatus(response?.connected ?? false);
    setSlideIndicator(response?.slide ?? 0);
  });
});
```

- [ ] **Step 4: Listen for `SLIDE_CHANGED` messages while popup is open**

Append to `popup.js` (after all existing code):

```javascript
chrome.runtime.onMessage.addListener((msg) => {
  if (msg.type === "SLIDE_CHANGED") {
    setSlideIndicator(msg.slide);
  }
});
```

- [ ] **Step 5: Manual verification**

1. Reload the extension in `chrome://extensions`
2. Open the extension popup while on a non-Google-Slides tab — session section should be hidden (works as before)
3. Navigate to Google Slides and connect to a talk slug — popup should show "Slide —"
4. Advance to slide 5 in the presentation — popup should update to "Slide 5" within ~1 second without reopening
5. Close and reopen the popup — should still show "Slide 5"
6. Advance to slide 6 — popup updates to "Slide 6"

- [ ] **Step 6: Commit**

```bash
git add extension/popup/popup.html extension/popup/popup.js
git commit -m "feat: show current slide number in extension popup"
```

---

## Task 3: Update docs

**Files:**
- Modify: `README.md`
- Modify: `docs/explainer.md`

- [ ] **Step 1: Update README end-to-end flow**

In the end-to-end test flow section, update step 7 to mention the slide indicator:

> (Optional) Load the Chrome extension pointed at `my-talk` and open a Google Slides presentation. Open the extension popup — it shows the current slide number ("Slide 3") in real time, confirming the adapter is reading the DOM correctly.

- [ ] **Step 2: Update explainer slide tracking section**

In the "Slide tracking" → "MutationObserver" section, note that the popup displays the current slide:

> The popup also displays the current slide number in real time ("Slide 3" or "—" for unknown). This serves as an immediate sanity check that the adapter is reading the DOM correctly — if the number doesn't update when you advance slides, the DOM structure has changed and the adapter selector needs updating.

- [ ] **Step 3: Run precommit and commit**

```bash
mix precommit
git add README.md docs/explainer.md
git commit -m "docs: document popup slide indicator and its verification purpose"
```
