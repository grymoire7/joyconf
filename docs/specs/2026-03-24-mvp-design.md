# JoyConf MVP — Design Spec

**Date:** 2026-03-24

## Overview

JoyConf is a web app that allows conference talk attendees to send live emoji reactions during a talk. Reactions appear as floating animations on attendees' phones and as an overlay on the speaker's Google Slides presentation via a Chrome extension.

---

## Tech Stack

| Concern | Choice |
|---|---|
| Language / framework | Elixir / Phoenix LiveView |
| Real-time | Phoenix PubSub + Channels |
| Database | PostgreSQL (Fly.io managed) |
| Deployment | Fly.io |
| Extension | Chrome (Manifest V3, content script) |

---

## Architecture

Three client surfaces connect to a single Phoenix app:

- **Attendee browser** — Phoenix LiveView over WebSocket. No authentication. Per-talk URL.
- **Chrome extension** — Phoenix Channel over WebSocket. Receives reaction broadcasts and renders an overlay on Google Slides.
- **Admin browser** — Phoenix LiveView over WebSocket. Password-protected via a plug checking `ADMIN_PASSWORD` env var.

Inside the Phoenix app:

- `TalkLive` — LiveView serving the attendee reaction page
- `AdminLive` — LiveView for talk creation
- `ReactionChannel` — Phoenix Channel for extension clients
- `RateLimiter` — ETS-backed module enforcing one reaction per session per 5 seconds
- PubSub — fan-out backbone shared by LiveView processes and `ReactionChannel`

**Real-time flow:**

1. Attendee taps emoji → client JS disables all buttons for 5s (UX)
2. `TalkLive` `handle_event` receives reaction → checks `RateLimiter` (server enforcement) → broadcasts via PubSub on `"reactions:#{slug}"`
3. All `TalkLive` processes on that topic receive the broadcast → push `floating_emoji` JS event to DOM
4. `ReactionChannel` (also subscribed) pushes the same event to connected extension clients
5. Extension content script receives the push → creates a floating emoji DOM element → CSS animation plays (drift up ~50px, fade out) → element removed on `animationend`

---

## Data Model

One table. Reactions are ephemeral — never persisted.

```
talks
  id           :integer, primary key
  title        :string, not null
  slug         :string, not null, unique  # lowercase, hyphens and digits only, max 100 chars
  inserted_at  :utc_datetime
  updated_at   :utc_datetime
```

Rate limiting state is held in an ETS table (in-memory, keyed by session ID). It does not survive application restarts, which is acceptable.

---

## Pages & Routes

| Route | Module | Auth |
|---|---|---|
| `GET /t/:slug` | `TalkLive` | None |
| `GET /admin` | `AdminLive` (index) | `ADMIN_PASSWORD` plug |
| `GET /admin/talks/new` | `AdminLive` (new) | `ADMIN_PASSWORD` plug |
| `WS /socket/websocket` | `UserSocket` | None |

`UserSocket` is declared in `endpoint.ex` and mounts `ReactionChannel` on the `"reactions:*"` topic.

---

## Attendee Page (`/t/:slug`)

- Displays the talk title
- Shows 5 emoji reaction buttons: ❤️ 😂 🔥 👏 🤯 (configurable in code)
- Live reaction stream: floating emojis from all attendees drift up and fade in real-time
- After any tap: all buttons dim to ~35% opacity and are disabled for 5s, then restore. A countdown label shows remaining cooldown time.
- Unknown slug → 404 page

---

## Admin

- Single env-var password (`ADMIN_PASSWORD`), checked in a plug. No user accounts.
- Talk creation form: title field, auto-generated slug (editable), preview of attendee URL
- On submit: creates talk, generates QR code (PNG, via `eqrcode` hex package) linking to the attendee URL, displays QR for download
- Lists existing talks with their slugs

---

## Chrome Extension

- **Manifest V3**, content script injected on `slides.google.com`
- **Popup:** Speaker enters talk slug once. Stored in `chrome.storage.local`. Shows connection status (Connected / Disconnected).
- **Connection:** Connects to a host URL bundled at extension build time (defaulting to the production Fly.io URL). Joins channel `"reactions:<slug>"` using the stored slug.
- **Overlay:** A `div` injected into the bottom-right corner of the slide canvas. Non-interactive (`pointer-events: none`). Floats emoji elements on each channel push; each element removes itself after the CSS animation completes (~800ms).
- **Reconnection:** Standard Phoenix JS client exponential backoff — no custom reconnect logic needed.

---

## Rate Limiting

Two layers:

1. **Client-side (UX):** After any tap, JS disables all buttons for 5s. Prevents unnecessary WebSocket traffic.
2. **Server-side (enforcement):** ETS table stores `{session_id, last_reaction_at}`. `RateLimiter` rejects events arriving within 5s of the previous one from the same session. Server silently drops rejected events.

---

## Error Handling

| Scenario | Behavior |
|---|---|
| Extension WebSocket disconnect | Phoenix JS client reconnects automatically with backoff |
| Server-side rate limit exceeded | Event silently dropped (client-side cooldown prevents this in normal use) |
| Unknown talk slug (attendee) | 404 LiveView page |
| Unknown talk slug (extension) | Popup shows "Disconnected" |
| Fly.io instance restart | LiveView and Channel reconnect automatically; in-flight reactions lost (acceptable) |

---

## Testing

Development follows **TDD red-green-refactor**: write a failing test first, make it pass, then refactor.

- **Unit tests:** `RateLimiter` (ETS logic), `Talk` changeset (slug validation, uniqueness)
- **LiveView integration tests:** `TalkLive` (reaction event handling, rate limit enforcement, broadcast), `AdminLive` (talk creation, QR code generation)
- **Channel tests:** `ReactionChannel` (join, reaction broadcast fan-out)
- **Chrome extension:** Manual testing only for MVP

---

## Deployment

- Single Fly.io app, one region for MVP
- Fly managed PostgreSQL, attached via `fly postgres attach`
- Secrets: `ADMIN_PASSWORD`, `DATABASE_URL`, `SECRET_KEY_BASE`
- `eqrcode` used for server-side QR PNG generation

---

## Out of Scope (MVP)

- Q&A / other poll types
- Speaker dashboard
- Admin dashboard / analytics
- Reaction persistence
- Multi-region deployment
