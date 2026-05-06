# Passwordless Authentication Design

**Date:** 2026-05-05
**Status:** Approved

## Overview

Replace the existing password-based `phx.gen.auth` scaffold with a passwordless authentication system using magic links as the primary flow and OAuth SSO (Google, Microsoft, GitHub) as a secondary flow. Eliminates the password reset flow, email confirmation flow, and all bcrypt/password logic. The existing session and token infrastructure is preserved and extended.

## Motivation

- Reduces friction for occasional-use speakers (no password to remember or reset)
- Eliminates password reset and email confirmation flows
- No passwords to steal
- Magic link doubles as registration — no separate signup form needed
- SSO is the fastest path for corporate presenters with Google/Microsoft accounts

## Data Model

### `users` table — changes

Remove `hashed_password` and `confirmed_at` columns via migration. Remove `password` virtual field from the schema. Remove `bcrypt_elixir` dependency.

Fields that remain: `email`, `api_key`, `plan`, `is_admin`, `inserted_at`, `updated_at`.

### New `user_identities` table

Stores OAuth provider associations. One row per linked provider account, allowing a single user to link multiple providers.

```
user_identities
  id            integer, primary key
  user_id       integer, FK → users (not null, on delete: delete all)
  provider      string (e.g. "google", "microsoft", "github")
  uid           string (provider's opaque user identifier)
  inserted_at   utc_datetime
  updated_at    utc_datetime
```

Unique constraint on `{provider, uid}`.

### `users_tokens` table — no changes

The existing token infrastructure supports multiple contexts. Magic links use a new `"magic_link"` context alongside the existing `"session"` context. Token TTL for magic links: 15 minutes, single-use (deleted on verification).

### Seeds

Admin seed creates a user by email only — no password. Admin logs in via magic link or OAuth.

## Auth Flows

### Magic link

1. User submits email on the login page
2. `Accounts.deliver_magic_link_email/2` looks up or creates the user by email, generates a token (stored in `users_tokens` with context `"magic_link"`, 15-minute TTL), and sends the email via Swoosh
3. In dev, the email is available at `/dev/mailbox`; in production, sent via Resend (Swoosh adapter)
4. User clicks the link → `GET /users/magic_link/:token`
5. `UserSessionController` verifies the token, deletes it (single-use), creates a session token, redirects to the app
6. Expired or already-used token → redirect to login with flash error

Magic link doubles as registration. No separate signup form. No indication in the response whether the account pre-existed (avoids email enumeration).

### OAuth (Assent)

1. User clicks a provider button → `GET /auth/:provider`
2. `UserSessionController` initiates the Assent OAuth redirect
3. Provider redirects to `GET /auth/:provider/callback`
4. Assent validates the callback, returns email + provider UID
5. `Accounts.find_or_create_user_from_oauth/2`:
   - Looks up `UserIdentity` by `{provider, uid}`
   - If found: loads the associated user
   - If not found: upserts a user by email (creating if new), inserts the `UserIdentity` record
6. Creates a session token, redirects to the app

The upsert-by-email behavior ensures that a user who previously signed in via magic link with `alice@gmail.com` and later signs in with Google using the same address gets the same account with a newly linked identity — no duplicate accounts.

The same `/auth/:provider` and `/auth/:provider/callback` routes handle two contexts:

- **Login/signup** (user not authenticated): find-or-create user, create session, redirect to app
- **Connect provider** (user already authenticated): add `UserIdentity` to the current user, redirect to settings with a success flash

The OAuth initiation step stores the context (`"login"` or `"connect"`) in the session so the callback handler knows which path to take.

**Providers at launch:** Google (required), Microsoft (required), GitHub (nice-to-have).

### Dev backdoor

A dev-only route at `/dev/login` renders a list of existing users as clickable rows plus a freeform email input. Submitting creates a session directly, bypassing all auth. Mounted only in the dev router scope alongside the Swoosh mailbox and LiveDashboard.

## Session & Auth Infrastructure

### Unchanged

- `UserToken` schema and session token functions (`build_session_token/1`, `verify_session_token_query/1`)
- `UserAuth` plug module (`fetch_current_scope_for_user`, `require_authenticated`, `redirect_if_user_is_authenticated`)
- Router `live_session` scopes and `pipe_through` pipelines
- `Scope` struct and `current_scope` assignment in LiveViews

### Removed

- `build_email_token` / `verify_email_token_query` for password reset and confirmation contexts
- `valid_password?` and bcrypt calls
- `password_changeset`, `confirm_changeset` from `User` schema

### Added to `Accounts` context

- `build_magic_link_token/1` — generates a `{encoded_token, user_token_record}` pair with `"magic_link"` context
- `verify_magic_link_token_query/1` — verifies and single-use-invalidates the token
- `find_or_create_user_from_oauth/2` — upserts user by email, inserts `UserIdentity` if new
- `deliver_magic_link_email/2` in `UserNotifier` — new email template

### Added to `UserSessionController`

- `GET /users/magic_link/:token` — magic link verification and session creation
- `GET /auth/:provider` — Assent OAuth initiation
- `GET /auth/:provider/callback` — Assent OAuth callback handling

All new routes are controller-based (not LiveViews) — they handle a token exchange or redirect immediately.

## UI

### Login/signup page (`/users/log_in`)

Single unified page replacing the separate login and registration screens:

- Email input + "Send magic link" primary button
- "Continue with Google", "Continue with Microsoft", "Continue with GitHub" OAuth buttons
- After email submission: replace form with confirmation message — "Check your email — we sent a link to `alice@example.com`." No indication of whether the account existed
- No password field, no "confirm password", no "forgot password"

### Magic link email

Plain and functional: app name, CTA button, note that the link expires in 15 minutes.

### Settings page

Remove the password change section. Add a "Connected accounts" section showing linked OAuth providers, each with a "Disconnect" button. Since magic link via email is always available as a login fallback, there is no risk of lockout — Disconnect is never disabled. Users can remove all OAuth providers and still log in via magic link.

### Dev backdoor (`/dev/login`)

Unstyled or minimally styled. Lists existing users as clickable login links plus a freeform email input for any address.

## Routing

### Removed

| Method | Path |
|--------|------|
| GET/POST | `/users/register` |
| GET/POST | `/users/reset_password` |
| GET/PUT | `/users/reset_password/:token` |
| GET | `/users/confirm` |
| GET | `/users/confirm/:token` |

### Changed

| Method | Path | Change |
|--------|------|--------|
| GET/POST | `/users/log_in` | Becomes unified magic link + OAuth login/signup page |

### Added

| Method | Path | Scope |
|--------|------|-------|
| GET | `/users/magic_link/:token` | Browser (unauthenticated) |
| GET | `/auth/:provider` | Browser (with or without auth — dual-purpose) |
| GET | `/auth/:provider/callback` | Browser (with or without auth — dual-purpose) |
| GET | `/dev/login` | Dev only |
| POST | `/dev/login` | Dev only |

## Dependencies

| Package | Change |
|---------|--------|
| `bcrypt_elixir` | Remove |
| `assent` | Add |

## Migrations

1. Remove `hashed_password` and `confirmed_at` columns from `users`
2. Create `user_identities` table with unique index on `{provider, uid}`
3. Update seeds to create admin user without password

## Security Considerations

- Magic link tokens are single-use and expire in 15 minutes
- No email enumeration: the "check your email" response is shown regardless of whether the account existed
- OAuth identity is keyed on `{provider, uid}`, not solely on email, to prevent provider-spoofing attacks
- Dev backdoor is strictly dev-only, never compiled into production
- Rate limiting on magic link sends is a post-launch consideration (Plug.RateLimit or similar)
