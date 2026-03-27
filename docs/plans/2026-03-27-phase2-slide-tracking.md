# Phase 2: Slide Number Tracking

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The extension detects the current slide number and sends it to the server when the slide changes. The server tags each incoming reaction with the current slide number. An adapter registry pattern keeps the Google Slides integration isolated so other presentation tools can be supported later with minimal changes.

**Architecture:** A small adapter registry in the extension maps URL patterns to `getSlide()` functions. The content script uses a `MutationObserver` to detect slide changes and pushes a `slide_changed` channel event. The server broadcasts slide changes over a `"slides:{slug}"` PubSub topic; `TalkLive` subscribes and stores `current_slide` in its socket assigns, which is stamped onto each persisted reaction. Slide `0` is the fallback for unknown/unsupported platforms.

**Tech Stack:** Elixir/Phoenix, ExUnit, Phoenix.ChannelTest, Phoenix.LiveViewTest, Jest, jsdom (extension unit tests)

**Prerequisite:** Phase 1 must be complete and merged before starting this branch. Specifically, Phase 1's `create_reactions` migration must include the `slide_number :integer, default: 0, null: false` column — verify this exists before starting Task 6, or `Reactions.create_reaction/3` will fail at runtime.

---

## File Map

**Create:**
- `extension/adapters/google_slides.js` — Google Slides DOM adapter
- `extension/adapters/index.js` — adapter registry
- `extension/__tests__/google_slides_adapter.test.js` — Jest adapter tests
- `extension/__tests__/fixtures/google_slides_dom.html` — DOM snapshot fixture
- `extension/package.json` — Jest dev dependency
- `extension/jest.config.js` — Jest configuration

**Modify:**
- `extension/content/content.js` — integrate adapter, observe slide changes, push `slide_changed`
- `lib/joyconf_web/channels/reaction_channel.ex` — handle `slide_changed`, broadcast to PubSub
- `lib/joyconf_web/live/talk_live.ex` — subscribe to `"slides:{slug}"`, track `current_slide`, stamp reactions
- `test/joyconf_web/channels/reaction_channel_test.exs` — `slide_changed` channel test
- `test/joyconf_web/live/talk_live_test.exs` — reaction stamped with slide number

---

## Task 1: Jest Setup for Extension Testing

**Files:**
- Create: `extension/package.json`
- Create: `extension/jest.config.js`

- [ ] **Step 1: Create `extension/package.json`**

```json
{
  "name": "joyconf-extension",
  "private": true,
  "scripts": {
    "test": "jest"
  },
  "devDependencies": {
    "jest": "^29.0.0",
    "jest-environment-jsdom": "^29.0.0"
  }
}
```

- [ ] **Step 2: Create `extension/jest.config.js`**

```js
module.exports = {
  testEnvironment: "jsdom",
  testMatch: ["**/__tests__/**/*.test.js"],
};
```

- [ ] **Step 3: Install dependencies**

```bash
cd extension && npm install
```

Expected: `node_modules/` created, no errors.

- [ ] **Step 4: Verify Jest runs (no tests yet)**

```bash
npm test
```

Expected: `No tests found, exiting with code 1` or `Test Suites: 0 of 0 total`. Either is fine — Jest is configured.

- [ ] **Step 5: Add `extension/node_modules` to `.gitignore`**

Add to the project root `.gitignore`:

```
extension/node_modules/
```

- [ ] **Step 6: Commit**

```bash
cd .. # back to project root
git add extension/package.json extension/jest.config.js .gitignore
git commit -m "chore: add Jest for extension unit tests"
```

---

## Task 2: Google Slides DOM Fixture

**Files:**
- Create: `extension/__tests__/fixtures/google_slides_dom.html`

The fixture is a minimal snapshot of the Google Slides DOM fragment that contains the slide indicator. This is what the adapter will scrape. Capture it from a live Google Slides tab.

- [ ] **Step 1: Capture the current Google Slides slide indicator DOM**

Open any Google Slides presentation in Chrome. In DevTools console, run:

```js
// Find the element that displays the current slide number.
document.querySelector('input[aria-label*="Slide"]')?.outerHTML
// or
document.querySelector('[data-slide-number]')?.outerHTML
```

Note the actual selector and element structure you find. The slide indicator is typically near the bottom toolbar and looks like: `<input class="punch-icon-toolbar-input" aria-label="Slide 3 of 12" value="3">`.

> **Critical: verify how Google Slides updates the indicator.** MutationObserver only fires for DOM *attribute* changes — not JavaScript property assignments. Google Slides likely updates `aria-label` via `setAttribute("aria-label", "Slide 4 of 12")`, which the observer will catch. However, it may update the `value` *property* directly (`input.value = "4"`) rather than the attribute, which would NOT trigger the observer. To verify, navigate between slides in DevTools with the Elements panel open and watch whether the `aria-label` attribute updates. If only `value` changes and `aria-label` does not, use a DOM `"input"` or `"change"` event listener instead of MutationObserver for the trigger.

- [ ] **Step 2: Create the fixture file**

Create `extension/__tests__/fixtures/google_slides_dom.html` with a minimal HTML fragment around the slide indicator. Based on typical Google Slides structure (update if your captured HTML differs):

```html
<!-- Minimal Google Slides slide indicator fixture -->
<!-- Captured from: https://docs.google.com/presentation (March 2026) -->
<!-- Update this file and the adapter selector if Google changes their DOM -->
<div class="goog-toolbar" role="toolbar">
  <div class="punch-icon-toolbar-input-container">
    <input
      class="punch-icon-toolbar-input"
      type="text"
      aria-label="Slide 3 of 12"
      value="3"
    />
  </div>
</div>
```

If the real DOM differs from the above, use the actual captured HTML. The fixture file is the source of truth for what the adapter must handle.

- [ ] **Step 3: Commit the fixture**

```bash
git add extension/__tests__/fixtures/google_slides_dom.html
git commit -m "test: add Google Slides DOM fixture for adapter tests"
```

---

## Task 3: Google Slides Adapter

**Files:**
- Create: `extension/adapters/google_slides.js`
- Create: `extension/__tests__/google_slides_adapter.test.js`

- [ ] **Step 1: Write the failing adapter tests**

Create `extension/__tests__/google_slides_adapter.test.js`:

```js
const fs = require("fs");
const path = require("path");
const { getSlide } = require("../adapters/google_slides");

function loadFixture(name) {
  const fixturePath = path.join(__dirname, "fixtures", name);
  return fs.readFileSync(fixturePath, "utf-8");
}

describe("Google Slides adapter", () => {
  beforeEach(() => {
    document.body.innerHTML = loadFixture("google_slides_dom.html");
  });

  afterEach(() => {
    document.body.innerHTML = "";
  });

  test("returns the current slide number from the toolbar input", () => {
    expect(getSlide()).toBe(3);
  });

  test("returns 0 when the slide indicator element is absent", () => {
    document.body.innerHTML = "<div>no slides here</div>";
    expect(getSlide()).toBe(0);
  });

  test("returns 0 when the value is not a valid number", () => {
    const input = document.querySelector('input[aria-label*="Slide"]');
    input.value = "abc";
    expect(getSlide()).toBe(0);
  });
});
```

- [ ] **Step 2: Run tests — confirm they fail**

```bash
cd extension && npm test
```

Expected: error — `Cannot find module '../adapters/google_slides'`.

- [ ] **Step 3: Create `extension/adapters/google_slides.js`**

Use the selector that matches your captured fixture. The default below targets the `aria-label` input pattern:

```js
/**
 * Google Slides adapter.
 *
 * Reads the current slide number from the slide-indicator toolbar input.
 * Returns 0 if the element is absent or the value cannot be parsed — this
 * is the "unknown slide" sentinel used by the server (reactions go to slide 0).
 *
 * BRITTLE: depends on Google Slides DOM structure. When this test starts
 * failing, update the selector here and the fixture in
 * __tests__/fixtures/google_slides_dom.html to match the new structure.
 */
function getSlide() {
  const input = document.querySelector('input[aria-label*="Slide"]');
  if (!input) return 0;

  const n = parseInt(input.value, 10);
  return Number.isFinite(n) && n > 0 ? n : 0;
}

module.exports = { getSlide };
```

- [ ] **Step 4: Run tests — confirm they pass**

```bash
npm test
```

Expected: 3 tests, 0 failures.

- [ ] **Step 5: Commit**

```bash
cd ..
git add extension/adapters/google_slides.js \
        extension/__tests__/google_slides_adapter.test.js
git commit -m "feat: add Google Slides DOM adapter with tests"
```

---

## Task 4: Adapter Registry

**Files:**
- Create: `extension/adapters/index.js`

The registry maps URL patterns to adapters. The content script calls `getAdapter(url)` at connect time. If no adapter matches, `getSlide()` returns `0` (the fallback bucket).

- [ ] **Step 1: Create `extension/adapters/index.js`**

```js
const googleSlides = require("./google_slides");

const ADAPTERS = [
  {
    match: /docs\.google\.com\/presentation/,
    getSlide: googleSlides.getSlide,
  },
];

/**
 * Returns the adapter for the given URL, or a no-op adapter that always
 * returns slide 0 for unknown/unsupported presentation tools.
 */
function getAdapter(url) {
  const adapter = ADAPTERS.find((a) => a.match.test(url));
  return adapter || { getSlide: () => 0 };
}

module.exports = { getAdapter };
```

- [ ] **Step 2: Write registry tests**

Create `extension/__tests__/adapter_registry.test.js`:

```js
const { getAdapter } = require("../adapters/index");

describe("adapter registry", () => {
  test("returns Google Slides adapter for Google Slides URLs", () => {
    const adapter = getAdapter(
      "https://docs.google.com/presentation/d/abc123/edit"
    );
    expect(typeof adapter.getSlide).toBe("function");
  });

  test("returns fallback adapter for unknown URLs", () => {
    const adapter = getAdapter("https://example.com/my-slides");
    expect(adapter.getSlide()).toBe(0);
  });

  test("fallback adapter always returns 0", () => {
    const adapter = getAdapter("https://slides.com/user/deck");
    expect(adapter.getSlide()).toBe(0);
  });
});
```

- [ ] **Step 3: Run tests — confirm they pass**

```bash
cd extension && npm test
```

Expected: all 6 tests pass (3 adapter + 3 registry).

- [ ] **Step 4: Commit**

```bash
cd ..
git add extension/adapters/index.js extension/__tests__/adapter_registry.test.js
git commit -m "feat: add adapter registry for presentation platform detection"
```

---

## Task 5: Wire Adapters into `content.js`

**Files:**
- Modify: `extension/content/content.js`

The content script needs to:
1. Select the adapter for the current page URL at connect time.
2. Set up a `MutationObserver` that fires `slide_changed` via the channel when the slide indicator changes.
3. Tear down the observer on disconnect.

Note: `content.js` runs in a browser extension context and cannot use `require()`. The adapter module is loaded as a separate content script injected before `content.js`. The registry is exposed on `window` so `content.js` can call it. Update `manifest.json` to inject the adapter files.

- [ ] **Step 1: Update `extension/manifest.json` to inject adapters**

Open `extension/manifest.json`. In the `content_scripts[0].js` array, add the adapter files **before** `content/content.js`:

```json
"js": [
  "lib/phoenix.js",
  "adapters/google_slides.js",
  "adapters/index.js",
  "content/content.js"
]
```

Also update `adapters/google_slides.js` and `adapters/index.js` to expose themselves on `window` instead of using `module.exports` (browser extensions don't have CommonJS). The Jest tests use `require()`, so we need both export styles.

- [ ] **Step 2: Update `extension/adapters/google_slides.js` for dual export**

Replace the last line `module.exports = { getSlide };` with:

```js
if (typeof module !== "undefined" && module.exports) {
  module.exports = { getSlide };
} else {
  window.JoyconfGoogleSlidesAdapter = { getSlide };
}
```

- [ ] **Step 3: Update `extension/adapters/index.js` for dual export**

Replace the contents of `extension/adapters/index.js`:

```js
// In the browser, adapter files are injected before this file (see manifest.json),
// so window.JoyconfGoogleSlidesAdapter is available. In Jest (jsdom), window exists
// but window.JoyconfGoogleSlidesAdapter is never set — the ternary falls through to
// require(), which is the intended test path. Do not reorder manifest.json injection
// without updating this logic.
const ADAPTERS = [
  {
    match: /docs\.google\.com\/presentation/,
    getSlide: (typeof window !== "undefined" && window.JoyconfGoogleSlidesAdapter)
      ? window.JoyconfGoogleSlidesAdapter.getSlide
      : (typeof require !== "undefined" ? require("./google_slides").getSlide : () => 0),
  },
];

function getAdapter(url) {
  const adapter = ADAPTERS.find((a) => a.match.test(url));
  return adapter || { getSlide: () => 0 };
}

if (typeof module !== "undefined" && module.exports) {
  module.exports = { getAdapter };
} else {
  window.JoyconfAdapterRegistry = { getAdapter };
}
```

- [ ] **Step 4: Re-run Jest to confirm adapter tests still pass**

```bash
cd extension && npm test
```

Expected: all tests still pass.

- [ ] **Step 5: Update `extension/content/content.js` to observe slide changes**

Add the following after the `let channel = null;` declaration (around line 8), and update the `connect` and `disconnect` logic:

Add these new variables after `let channel = null;`:

```js
let slideObserver = null;
let currentSlide = 0;
```

Add this new function after `isConnected()`:

```js
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
```

Update the `connect` function to call `startSlideObserver()` after joining the channel successfully, and `stopSlideObserver()` on disconnect:

```js
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
```

- [ ] **Step 6: Commit**

```bash
cd ..
git add extension/manifest.json \
        extension/adapters/google_slides.js \
        extension/adapters/index.js \
        extension/content/content.js
git commit -m "feat: integrate slide adapter and MutationObserver into content script"
```

---

## Task 6: `ReactionChannel` — Handle `slide_changed`

**Files:**
- Modify: `lib/joyconf_web/channels/reaction_channel.ex`
- Modify: `test/joyconf_web/channels/reaction_channel_test.exs`

The channel receives `slide_changed` from the extension and broadcasts to the `"slides:{slug}"` PubSub topic so `TalkLive` processes can update their `current_slide` assign.

- [ ] **Step 1: Add `slide_changed` channel test**

Append to `test/joyconf_web/channels/reaction_channel_test.exs`:

```elixir
  describe "slide_changed" do
    setup %{socket: socket, talk: talk} do
      Phoenix.PubSub.subscribe(Joyconf.PubSub, "slides:#{talk.slug}")
      {:ok, _, joined} = subscribe_and_join(socket, "reactions:#{talk.slug}", %{})
      %{joined: joined, talk: talk}
    end

    test "broadcasts slide number to the slides PubSub topic", %{joined: joined, talk: talk} do
      ref = push(joined, "slide_changed", %{"slide" => 5})
      assert_reply ref, :ok
      assert_receive %Phoenix.Socket.Broadcast{
        topic: "slides:" <> _slug,
        event: "slide_changed",
        payload: %{slide: 5}
      }, 500
    end

    test "does not broadcast for slide 0 (unknown slide sentinel)", %{joined: joined} do
      ref = push(joined, "slide_changed", %{"slide" => 0})
      assert_reply ref, :ok
      refute_receive %Phoenix.Socket.Broadcast{event: "slide_changed"}, 200
    end
  end
```

- [ ] **Step 2: Run tests — confirm they fail**

```bash
mix test test/joyconf_web/channels/reaction_channel_test.exs
```

Expected: failures — `slide_changed` handle_in not defined.

- [ ] **Step 3: Add `handle_in("slide_changed", ...)` to `lib/joyconf_web/channels/reaction_channel.ex`**

```elixir
  def handle_in("slide_changed", %{"slide" => slide}, socket) when is_integer(slide) and slide > 0 do
    JoyconfWeb.Endpoint.broadcast!(
      "slides:#{socket.assigns.talk.slug}",
      "slide_changed",
      %{slide: slide}
    )

    {:reply, :ok, socket}
  end

  def handle_in("slide_changed", _payload, socket) do
    {:reply, :ok, socket}
  end
```

- [ ] **Step 4: Run tests — confirm they pass**

```bash
mix test test/joyconf_web/channels/reaction_channel_test.exs
```

Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/joyconf_web/channels/reaction_channel.ex \
        test/joyconf_web/channels/reaction_channel_test.exs
git commit -m "feat: add slide_changed broadcast to ReactionChannel"
```

---

## Task 7: `TalkLive` — Subscribe to Slide Changes, Stamp Reactions

**Files:**
- Modify: `lib/joyconf_web/live/talk_live.ex`
- Modify: `test/joyconf_web/live/talk_live_test.exs`

- [ ] **Step 1: Add slide stamping tests**

Append to `test/joyconf_web/live/talk_live_test.exs`:

```elixir
  describe "slide-stamped reaction persistence" do
    test "stamps reaction with current_slide when slide has been set", %{conn: conn, talk: talk} do
      {:ok, session} = Joyconf.Talks.start_session(talk)
      {:ok, view, _html} = live(conn, "/t/#{talk.slug}")

      # Simulate the extension broadcasting a slide change
      JoyconfWeb.Endpoint.broadcast!(
        "slides:#{talk.slug}",
        "slide_changed",
        %{slide: 7}
      )

      # Give the LiveView process a moment to handle the broadcast
      _ = :sys.get_state(view.pid)

      render_click(view, "react", %{"emoji" => "❤️"})

      reaction = Joyconf.Repo.one(
        from r in Joyconf.Reactions.Reaction,
          where: r.talk_session_id == ^session.id
      )
      assert reaction.slide_number == 7
    end

    test "stamps reaction with slide 0 when no slide has been set", %{conn: conn, talk: talk} do
      {:ok, session} = Joyconf.Talks.start_session(talk)
      {:ok, view, _html} = live(conn, "/t/#{talk.slug}")

      render_click(view, "react", %{"emoji" => "❤️"})

      reaction = Joyconf.Repo.one(
        from r in Joyconf.Reactions.Reaction,
          where: r.talk_session_id == ^session.id
      )
      assert reaction.slide_number == 0
    end
  end
```

- [ ] **Step 2: Run tests — confirm they fail**

```bash
mix test test/joyconf_web/live/talk_live_test.exs
```

Expected: failures — `current_slide` not tracked, reactions still stamped with default 0 regardless of slide broadcasts.

- [ ] **Step 3: Update `lib/joyconf_web/live/talk_live.ex`**

```elixir
defmodule JoyconfWeb.TalkLive do
  use JoyconfWeb, :live_view

  alias Joyconf.{Talks, RateLimiter, Reactions}

  @emojis ["❤️", "😂", "👏", "🤯", "🙋🏻", "🎉", "💩", "😮", "🎯"]

  def mount(%{"slug" => slug}, _session, socket) do
    case Talks.get_talk_by_slug(slug) do
      nil ->
        {:ok, redirect(socket, to: "/")}

      talk ->
        if connected?(socket) do
          Phoenix.PubSub.subscribe(Joyconf.PubSub, "reactions:#{slug}")
          Phoenix.PubSub.subscribe(Joyconf.PubSub, "slides:#{slug}")
        end

        {:ok, assign(socket, talk: talk, emojis: @emojis, session_id: socket.id, current_slide: 0)}
    end
  end

  def handle_event("react", %{"emoji" => emoji}, socket) do
    if RateLimiter.allow?(socket.assigns.session_id) do
      case Talks.get_active_session(socket.assigns.talk.id) do
        nil -> :ok
        session -> Reactions.create_reaction(session, emoji, socket.assigns.current_slide)
      end

      JoyconfWeb.Endpoint.broadcast!(
        "reactions:#{socket.assigns.talk.slug}",
        "new_reaction",
        %{emoji: emoji}
      )
    end

    {:noreply, socket}
  end

  def handle_info(
        %Phoenix.Socket.Broadcast{event: "new_reaction", payload: %{emoji: emoji}},
        socket
      ) do
    {:noreply, push_event(socket, "new_reaction", %{emoji: emoji})}
  end

  def handle_info(
        %Phoenix.Socket.Broadcast{event: "slide_changed", payload: %{slide: slide}},
        socket
      ) do
    {:noreply, assign(socket, :current_slide, slide)}
  end
end
```

- [ ] **Step 4: Run tests — confirm they pass**

```bash
mix test test/joyconf_web/live/talk_live_test.exs
```

Expected: all tests pass.

- [ ] **Step 5: Run full test suite**

```bash
mix test
```

Expected: all tests pass.

- [ ] **Step 6: Run precommit checks**

```bash
mix precommit
```

Expected: all checks pass.

- [ ] **Step 7: Commit**

```bash
git add lib/joyconf_web/live/talk_live.ex test/joyconf_web/live/talk_live_test.exs
git commit -m "feat: subscribe to slide changes and stamp reactions with current slide"
```

---

## Phase 2 Complete

Reactions are now tagged with the slide number on which they were received. Google Slides is fully supported. Any unknown presentation tool falls back to slide `0`. Adding support for a new platform means adding one entry to `extension/adapters/index.js` and a new adapter file — the Jest fixture strategy keeps each adapter testable without a live browser.

When Google Slides changes their DOM (and they will), the `google_slides_adapter.test.js` test will fail loudly. The fix is to:

1. Capture the new DOM structure from a live Slides tab.
2. Update `extension/__tests__/fixtures/google_slides_dom.html`.
3. Update the selector in `extension/adapters/google_slides.js`.
4. Re-run `npm test` until green.
