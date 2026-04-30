# Phase 3: Public Pages Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the Phoenix placeholder home page with a landing page, add a pricing page, and add Terms of Service and Privacy Policy pages.

**Architecture:** All four pages use `PageController` with new actions and HEEx templates. The landing and pricing pages are world-class marketing pages styled with Tailwind CSS. The ToS and Privacy pages render template content with standard legal structure. Navigation header (logo, Pricing, Log in, Sign up) and footer (ToS, Privacy) are added to the landing page. Existing authenticated routes and the `TalkLive` route are unaffected.

**Tech Stack:** Phoenix 1.8, LiveView, Tailwind CSS v4, HEEx

---

## File Map

### Modified
| File | Change |
|---|---|
| `lib/speechwave_web/controllers/page_controller.ex` | Add `:pricing`, `:terms`, `:privacy` actions |
| `lib/speechwave_web/controllers/page_html.ex` | Register new template functions |
| `lib/speechwave_web/controllers/page_html/home.html.heex` | Replace Phoenix placeholder with landing page |
| `lib/speechwave_web/router.ex` | Add routes for `/pricing`, `/terms`, `/privacy` |
| `test/speechwave_web/controllers/page_controller_test.exs` | Add tests for new pages |

### Created
| File | Purpose |
|---|---|
| `lib/speechwave_web/controllers/page_html/pricing.html.heex` | Pricing page template |
| `lib/speechwave_web/controllers/page_html/terms.html.heex` | Terms of Service template |
| `lib/speechwave_web/controllers/page_html/privacy.html.heex` | Privacy Policy template |

---

## Task 1: Add routes and controller actions

**Files:**
- Modify: `lib/speechwave_web/router.ex`
- Modify: `lib/speechwave_web/controllers/page_controller.ex`
- Modify: `test/speechwave_web/controllers/page_controller_test.exs`

- [ ] **Step 1: Write failing tests**

Replace the contents of `test/speechwave_web/controllers/page_controller_test.exs`:

```elixir
defmodule SpeechwaveWeb.PageControllerTest do
  use SpeechwaveWeb.ConnCase

  test "GET / returns 200", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "Speechwave"
  end

  test "GET /pricing returns 200", %{conn: conn} do
    conn = get(conn, ~p"/pricing")
    assert html_response(conn, 200) =~ "Free"
  end

  test "GET /terms returns 200", %{conn: conn} do
    conn = get(conn, ~p"/terms")
    assert html_response(conn, 200) =~ "Terms"
  end

  test "GET /privacy returns 200", %{conn: conn} do
    conn = get(conn, ~p"/privacy")
    assert html_response(conn, 200) =~ "Privacy"
  end
end
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
mix test test/speechwave_web/controllers/page_controller_test.exs
```

Expected: `/pricing`, `/terms`, and `/privacy` return 404 — those routes don't exist yet.

- [ ] **Step 3: Add routes to `router.ex`**

In `lib/speechwave_web/router.ex`, inside the public scope (the one with `get "/", PageController, :home`), add:

```elixir
get "/pricing", PageController, :pricing
get "/terms", PageController, :terms
get "/privacy", PageController, :privacy
```

- [ ] **Step 4: Add controller actions to `page_controller.ex`**

In `lib/speechwave_web/controllers/page_controller.ex`, add after the existing `home/2` action:

```elixir
def pricing(conn, _params), do: render(conn, :pricing)
def terms(conn, _params), do: render(conn, :terms)
def privacy(conn, _params), do: render(conn, :privacy)
```

- [ ] **Step 5: Run tests to confirm they fail for the right reason**

```bash
mix test test/speechwave_web/controllers/page_controller_test.exs
```

Expected: Tests fail with a template-not-found error — the `.heex` files don't exist yet. That's expected.

- [ ] **Step 6: Commit the routes and actions**

```bash
git add lib/speechwave_web/router.ex \
        lib/speechwave_web/controllers/page_controller.ex \
        test/speechwave_web/controllers/page_controller_test.exs
git commit -m "feat: add /pricing, /terms, /privacy routes and controller actions"
```

---

## Task 2: Build the landing page

**Files:**
- Modify: `lib/speechwave_web/controllers/page_html/home.html.heex`

- [ ] **Step 1: Replace `home.html.heex` with the landing page**

Replace the entire contents of `lib/speechwave_web/controllers/page_html/home.html.heex`:

```heex
<%!-- Navigation --%>
<header class="fixed top-0 left-0 right-0 z-50 bg-white/80 backdrop-blur-md border-b border-gray-100">
  <div class="max-w-6xl mx-auto px-6 h-16 flex items-center justify-between">
    <a href="/" class="flex items-center gap-2 font-bold text-xl text-gray-900">
      <span class="text-2xl">🎤</span>
      Speechwave
    </a>
    <nav class="flex items-center gap-6">
      <a href={~p"/pricing"} class="text-sm text-gray-600 hover:text-gray-900 transition-colors">
        Pricing
      </a>
      <a href={~p"/users/log-in"} class="text-sm text-gray-600 hover:text-gray-900 transition-colors">
        Log in
      </a>
      <a
        href={~p"/users/register"}
        class="px-4 py-2 text-sm font-medium text-white bg-indigo-600 rounded-lg hover:bg-indigo-700 transition-colors"
      >
        Sign up free
      </a>
    </nav>
  </div>
</header>

<%!-- Hero --%>
<section class="pt-32 pb-24 px-6 bg-gradient-to-br from-white via-indigo-50/30 to-white">
  <div class="max-w-4xl mx-auto text-center">
    <div class="inline-flex items-center gap-2 px-3 py-1.5 rounded-full bg-indigo-100 text-indigo-700 text-xs font-medium mb-8">
      <span class="w-1.5 h-1.5 rounded-full bg-indigo-500"></span>
      Free to get started — no credit card required
    </div>
    <h1 class="text-5xl sm:text-6xl font-extrabold text-gray-900 tracking-tight leading-tight mb-6">
      Live emoji reactions
      <span class="text-indigo-600">for your next talk</span>
    </h1>
    <p class="text-xl text-gray-500 max-w-2xl mx-auto mb-10">
      Let your audience react in real time while you present.
      Install the browser extension, share a QR code, and watch the
      energy light up your slides.
    </p>
    <div class="flex flex-col sm:flex-row gap-4 justify-center">
      <a
        href={~p"/users/register"}
        class="px-8 py-4 text-base font-semibold text-white bg-indigo-600 rounded-xl hover:bg-indigo-700 transition-all hover:shadow-lg hover:-translate-y-0.5"
      >
        Get started free
      </a>
      <a
        href={~p"/pricing"}
        class="px-8 py-4 text-base font-semibold text-gray-700 bg-white border border-gray-200 rounded-xl hover:border-gray-300 hover:shadow-sm transition-all"
      >
        See pricing
      </a>
    </div>
  </div>
</section>

<%!-- How it works --%>
<section class="py-24 px-6 bg-white">
  <div class="max-w-5xl mx-auto">
    <h2 class="text-3xl font-bold text-gray-900 text-center mb-4">
      Up and running in minutes
    </h2>
    <p class="text-gray-500 text-center mb-16 max-w-xl mx-auto">
      No complicated setup. Works with Google Slides today.
    </p>

    <div class="grid grid-cols-1 md:grid-cols-3 gap-8">
      <div class="relative p-8 rounded-2xl bg-gradient-to-br from-indigo-50 to-white border border-indigo-100">
        <div class="text-4xl mb-4">🔌</div>
        <div class="text-xs font-bold text-indigo-500 uppercase tracking-wide mb-2">Step 1</div>
        <h3 class="text-lg font-semibold text-gray-900 mb-2">Install the extension</h3>
        <p class="text-gray-500 text-sm">
          Add the Speechwave Chrome extension and paste your API key from your account settings.
        </p>
      </div>

      <div class="relative p-8 rounded-2xl bg-gradient-to-br from-violet-50 to-white border border-violet-100">
        <div class="text-4xl mb-4">📲</div>
        <div class="text-xs font-bold text-violet-500 uppercase tracking-wide mb-2">Step 2</div>
        <h3 class="text-lg font-semibold text-gray-900 mb-2">Share the QR code</h3>
        <p class="text-gray-500 text-sm">
          Add the Speechwave URL to your first slide. The audience scans it to open the reaction page in their browser.
        </p>
      </div>

      <div class="relative p-8 rounded-2xl bg-gradient-to-br from-pink-50 to-white border border-pink-100">
        <div class="text-4xl mb-4">🎉</div>
        <div class="text-xs font-bold text-pink-500 uppercase tracking-wide mb-2">Step 3</div>
        <h3 class="text-lg font-semibold text-gray-900 mb-2">Watch the reactions</h3>
        <p class="text-gray-500 text-sm">
          Emoji reactions float up on your screen in real time as your audience taps them.
        </p>
      </div>
    </div>
  </div>
</section>

<%!-- Features --%>
<section class="py-24 px-6 bg-gray-50">
  <div class="max-w-5xl mx-auto">
    <h2 class="text-3xl font-bold text-gray-900 text-center mb-16">
      Everything you need on the free plan
    </h2>
    <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-6">
      <div class="p-6 bg-white rounded-2xl border border-gray-100 shadow-sm">
        <div class="text-2xl mb-3">😂</div>
        <h3 class="font-semibold text-gray-900 mb-1">Live emoji reactions</h3>
        <p class="text-sm text-gray-500">Up to 50 audience members react in real time.</p>
      </div>
      <div class="p-6 bg-white rounded-2xl border border-gray-100 shadow-sm">
        <div class="text-2xl mb-3">📊</div>
        <h3 class="font-semibold text-gray-900 mb-1">Session analytics</h3>
        <p class="text-sm text-gray-500">See reaction counts, timelines, and trends per session.</p>
      </div>
      <div class="p-6 bg-white rounded-2xl border border-gray-100 shadow-sm">
        <div class="text-2xl mb-3">📱</div>
        <h3 class="font-semibold text-gray-900 mb-1">QR code sharing</h3>
        <p class="text-sm text-gray-500">Auto-generated QR code for instant audience access.</p>
      </div>
      <div class="p-6 bg-white rounded-2xl border border-gray-100 shadow-sm">
        <div class="text-2xl mb-3">🎇</div>
        <h3 class="font-semibold text-gray-900 mb-1">Fireworks mode</h3>
        <p class="text-sm text-gray-500">When reactions surge, watch the fireworks fly.</p>
      </div>
      <div class="p-6 bg-white rounded-2xl border border-gray-100 shadow-sm">
        <div class="text-2xl mb-3">🔒</div>
        <h3 class="font-semibold text-gray-900 mb-1">Secure by default</h3>
        <p class="text-sm text-gray-500">Only you can start sessions for your talks.</p>
      </div>
      <div class="p-6 bg-white rounded-2xl border border-gray-100 shadow-sm">
        <div class="text-2xl mb-3">💸</div>
        <h3 class="font-semibold text-gray-900 mb-1">Free forever</h3>
        <p class="text-sm text-gray-500">The free plan has no time limit. Upgrade when you're ready.</p>
      </div>
    </div>
  </div>
</section>

<%!-- CTA --%>
<section class="py-24 px-6 bg-indigo-600">
  <div class="max-w-2xl mx-auto text-center">
    <h2 class="text-3xl font-bold text-white mb-4">
      Ready to energize your next talk?
    </h2>
    <p class="text-indigo-200 mb-10">
      Create your free account and have reactions live before your next slide deck is done.
    </p>
    <a
      href={~p"/users/register"}
      class="inline-block px-8 py-4 text-base font-semibold text-indigo-600 bg-white rounded-xl hover:bg-indigo-50 transition-all hover:shadow-lg hover:-translate-y-0.5"
    >
      Get started free
    </a>
  </div>
</section>

<%!-- Footer --%>
<footer class="py-10 px-6 bg-gray-900">
  <div class="max-w-6xl mx-auto flex flex-col sm:flex-row items-center justify-between gap-4 text-sm text-gray-500">
    <span>© {Date.utc_today().year} Speechwave</span>
    <div class="flex gap-6">
      <a href={~p"/terms"} class="hover:text-gray-300 transition-colors">Terms of Service</a>
      <a href={~p"/privacy"} class="hover:text-gray-300 transition-colors">Privacy Policy</a>
    </div>
  </div>
</footer>
```

- [ ] **Step 2: Run the page controller test**

```bash
mix test test/speechwave_web/controllers/page_controller_test.exs --grep "GET /"
```

Expected: Passes — the landing page renders and contains "Speechwave".

- [ ] **Step 3: Start the server and verify the landing page visually**

```bash
mix phx.server
```

Open `http://localhost:4000` in a browser. Verify:
- Navigation header is visible with logo, Pricing, Log in, Sign up links
- Hero section renders with CTA buttons
- How it works section shows 3 steps
- Features grid shows 6 cards
- CTA section has indigo background
- Footer shows ToS and Privacy links

- [ ] **Step 4: Commit**

```bash
git add lib/speechwave_web/controllers/page_html/home.html.heex
git commit -m "feat: replace Phoenix placeholder with Speechwave landing page"
```

---

## Task 3: Build the pricing page

**Files:**
- Create: `lib/speechwave_web/controllers/page_html/pricing.html.heex`

- [ ] **Step 1: Create `pricing.html.heex`**

```heex
<%!-- Navigation (same as landing page) --%>
<header class="fixed top-0 left-0 right-0 z-50 bg-white/80 backdrop-blur-md border-b border-gray-100">
  <div class="max-w-6xl mx-auto px-6 h-16 flex items-center justify-between">
    <a href="/" class="flex items-center gap-2 font-bold text-xl text-gray-900">
      <span class="text-2xl">🎤</span>
      Speechwave
    </a>
    <nav class="flex items-center gap-6">
      <a href={~p"/pricing"} class="text-sm font-medium text-indigo-600">Pricing</a>
      <a href={~p"/users/log-in"} class="text-sm text-gray-600 hover:text-gray-900 transition-colors">Log in</a>
      <a href={~p"/users/register"} class="px-4 py-2 text-sm font-medium text-white bg-indigo-600 rounded-lg hover:bg-indigo-700 transition-colors">
        Sign up free
      </a>
    </nav>
  </div>
</header>

<div class="pt-28 pb-24 px-6 bg-gray-50 min-h-screen">
  <div class="max-w-5xl mx-auto">
    <div class="text-center mb-16">
      <h1 class="text-4xl font-extrabold text-gray-900 mb-4">Simple, transparent pricing</h1>
      <p class="text-lg text-gray-500">Start free. Upgrade when you need more.</p>
    </div>

    <div class="grid grid-cols-1 md:grid-cols-3 gap-6 items-start">

      <%!-- Free --%>
      <div class="bg-white rounded-2xl border-2 border-indigo-500 shadow-lg p-8 relative">
        <div class="absolute -top-3 left-1/2 -translate-x-1/2">
          <span class="px-3 py-1 bg-indigo-500 text-white text-xs font-bold rounded-full">Current Plan</span>
        </div>
        <div class="mb-6">
          <h2 class="text-xl font-bold text-gray-900 mb-1">Free</h2>
          <div class="flex items-baseline gap-1">
            <span class="text-4xl font-extrabold text-gray-900">$0</span>
            <span class="text-gray-500">/month</span>
          </div>
          <p class="text-sm text-gray-500 mt-2">No credit card required.</p>
        </div>
        <ul class="space-y-3 mb-8 text-sm">
          <li class="flex items-center gap-2 text-gray-700">
            <span class="text-green-500 font-bold">✓</span> Up to 50 participants per talk
          </li>
          <li class="flex items-center gap-2 text-gray-700">
            <span class="text-green-500 font-bold">✓</span> 10 full sessions per month
          </li>
          <li class="flex items-center gap-2 text-gray-700">
            <span class="text-green-500 font-bold">✓</span> Live emoji reactions
          </li>
          <li class="flex items-center gap-2 text-gray-700">
            <span class="text-green-500 font-bold">✓</span> Session analytics
          </li>
          <li class="flex items-center gap-2 text-gray-700">
            <span class="text-green-500 font-bold">✓</span> QR code sharing
          </li>
          <li class="flex items-center gap-2 text-gray-700">
            <span class="text-green-500 font-bold">✓</span> Fireworks mode
          </li>
        </ul>
        <a
          href={~p"/users/register"}
          class="block w-full text-center py-3 px-6 bg-indigo-600 text-white rounded-xl font-semibold text-sm hover:bg-indigo-700 transition-colors"
        >
          Sign up free
        </a>
      </div>

      <%!-- Pro --%>
      <div class="bg-white rounded-2xl border border-gray-200 p-8 opacity-75">
        <div class="mb-6">
          <h2 class="text-xl font-bold text-gray-900 mb-1">Pro</h2>
          <div class="flex items-baseline gap-1">
            <span class="text-4xl font-extrabold text-gray-400">—</span>
          </div>
          <p class="text-sm text-gray-400 mt-2">Coming soon</p>
        </div>
        <ul class="space-y-3 mb-8 text-sm">
          <li class="flex items-center gap-2 text-gray-400">
            <span class="font-bold">✓</span> Unlimited participants
          </li>
          <li class="flex items-center gap-2 text-gray-400">
            <span class="font-bold">✓</span> Unlimited sessions
          </li>
          <li class="flex items-center gap-2 text-gray-400">
            <span class="font-bold">✓</span> Everything in Free
          </li>
        </ul>
        <button
          disabled
          class="block w-full text-center py-3 px-6 bg-gray-100 text-gray-400 rounded-xl font-semibold text-sm cursor-not-allowed"
        >
          Notify me
        </button>
      </div>

      <%!-- Enterprise --%>
      <div class="bg-white rounded-2xl border border-gray-200 p-8 opacity-75">
        <div class="mb-6">
          <h2 class="text-xl font-bold text-gray-900 mb-1">Enterprise</h2>
          <div class="flex items-baseline gap-1">
            <span class="text-4xl font-extrabold text-gray-400">—</span>
          </div>
          <p class="text-sm text-gray-400 mt-2">Coming soon</p>
        </div>
        <ul class="space-y-3 mb-8 text-sm">
          <li class="flex items-center gap-2 text-gray-400">
            <span class="font-bold">✓</span> Everything in Pro
          </li>
          <li class="flex items-center gap-2 text-gray-400">
            <span class="font-bold">✓</span> Priority support
          </li>
          <li class="flex items-center gap-2 text-gray-400">
            <span class="font-bold">✓</span> Custom integrations
          </li>
        </ul>
        <button
          disabled
          class="block w-full text-center py-3 px-6 bg-gray-100 text-gray-400 rounded-xl font-semibold text-sm cursor-not-allowed"
        >
          Contact us
        </button>
      </div>
    </div>

    <p class="text-center text-sm text-gray-400 mt-10">
      A "full session" is a session lasting longer than 10 minutes.
    </p>
  </div>
</div>

<footer class="py-10 px-6 bg-gray-900">
  <div class="max-w-6xl mx-auto flex flex-col sm:flex-row items-center justify-between gap-4 text-sm text-gray-500">
    <span>© {Date.utc_today().year} Speechwave</span>
    <div class="flex gap-6">
      <a href={~p"/terms"} class="hover:text-gray-300 transition-colors">Terms of Service</a>
      <a href={~p"/privacy"} class="hover:text-gray-300 transition-colors">Privacy Policy</a>
    </div>
  </div>
</footer>
```

- [ ] **Step 2: Run tests**

```bash
mix test test/speechwave_web/controllers/page_controller_test.exs --grep "pricing"
```

Expected: Passes.

- [ ] **Step 3: Check the pricing page visually**

Open `http://localhost:4000/pricing`. Verify all three plan cards render, Free is highlighted with a badge, Pro and Enterprise are dimmed with "Coming soon".

- [ ] **Step 4: Commit**

```bash
git add lib/speechwave_web/controllers/page_html/pricing.html.heex
git commit -m "feat: add pricing page with free/pro/enterprise tiers"
```

---

## Task 4: Build the Terms of Service page

**Files:**
- Create: `lib/speechwave_web/controllers/page_html/terms.html.heex`

- [ ] **Step 1: Create `terms.html.heex`**

```heex
<header class="fixed top-0 left-0 right-0 z-50 bg-white/80 backdrop-blur-md border-b border-gray-100">
  <div class="max-w-6xl mx-auto px-6 h-16 flex items-center justify-between">
    <a href="/" class="flex items-center gap-2 font-bold text-xl text-gray-900">
      <span class="text-2xl">🎤</span>
      Speechwave
    </a>
  </div>
</header>

<div class="pt-28 pb-24 px-6">
  <div class="max-w-2xl mx-auto [&_h2]:text-lg [&_h2]:font-semibold [&_h2]:text-gray-900 [&_h2]:mt-8 [&_h2]:mb-2 [&_p]:text-gray-600 [&_p]:leading-relaxed [&_a]:text-indigo-600 [&_a]:underline">
    <h1 class="text-3xl font-bold text-gray-900 mb-2">Terms of Service</h1>
    <p class="text-gray-400 text-sm mb-8">Last updated: April 2026</p>

    <h2>1. Acceptance of Terms</h2>
    <p>
      By accessing or using Speechwave ("the Service"), you agree to be bound
      by these Terms of Service. If you do not agree to these terms, do not
      use the Service.
    </p>

    <h2>2. Description of Service</h2>
    <p>
      Speechwave provides a live audience reaction platform for presenters,
      including a web dashboard, browser extension, and audience-facing
      reaction pages.
    </p>

    <h2>3. Account Responsibilities</h2>
    <p>
      You are responsible for maintaining the confidentiality of your account
      credentials, including your API key. You agree to notify us immediately
      of any unauthorized use of your account.
    </p>

    <h2>4. Acceptable Use</h2>
    <p>
      You may not use the Service to transmit harmful, offensive, or illegal
      content. You may not attempt to reverse-engineer, abuse, or disrupt the
      Service or its infrastructure.
    </p>

    <h2>5. Free Tier Limits</h2>
    <p>
      The free plan includes up to 50 participants per talk and 10 full sessions
      (longer than 10 minutes) per calendar month. We reserve the right to
      enforce these limits and to modify them with notice.
    </p>

    <h2>6. Termination</h2>
    <p>
      We reserve the right to suspend or terminate accounts that violate these
      terms. You may delete your account at any time by contacting us.
    </p>

    <h2>7. Disclaimer of Warranties</h2>
    <p>
      The Service is provided "as is" without warranty of any kind. We do not
      guarantee uninterrupted availability or error-free operation.
    </p>

    <h2>8. Limitation of Liability</h2>
    <p>
      To the fullest extent permitted by law, Speechwave shall not be liable
      for any indirect, incidental, or consequential damages arising from your
      use of the Service.
    </p>

    <h2>9. Governing Law</h2>
    <p>
      These terms are governed by the laws of the United States. Any disputes
      shall be resolved in the applicable courts.
    </p>

    <h2>10. Changes to These Terms</h2>
    <p>
      We may update these terms from time to time. Continued use of the Service
      after changes constitutes acceptance of the new terms.
    </p>

    <h2>11. Contact</h2>
    <p>
      For questions about these terms, contact us at
      <a href="mailto:hello@speechwave.live">hello@speechwave.live</a>.
    </p>
  </div>
</div>

<footer class="py-10 px-6 bg-gray-900">
  <div class="max-w-6xl mx-auto flex flex-col sm:flex-row items-center justify-between gap-4 text-sm text-gray-500">
    <span>© {Date.utc_today().year} Speechwave</span>
    <div class="flex gap-6">
      <a href={~p"/terms"} class="hover:text-gray-300 transition-colors">Terms of Service</a>
      <a href={~p"/privacy"} class="hover:text-gray-300 transition-colors">Privacy Policy</a>
    </div>
  </div>
</footer>
```

> **Important:** Review and customize this content with your team before launch. This is a template — it is not legal advice.

- [ ] **Step 2: Run tests**

```bash
mix test test/speechwave_web/controllers/page_controller_test.exs --grep "terms"
```

Expected: Passes.

- [ ] **Step 3: Commit**

```bash
git add lib/speechwave_web/controllers/page_html/terms.html.heex
git commit -m "feat: add Terms of Service page"
```

---

## Task 5: Build the Privacy Policy page

**Files:**
- Create: `lib/speechwave_web/controllers/page_html/privacy.html.heex`

- [ ] **Step 1: Create `privacy.html.heex`**

```heex
<header class="fixed top-0 left-0 right-0 z-50 bg-white/80 backdrop-blur-md border-b border-gray-100">
  <div class="max-w-6xl mx-auto px-6 h-16 flex items-center justify-between">
    <a href="/" class="flex items-center gap-2 font-bold text-xl text-gray-900">
      <span class="text-2xl">🎤</span>
      Speechwave
    </a>
  </div>
</header>

<div class="pt-28 pb-24 px-6">
  <div class="max-w-2xl mx-auto [&_h2]:text-lg [&_h2]:font-semibold [&_h2]:text-gray-900 [&_h2]:mt-8 [&_h2]:mb-2 [&_p]:text-gray-600 [&_p]:leading-relaxed [&_ul]:list-disc [&_ul]:pl-6 [&_ul]:text-gray-600 [&_ul]:space-y-1 [&_a]:text-indigo-600 [&_a]:underline">
    <h1 class="text-3xl font-bold text-gray-900 mb-2">Privacy Policy</h1>
    <p class="text-gray-400 text-sm mb-8">Last updated: April 2026</p>

    <h2>1. What We Collect</h2>
    <p>
      We collect the following information when you use Speechwave:
    </p>
    <ul>
      <li><strong>Email address</strong> — used to create and manage your account.</li>
      <li><strong>Usage data</strong> — number of sessions, participants, and reactions, used to enforce plan limits and improve the service.</li>
    </ul>
    <p>
      Audience members who use the reaction page are anonymous. We do not
      collect any personal information from audience members.
    </p>

    <h2>2. How We Use Your Data</h2>
    <p>
      We use your email address to send account confirmation and password reset
      emails. We use usage data solely to provide and improve the Service,
      including enforcing free tier limits.
    </p>

    <h2>3. Data Storage</h2>
    <p>
      Your data is stored on infrastructure provided by
      <a href="https://fly.io" target="_blank">Fly.io</a>,
      located in the United States.
    </p>

    <h2>4. Data Sharing</h2>
    <p>
      We do not sell, rent, or share your personal data with third parties,
      except as required by law.
    </p>

    <h2>5. Cookies and Sessions</h2>
    <p>
      We use a session cookie to keep you logged in. No third-party tracking
      cookies are used.
    </p>

    <h2>6. Data Deletion</h2>
    <p>
      You may request deletion of your account and all associated data by
      emailing us at
      <a href="mailto:hello@speechwave.live">hello@speechwave.live</a>.
      We will process your request within 30 days.
    </p>

    <h2>7. Changes to This Policy</h2>
    <p>
      We may update this policy from time to time. Continued use of the Service
      after changes constitutes acceptance of the updated policy.
    </p>

    <h2>8. Contact</h2>
    <p>
      For privacy questions, contact us at
      <a href="mailto:hello@speechwave.live">hello@speechwave.live</a>.
    </p>
  </div>
</div>

<footer class="py-10 px-6 bg-gray-900">
  <div class="max-w-6xl mx-auto flex flex-col sm:flex-row items-center justify-between gap-4 text-sm text-gray-500">
    <span>© {Date.utc_today().year} Speechwave</span>
    <div class="flex gap-6">
      <a href={~p"/terms"} class="hover:text-gray-300 transition-colors">Terms of Service</a>
      <a href={~p"/privacy"} class="hover:text-gray-300 transition-colors">Privacy Policy</a>
    </div>
  </div>
</footer>
```

> **Important:** Review and customize this content with your team before launch. This is a template — it is not legal advice.

- [ ] **Step 2: Run tests**

```bash
mix test test/speechwave_web/controllers/page_controller_test.exs --grep "privacy"
```

Expected: Passes.

- [ ] **Step 3: Commit**

```bash
git add lib/speechwave_web/controllers/page_html/privacy.html.heex
git commit -m "feat: add Privacy Policy page"
```

---

## Task 6: Run full test suite and precommit

- [ ] **Step 1: Run all tests**

```bash
mix test
```

Expected: All pass.

- [ ] **Step 2: Run precommit**

```bash
mix precommit
```

Fix any issues and commit if needed:

```bash
git add -A && git commit -m "chore: precommit fixes for public pages"
```

- [ ] **Step 3: Verify all pages visually in the browser**

With `mix phx.server` running, open and spot-check each page:
- `http://localhost:4000/` — landing page
- `http://localhost:4000/pricing` — pricing page
- `http://localhost:4000/terms` — ToS page
- `http://localhost:4000/privacy` — Privacy page

Verify the navigation logo links back to `/` on all pages. Verify footer links are correct on all pages.
