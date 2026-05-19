# Architectural Decisions

## 2026-05-05 — Passwordless authentication (magic links + OAuth)

**Decision:** Replace password-based `phx.gen.auth` with a passwordless system
using email magic links as the primary flow and OAuth SSO (Google, GitHub,
Microsoft via Assent) as a secondary flow.

**Why:** Speakers are occasional users who forget passwords; magic links remove
that friction entirely. Magic link doubles as registration, eliminating the
separate signup form. No passwords means no bcrypt overhead, no password-reset
flow, and nothing for an attacker to steal from the `users` table.

**What changed:**
- Removed `hashed_password` and `confirmed_at` columns from `users`
- Removed `bcrypt_elixir` dependency; added `assent` for OAuth
- Added `user_identities` table — one row per linked OAuth provider account,
  with a unique constraint on `{provider, uid}` to prevent spoofing
- Magic link tokens use the existing `users_tokens` table under a new
  `"magic_link"` context (15-minute TTL, single-use)
- Unified login/signup page at `/users/log-in` — email submission sends a
  magic link; OAuth buttons redirect through Assent; no separate registration
  screen
- `find_or_create_user_from_oauth/2` upserts by email so a user who signs in
  via magic link and later via Google with the same address gets one account
- Dev-only backdoor at `/dev/login` — lists existing users as clickable links
  and accepts any email, bypassing all auth (never compiled in production)

**Trade-offs:** Rate limiting on magic link sends is deferred; the login page
is currently unprotected against enumeration-at-volume. Post-launch concern.
