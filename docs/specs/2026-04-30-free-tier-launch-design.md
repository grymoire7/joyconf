# Free Tier Launch Design

**Date:** 2026-04-30
**Status:** Approved

## Overview

This document covers the four phases needed to launch Speechwave's free tier
publicly. The work spans the main `speechwave` Phoenix app and the
`chrome-extension` repo.

**Goal:** A publicly launchable free tier with authentication-gated extension
access, reliable infrastructure, and public-facing marketing pages.

**Out of scope:** Paid plan billing, plan upgrades, admin dashboard.

---

## Phase 1 — SQLite Migration

### Motivation

The fly.io free tier allocates 256MB RAM. PostgreSQL exhausts this even under
no load, causing database restarts mid-talk and losing reaction data. SQLite
runs in-process with the Elixir VM and has negligible memory overhead.

### Approach

- Replace `postgrex` with `ecto_sqlite3` in `mix.exs` and Ecto config.
- Change `Ecto.Adapters.Postgres` → `Ecto.Adapters.SQLite3` in `config/`.
- Database file path: `/data/speechwave.db` on a fly.io persistent volume.
- Run Litestream as a sidecar to continuously replicate the SQLite WAL to
  Tigris (fly.io object storage, free up to 5GB — well within expected usage).

### Query compatibility

One Postgres-specific query must be rewritten:

`count_full_sessions_this_month/1` in `Speechwave.Talks` uses:
```sql
EXTRACT(EPOCH FROM (ended_at - started_at)) > 600
```

Replace with SQLite equivalent:
```sql
(strftime('%s', ended_at) - strftime('%s', started_at)) > 600
```

All other schema and queries are SQLite-compatible as-is.

### Infrastructure

- Add a `[mounts]` section to `fly.toml` for the `/data` volume.
- Add a `[processes]` or release command to run `litestream replicate` alongside the app.
- Document restore procedure for disaster recovery.

---

## Phase 2 — API Keys + Extension Auth

### Motivation

Currently, anyone who knows a talk's slug can join its reaction channel. The
slug is displayed on the first slide of every talk, so it is not a secret. We
need to ensure only the talk owner (or an authorized user) can connect the
extension to a talk, and that usage limits are enforced per user.

### Server Changes

**Schema:**
- Add `api_key` (`:string`) column to the `users` table.
- Generate a cryptographically random 32-byte hex string on user creation via
  `Accounts.create_user`. Use `:crypto.strong_rand_bytes(32) |>
  Base.encode16(case: :lower)`.
- `api_key` must not appear in `cast/2` calls — set programmatically only.
- The migration must backfill `api_key` for any existing users using a
  generated default (e.g., via a migration-time `execute/1` SQL statement or an
  Ecto `Repo.update_all`).

**ReactionChannel.join/3:**

The channel params now include `api_key`. Validation order:

1. Look up the talk by slug. Return `{:error, %{reason: "not_found"}}` if missing.
2. Look up the user by `api_key`. Return `{:error, %{reason: "unauthorized"}}` if no match.
3. Check `user.confirmed_at` is not nil. Return `{:error, %{reason: "email_not_confirmed"}}` if unconfirmed.
4. Check `talk.user_id == user.id`. Return `{:error, %{reason: "unauthorized"}}` if mismatch.
5. Check `max_participants` plan limit (existing logic). Return `{:error, %{reason: "capacity_reached"}}` if exceeded.
6. On success: subscribe the channel process to `"user:{user.id}:disconnect"`
   via `Phoenix.PubSub`, then proceed with `send(self(), :after_join)` and
   assign both `talk` and `user` to the socket. Handle the disconnect broadcast
   with `{:stop, :normal, socket}`.

Auth occurs only at join time. Once joined, the channel connection is trusted
for its lifetime — no per-message credential checks.

**Settings page:**
- Display the user's API key in `UserLive.Settings` in a read-only, copyable input field.
- Include a "Regenerate" button (with confirmation) for users who believe their
  key is compromised. On regeneration, the server broadcasts to a user-specific
  PubSub topic (`"user:{user_id}:disconnect"`); any active `ReactionChannel`
  processes subscribed to that topic handle the message by stopping (`{:stop,
  :normal, socket}`), terminating the connection immediately. New join attempts
  with the old key will also fail since the key no longer exists in the database.
- The extension receives the channel close and should surface a message
  prompting the user to update their API key in the popup.

### Extension Changes

**One-time setup:**
- On popup open, check `chrome.storage.sync` for a stored `apiKey`.
- If none is found, show a setup screen in the popup with a text input for the
  API key and a link to the Speechwave dashboard settings page. The user pastes
  their key once; it is saved to `chrome.storage.sync` and syncs across Chrome
  profiles.
- Once saved, the normal slug/connect UI is shown.

**Channel connection:**
- Pass `{ api_key: storedApiKey }` as the channel params on join:
  ```js
  socket.channel(`reactions:${slug}`, { api_key: storedApiKey })
  ```

**Error handling in popup:**
- `"unauthorized"` → "Invalid API key or you don't own this talk."
- `"email_not_confirmed"` → "Please confirm your email before using the extension."
- `"capacity_reached"` → "Talk is at capacity." (existing)
- `"not_found"` → "Talk not found." (existing)

### Dashboard Banner

Users with `confirmed_at == nil` see a persistent banner at the top of the dashboard:

> "Please confirm your email address to activate the browser extension. [Resend confirmation email]"

The banner is dismissed once `confirmed_at` is set (i.e., after the user clicks the confirmation link).

---

## Phase 3 — Public Pages

All new pages are added as routes in the existing `:browser` pipeline. Static
content pages (ToS, Privacy) use controller actions. The landing and pricing
pages may use LiveView or controller actions — controller is simpler for static
content.

### Home / Landing Page

Replaces the default Phoenix placeholder at `/`.

Content sections:
1. **Hero** — tagline, brief description of what Speechwave does, primary CTA ("Get started free" → `/users/register`).
2. **How it works** — three-step explainer: install the extension → share your QR code → watch reactions appear live.
3. **Features** — highlights of the free plan (live emoji reactions, session analytics, QR code sharing).
4. **CTA footer** — secondary sign-up prompt.

Navigation header: logo, "Pricing" link, "Log in" link, "Sign up" button.
Page footer: "Terms of Service" and "Privacy Policy" links.

### Pricing Page (`/pricing`)

Three-column layout:

| Free | Pro | Enterprise |
|------|-----|------------|
| $0/month | Coming soon | Coming soon |
| 50 participants | Unlimited participants | — |
| 10 full sessions/month | Unlimited sessions | — |
| Sign up | Notify me | Contact us |

"Notify me" and "Contact us" are placeholder links or simple mailto links for now — no backend needed.

### Terms of Service (`/terms`)

Standard SaaS terms covering: acceptance of terms, description of service,
account responsibilities, acceptable use, termination, disclaimer of
warranties, limitation of liability, governing law. Template content to be
reviewed and customized by the team before launch.

### Privacy Policy (`/privacy`)

Covers: what data is collected (email address, usage data), how it is stored
(fly.io infrastructure, US region), that it is not sold to third parties, data
deletion requests (email to contact address), cookie/session use. Template
content to be reviewed and customized before launch.

---

## Phase 4 — Usage Visibility

### Dashboard Usage Summary

A new section on `DashboardLive` showing the user's current free tier
consumption. Rendered on mount; refreshed when a session is started or stopped.

**Displayed metrics:**

1. **Full sessions this month** — `X / 10 used` with a progress bar. Sourced
   from the existing `Talks.count_full_sessions_this_month/1`. The bar turns
   amber at 8/10 and red at 10/10.
2. **Max participants per talk** — static display of the plan cap (50 for
   free). No per-user tracking needed; enforcement already happens at channel
   join.

**No new data model required.** Both values are derived from existing schema
and `Speechwave.Plans` config.

The confirmation-pending email banner (from Phase 2) appears above the usage
summary for unconfirmed users.

---

## Phasing Summary

| Phase                | What ships                              | Enables                                      |
| -------------------- | --------------------------------------- | -------------------------------------------- |
| 1 — SQLite           | Database migration + Litestream backups | Reliable infrastructure, unblocks production |
| 2 — API keys         | Extension auth, email confirmation gate | Safe to open to public                       |
| 3 — Public pages     | Landing, pricing, ToS, privacy          | Marketing and legal readiness                |
| 4 — Usage visibility | Dashboard usage summary + email banner  | User transparency, plan limit awareness      |

Phases 3 and 4 can be developed in parallel once Phase 2 is complete.

