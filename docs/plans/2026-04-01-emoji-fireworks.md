# Emoji Fireworks Animation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Trigger a radial burst fireworks animation in the extension overlay when a single emoji type dominates the in-flight reactions, with a presenter-controlled on/off toggle and a DEV_MODE test button.

**Architecture:** The trigger condition is a pure function extracted to `extension/lib/fireworks.js` (testable with Jest, exposed as `window.SpeechwaveFireworks` at runtime). In-flight counts are tracked per emoji type in `content.js`; the total is derived on demand. The fireworks spawner uses the Web Animations API to avoid per-element CSS custom property issues. The popup toggle writes to `chrome.storage.sync`; `content.js` reads it on init and responds to live `SET_FIREWORKS` messages.

**Tech Stack:** Vanilla JS (Chrome Extension MV3), Web Animations API, `chrome.storage.sync`, Jest (jsdom), existing Phoenix channel infrastructure.

---

## File Map

| Action | File | Responsibility |
|--------|------|----------------|
| Create | `extension/lib/fireworks.js` | Pure trigger logic — testable, exposed as `window.SpeechwaveFireworks` |
| Create | `extension/tests/fireworks.test.js` | Jest unit tests for trigger logic |
| Modify | `extension/manifest.json` | Add `lib/fireworks.js` to content script load order |
| Modify | `extension/content/content.js` | In-flight tracking, fireworks spawner, storage init, new message handlers |
| Modify | `extension/popup/popup.html` | Fireworks toggle + DEV_MODE test button |
| Modify | `extension/popup/popup.js` | Toggle handler, storage read/write, DEV_MODE test button handler |

---

## Task 1: Trigger logic module

**Files:**
- Create: `extension/lib/fireworks.js`
- Create: `extension/tests/fireworks.test.js`
- Modify: `extension/manifest.json`

- [ ] **Step 1: Write the failing tests**

Create `extension/tests/fireworks.test.js`:

```js
const { checkFireworksTrigger } = require("../lib/fireworks");

const opts = { minCount: 5, minPercent: 0.4 };

describe("checkFireworksTrigger", () => {
  test("returns true when count and percent both exceed thresholds", () => {
    // count=6, total=8, percent=0.75 — both pass
    expect(checkFireworksTrigger({ "❤️": 6, "👍": 2 }, "❤️", opts)).toBe(true);
  });

  test("returns false when count is below minCount", () => {
    // count=4, total=5, percent=0.8 — count fails
    expect(checkFireworksTrigger({ "❤️": 4, "👍": 1 }, "❤️", opts)).toBe(false);
  });

  test("returns false when percent is below minPercent", () => {
    // count=6, total=26, percent=0.23 — percent fails
    expect(checkFireworksTrigger({ "❤️": 6, "👍": 20 }, "❤️", opts)).toBe(false);
  });

  test("returns false when emoji is not in flight", () => {
    expect(checkFireworksTrigger({ "👍": 10 }, "❤️", opts)).toBe(false);
  });

  test("returns false when inFlight is empty", () => {
    expect(checkFireworksTrigger({}, "❤️", opts)).toBe(false);
  });

  test("percent is relative to all in-flight emoji types combined", () => {
    // count=5, total=15, percent=0.33 — below 0.4 threshold
    expect(checkFireworksTrigger({ "❤️": 5, "👍": 5, "🔥": 5 }, "❤️", opts)).toBe(false);
  });

  test("returns true at exactly the thresholds", () => {
    // count=5, total=12, percent=0.41 — both pass at boundary
    expect(checkFireworksTrigger({ "❤️": 5, "👍": 7 }, "❤️", opts)).toBe(true);
  });
});
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd /Users/tracy/projects/speechwave/extension && npx jest tests/fireworks.test.js
```

Expected: all tests fail with `Cannot find module '../lib/fireworks'`.

- [ ] **Step 3: Create the module**

Create `extension/lib/fireworks.js`:

```js
function checkFireworksTrigger(inFlight, emoji, { minCount, minPercent }) {
  const count = inFlight[emoji] || 0;
  const total = Object.values(inFlight).reduce((a, b) => a + b, 0);
  const percent = total > 0 ? count / total : 0;
  return count >= minCount && percent >= minPercent;
}

if (typeof module !== "undefined") {
  module.exports = { checkFireworksTrigger };
} else {
  window.SpeechwaveFireworks = { checkFireworksTrigger };
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
cd /Users/tracy/projects/speechwave/extension && npx jest tests/fireworks.test.js
```

Expected: 7 tests pass.

- [ ] **Step 5: Add fireworks.js to the manifest content script load order**

In `extension/manifest.json`, add `"lib/fireworks.js"` before `"content/content.js"`:

```json
"js": ["lib/phoenix.js", "lib/fireworks.js", "adapters/google_slides.js", "adapters/index.js", "content/content.js"],
```

- [ ] **Step 6: Commit**

```bash
cd /Users/tracy/projects/speechwave && git add extension/lib/fireworks.js extension/tests/fireworks.test.js extension/manifest.json
git commit -m "feat: add fireworks trigger logic module with tests"
```

---

## Task 2: In-flight tracking in content.js

**Files:**
- Modify: `extension/content/content.js`

- [ ] **Step 1: Add state variables and constants after the existing module-level vars (after line 10)**

Add after `let currentSlide = 0;`:

```js
const FIREWORKS_MIN_COUNT = 5;
const FIREWORKS_MIN_PERCENT = 0.4;
const FIREWORKS_COOLDOWN_MS = 8000;
const FIREWORKS_BURST_COUNT = 16;

const inFlight = {};
let fireworksEnabled = true;
let fireworksActive = false;
let lastFireworksTime = 0;
```

- [ ] **Step 2: Replace the existing spawnEmoji function (lines 56–70) with a version that tracks in-flight counts**

```js
function spawnEmoji(emoji) {
  inFlight[emoji] = (inFlight[emoji] || 0) + 1;

  const overlay = getOrCreateOverlay();
  const el = document.createElement("span");
  el.textContent = emoji;
  el.style.cssText = [
    "position: absolute",
    "bottom: 0",
    `left: ${Math.floor(Math.random() * 70)}%`,
    "font-size: 28px",
    "animation: speechwaveFloat 2.5s ease-out forwards",
    "pointer-events: none",
  ].join(";");
  overlay.appendChild(el);
  el.addEventListener("animationend", () => {
    el.remove();
    inFlight[emoji] = Math.max(0, (inFlight[emoji] || 0) - 1);
    if (inFlight[emoji] === 0) delete inFlight[emoji];
  });

  maybeSpawnFireworks(emoji);
}
```

Note: `maybeSpawnFireworks` is defined in Task 3. The extension won't be loadable until Task 3 is complete — that's fine, keep moving.

- [ ] **Step 3: Commit**

```bash
cd /Users/tracy/projects/speechwave && git add extension/content/content.js
git commit -m "feat: track in-flight emoji counts in spawnEmoji"
```

---

## Task 3: Fireworks spawner

**Files:**
- Modify: `extension/content/content.js`

- [ ] **Step 1: Add `maybeSpawnFireworks` and `spawnFireworks` functions after `spawnEmoji`**

```js
function maybeSpawnFireworks(emoji) {
  if (!fireworksEnabled) return;
  if (fireworksActive) return;
  if (Date.now() - lastFireworksTime < FIREWORKS_COOLDOWN_MS) return;
  if (window.SpeechwaveFireworks.checkFireworksTrigger(inFlight, emoji, {
    minCount: FIREWORKS_MIN_COUNT,
    minPercent: FIREWORKS_MIN_PERCENT,
  })) {
    spawnFireworks(emoji);
  }
}

function spawnFireworks(emoji) {
  fireworksActive = true;
  lastFireworksTime = Date.now();

  const overlay = getOrCreateOverlay();
  const cx = overlay.offsetWidth / 2;
  const cy = overlay.offsetHeight / 2;
  let remaining = FIREWORKS_BURST_COUNT;

  for (let i = 0; i < FIREWORKS_BURST_COUNT; i++) {
    const angle = (i / FIREWORKS_BURST_COUNT) * 2 * Math.PI;
    const dist = 60 + Math.random() * 40;
    const tx = Math.round(Math.cos(angle) * dist);
    const ty = Math.round(Math.sin(angle) * dist);
    const delay = Math.random() * 300;

    const el = document.createElement("span");
    el.textContent = emoji;
    el.style.cssText = [
      "position: absolute",
      `left: ${cx}px`,
      `top: ${cy}px`,
      "font-size: 24px",
      "pointer-events: none",
    ].join(";");
    overlay.appendChild(el);

    const anim = el.animate(
      [
        { transform: "translate(0, 0) scale(1)", opacity: 1 },
        { transform: `translate(${tx}px, ${ty}px) scale(0.3)`, opacity: 0 },
      ],
      { duration: 1200, delay, easing: "ease-out", fill: "forwards" }
    );
    anim.addEventListener("finish", () => {
      el.remove();
      remaining--;
      if (remaining === 0) fireworksActive = false;
    });
  }
}
```

- [ ] **Step 2: Manually verify the animation fires**

Load the extension in Chrome (`chrome://extensions` → Load unpacked → select `extension/`). Open a Google Slides presentation. Open DevTools console on the Slides tab and run:

```js
spawnFireworks("❤️")
```

Expected: 16 ❤️ emojis burst outward from the center of the overlay in a radial pattern and fade out. `fireworksActive` returns to `false` after the last one finishes (~1.5s).

If the overlay is too small to see the burst clearly, temporarily change `FIREWORKS_BURST_COUNT` to `8` while tuning, then restore.

- [ ] **Step 3: Commit**

```bash
cd /Users/tracy/projects/speechwave && git add extension/content/content.js
git commit -m "feat: add fireworks spawner with radial burst animation"
```

---

## Task 4: Popup fireworks toggle

**Files:**
- Modify: `extension/popup/popup.html`
- Modify: `extension/popup/popup.js`
- Modify: `extension/content/content.js`

- [ ] **Step 1: Add the toggle section to popup.html**

Add after the closing `</div>` of `#session-section` (before the `<script>` tag):

```html
<div id="fireworks-section" style="margin-top: 12px; border-top: 1px solid #eee; padding-top: 12px;">
  <label style="display: flex; align-items: center; gap: 8px; cursor: pointer; margin-bottom: 0;">
    <input type="checkbox" id="fireworks-toggle" checked>
    <span style="font-size: 12px; font-weight: 600; color: #5f6368;">Fireworks animations</span>
  </label>
  <button id="test-fireworks-btn" style="display: none; margin-top: 8px; background: #f9ab00;">Test Fireworks</button>
</div>
```

- [ ] **Step 2: Add toggle wiring to popup.js**

Add at the top of `popup.js` with the other `getElementById` calls:

```js
const fireworksToggle = document.getElementById("fireworks-toggle");
const testFireworksBtn = document.getElementById("test-fireworks-btn");
```

Add after the existing `chrome.storage.local.get(...)` call at the top:

```js
chrome.storage.sync.get({ fireworksEnabled: true }, ({ fireworksEnabled }) => {
  fireworksToggle.checked = fireworksEnabled;
});

fireworksToggle.addEventListener("change", () => {
  const enabled = fireworksToggle.checked;
  chrome.storage.sync.set({ fireworksEnabled: enabled });
  chrome.tabs.query({ active: true, currentWindow: true }, ([tab]) => {
    chrome.tabs.sendMessage(tab.id, { type: "SET_FIREWORKS", enabled });
  });
});
```

- [ ] **Step 3: Read storage on init and handle SET_FIREWORKS in content.js**

At the bottom of `content.js`, alongside the existing `chrome.storage.local.get` call, add:

```js
chrome.storage.sync.get({ fireworksEnabled: true }, ({ fireworksEnabled: val }) => {
  fireworksEnabled = val;
});
```

In the `chrome.runtime.onMessage.addListener` callback, add a new branch before the closing `}`  of the listener:

```js
} else if (msg.type === "SET_FIREWORKS") {
  fireworksEnabled = msg.enabled;
  sendResponse({});
}
```

- [ ] **Step 4: Manually verify the toggle**

Reload the extension. Open a Slides presentation. Open the popup:
- Confirm the "Fireworks animations" checkbox is checked by default.
- Uncheck it. Open DevTools console and verify `fireworksEnabled` is `false`.
- Re-check it. Verify `fireworksEnabled` is `true`.
- Close and reopen the popup. Confirm the checkbox state persisted.

- [ ] **Step 5: Commit**

```bash
cd /Users/tracy/projects/speechwave && git add extension/popup/popup.html extension/popup/popup.js extension/content/content.js
git commit -m "feat: add fireworks toggle to popup with chrome.storage.sync persistence"
```

---

## Task 5: DEV_MODE test button

**Files:**
- Modify: `extension/popup/popup.js`
- Modify: `extension/content/content.js`

- [ ] **Step 1: Add DEV_MODE constant and test button handler to popup.js**

Add at the very top of `popup.js` (first line):

```js
const DEV_MODE = true; // set to false before shipping
```

Add after the `fireworksToggle.addEventListener` block:

```js
if (DEV_MODE) testFireworksBtn.style.display = "block";

testFireworksBtn.addEventListener("click", () => {
  chrome.tabs.query({ active: true, currentWindow: true }, ([tab]) => {
    chrome.tabs.sendMessage(tab.id, { type: "TEST_FIREWORKS" });
  });
});
```

- [ ] **Step 2: Handle TEST_FIREWORKS in content.js**

In the `chrome.runtime.onMessage.addListener` callback, add after the `SET_FIREWORKS` branch:

```js
} else if (msg.type === "TEST_FIREWORKS") {
  const testEmojis = ["❤️", "🔥", "👏", "🎉", "😂"];
  spawnFireworks(testEmojis[Math.floor(Math.random() * testEmojis.length)]);
  sendResponse({});
}
```

- [ ] **Step 3: Manually verify end-to-end**

Reload the extension. Open a Google Slides presentation (fullscreen and windowed):

1. Confirm the orange "Test Fireworks" button appears in the popup.
2. Click it. Verify a radial burst fires in the overlay with a random emoji.
3. Click it again immediately. Verify the second click is **blocked** by `fireworksActive` until the first burst finishes.
4. Enter fullscreen (`F11` or presentation mode). Click the test button from the popup. Verify the burst appears over the fullscreen slide.
5. Uncheck "Fireworks animations". Click the test button. Verify nothing fires (`fireworksEnabled` gates `maybeSpawnFireworks` but `TEST_FIREWORKS` bypasses it intentionally — the test button calls `spawnFireworks` directly so it works even when disabled, which is correct for testing).
6. Run all extension tests to confirm nothing is broken: `cd extension && npx jest`

- [ ] **Step 4: Commit**

```bash
cd /Users/tracy/projects/speechwave && git add extension/popup/popup.js extension/content/content.js
git commit -m "feat: add DEV_MODE test fireworks button to popup"
```

---

## Disabling DEV_MODE before shipping

When ready to ship, make a single change in `extension/popup/popup.js`:

```js
const DEV_MODE = false; // set to false before shipping
```

This hides the "Test Fireworks" button. No other code changes needed.
