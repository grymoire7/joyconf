# Interactive Codebase Explainer — Design Spec

**Date:** 2026-05-09
**Status:** Approved
**Output:** `docs/explainer/index.html`

---

## Goal

Replace `docs/explainer.md` (which became stale) with a rich, self-contained HTML page that reflects the current codebase state and gives a new developer a complete mental model of how Speechwave works.

---

## Structure

**Sidebar chapters + scrollable content** — a persistent left sidebar lists all chapters. Clicking a chapter loads its content into the main area without a page reload (JS `hashchange` / `data-chapter` toggle). Within a chapter the reader scrolls normally. Feels like Phoenix docs or MDN.

All CSS, JS, and SVG are inlined — no build step, no CDN dependency, no external requests.

---

## Chapters

### Getting Started

1. **Overview** — The big picture: three actors (Attendee, Phoenix Server, Speaker), two WebSocket connections (`/live` vs `/socket`), how PubSub ties them together. Static SVG architecture diagram. File tree showing current project layout.

2. **Data Model** — All five schemas annotated with purpose and key design notes:
   - `users` — email, plan, api_key, is_admin, has_many identities
   - `user_identities` — provider + uid for OAuth accounts (one user can have many)
   - `talks` — title, slug, belongs_to user (scope-aware ownership)
   - `talk_sessions` — recording windows, started_at/ended_at, has_many reactions
   - `reactions` — emoji, slide_number, belongs_to talk_session

### Key Flows

3. **Authentication** *(new)* — Passwordless-only system:
   - Magic link flow: email submitted → `register_or_get_user_by_email` → `UserToken` (type: "login") → email → `/users/magic_link/:token` → session
   - OAuth flow (Assent): authorize redirect → provider callback → `find_or_create_user_from_oauth` → session. Also supports "connect" context (logged-in user linking a new provider)
   - `Scope` struct wrapping the authenticated user — passed as first arg to all scoped context functions
   - API key — auto-generated on User insert, displayed in Settings, used by Chrome extension to join the Channel
   - Sudo mode — 20-minute window after last authentication for sensitive operations

4. **Emoji Journey** *(step-by-step animated stepper, 6 steps)*:
   1. Attendee taps button → `phx-click="react"` → LiveView `handle_event`
   2. `RateLimiter.allow?/1` — ETS check, 3s cooldown per socket.id
   3. Persist reaction to DB if active session exists (with current_slide)
   4. `Endpoint.broadcast!/3` → PubSub → all subscribers of `"reactions:slug"`
   5. `TalkLive.handle_info` → `push_event` → `EmojiStream` JS hook → floating emoji in browser
   6. `ReactionChannel` → WebSocket push → Chrome extension `spawnEmoji()`

5. **WebSockets** — Two connections in depth:
   - `/live` — Phoenix LiveView socket, managed automatically, handles `phx-click` events and `push_event` delivery
   - `/socket` — Bare Phoenix Channel socket used by Chrome extension; `check_origin: false` allows `chrome-extension://` origin; requires `api_key` param on join; owner verified against talk.user_id
   - Why PubSub bridges them: `broadcast!/3` is subscriber-type-agnostic — `handle_event` in `TalkLive` doesn't know the extension exists

### Infrastructure

6. **Plans & Limits** *(new)* — Three tiers (`:free`, `:pro`, `:org`):
   - `Plans.limit/2` — pure function returning the limit value (or `:unlimited`) for a feature × plan combination
   - `Plans.check/3` — returns `:ok` or `{:error, :limit_reached}`
   - Two enforced features: `:max_participants` and `:full_sessions_per_month`
   - Participant counting via `Presence.list/1` — map_size of tracked sockets in `"reactions:slug"` topic, checked at channel join
   - Full session counting via `count_full_sessions_this_month/1` — sessions > 600 seconds in the current calendar month

7. **Supervision Tree** — Updated diagram:
   - Added `SpeechwaveWeb.Presence` (always started)
   - Added `Speechwave.DbBackup` (conditionally started — only when `STORAGE_BUCKET` env var is set)
   - Restart semantics: RateLimiter crash wipes ETS table (fresh cooldown state, acceptable data loss)

8. **DB Backup** *(new)* — `Speechwave.DbBackup` GenServer:
   - Runs 5 minutes after boot, then every hour
   - `VACUUM INTO '/tmp/speechwave_backup.db'` — creates a live, consistent SQLite snapshot without locking the main DB
   - Uploads to S3-compatible storage via `Req.put!/2` with `aws_sigv4` signing
   - Conditionally started: only when `STORAGE_BUCKET` env var is present (not in dev)

### Features

9. **Chrome Extension** — Two parts: Popup (slug + connect) and Content Script (WebSocket, overlay, animations):
   - Channel join now requires `api_key` in params
   - Fireworks: compound trigger (`count >= MIN_COUNT && count/total >= MIN_PERCENT`), in-flight tracking, global cooldown, Web Animations API for computed trajectories
   - Slide tracking: `MutationObserver` + adapter registry (`GoogleSlidesAdapter`)
   - Fullscreen re-parenting: overlay moved into `document.fullscreenElement` on `fullscreenchange`

10. **Analytics** — Per-slide reaction aggregation, bar chart rendering in pure Tailwind, session comparison mode at `/sessions/:id/compare/:other_id`

---

## Visual Style

- **Color palette:** Dark background (`#0f172a`) for sidebar + code blocks; light (`#f8fafc`) for main content
- **Accent:** Purple (`#7c3aed` / `#a78bfa`) for active nav, code keywords, callout borders
- **Code blocks:** Monospace, syntax-highlighted with inline `<span>` tags (no external library needed)
- **Callout boxes:** Left-bordered purple strip with a "Why?" label — used for non-obvious design decisions
- **Schema tables:** Clean, borderless with monospace field names in purple
- **New badges:** Small purple pill on sidebar items for chapters covering genuinely new functionality

---

## Interactive Components

### Step Stepper
Used in: Emoji Journey, Authentication, WebSocket join flow

- Progress dots at top-right of stepper card
- Diagram row showing all nodes; active node highlighted, past nodes dimmed
- Description text explains the active step
- Prev/Next buttons; keyboard accessible (left/right arrows)

### Collapsible "Why?" Sections
Used throughout all chapters for non-obvious design decisions.

- Click to expand/collapse
- Icon rotates on expand

### Sidebar Navigation
- Active item highlighted with left border + purple text
- "new" badge on Authentication, Plans & Limits, DB Backup chapters
- Smooth scroll to top of main area on chapter change

---

## What Changed Since the Old Explainer

The spec covers all of these and the implementation should make them prominent:

| Area | Change |
|------|--------|
| Auth | Completely new — passwordless magic links + OAuth (Assent); no passwords |
| Talk ownership | Talks now `belongs_to :user`; all queries are scope-filtered |
| Admin panel | Replaced by per-user `DashboardLive` at `/dashboard` |
| Channel auth | `join/3` now requires `api_key` + owner verification |
| Presence | Added for participant counting |
| Plans | New `Plans` module — free/pro/org tier enforcement |
| Supervision | Added `Presence`, conditional `DbBackup` |
| DB Backup | New GenServer with hourly VACUUM INTO + S3 upload |
| Emoji set | Expanded from 5 to 9 emojis |

---

## Implementation Notes

- Single HTML file, fully self-contained (no external CSS, JS, or font CDN calls)
- Chapter switching handled by a small vanilla JS module (~60 lines)
- Stepper state managed per-chapter with simple counter
- No build step — edit the HTML file directly
- The old `docs/explainer.md` stays in place until the HTML version is complete and reviewed, then it can be deleted
