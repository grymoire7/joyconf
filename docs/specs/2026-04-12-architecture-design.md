# Speechwave Architecture Design

**Date:** 2026-04-12

## Overview

This document defines the repository structure, licensing strategy, and tier
limits enforcement model for the Speechwave productization effort. It resolves
the core architectural questions that constrain all subsequent work: where code
lives, how it is governed, and how paid tier limits are enforced in a public
codebase.

---

## GitHub Organization & Repository Structure

A `speechwave-live` GitHub Organization is created. The free GitHub org tier
supports unlimited public repositories — no paid plan is required.

| Repo                         | Visibility | Contents                                   |
| ---------------------------- | ---------- | ------------------------------------------ |
| `speechwave-live/speechwave` | Public     | Phoenix app (renamed from `joyconf`)       |
| `speechwave-live/extension`  | Public     | Chrome extension (extracted from monorepo) |

The Chrome extension is extracted into its own repository because it has an
independent release lifecycle — Chrome Web Store publishes are decoupled from
app deploys. Colocating it in the main repo was acceptable for the MVP but does
not scale once the extension is a published, versioned product.

---

## Licensing

### Phoenix app (`speechwave-live/speechwave`)

Licensed under the **Business Source License 1.1 (BSL 1.1)** with the following
terms:

| Field                | Value                                                                                             |
| -------------------- | ------------------------------------------------------------------------------------------------- |
| Licensor             | Tracy Atteberry                                                                                   |
| Licensed Work        | Speechwave                                                                                        |
| Additional Use Grant | Personal, non-commercial, and development use, including self-hosting for non-commercial purposes |
| Change Date          | Four years from each version's release date                                                       |
| Change License       | Apache License 2.0                                                                                |

In plain terms:

- Anyone may read, fork, and run the code locally or self-host it for
  non-commercial purposes.
- Commercial self-hosting (e.g. running a competing hosted service) requires a
  separate license from the licensor.
- The licensor's own hosted instance at speechwave.live is explicitly permitted.
- Each released version automatically converts to Apache 2.0 four years after
  its release date.

The repository includes:

- `LICENSE` — full BSL 1.1 text with the above fields populated
- `LICENSE_FAQ.md` — plain-language explanation of what is and is not permitted,
  following the convention established by HashiCorp, Sentry, and similar projects

### Chrome extension (`speechwave-live/extension`)

Licensed under **MIT**. The extension has no monetization surface, MIT is the
conventional license for browser extensions, and it simplifies Chrome Web Store
submission.

---

## Tier Limits Enforcement

Limits are enforced in application logic based on a `plan` field on the user
record — not environment variables. Three plans are defined: `free`, `pro`, and
`org`.

### Plan definitions

A dedicated `Speechwave.Plans` module defines limits for each plan as
pattern-matched constants:

```elixir
defmodule Speechwave.Plans do
  def limit(:max_participants, :free), do: 50
  def limit(:full_sessions_per_month, :free), do: 10  # "full" = session duration > 10 minutes
  def limit(:max_participants, :pro), do: :unlimited
  def limit(:full_sessions_per_month, :pro), do: :unlimited
  # org inherits pro limits
  def limit(feature, :org), do: limit(feature, :pro)
end
```

### Enforcement points

Limit checks occur at well-defined points in the request lifecycle — before a
session starts and when a participant joins. The check returns `:ok` or
`{:error, :limit_reached}`. LiveViews and channels handle those return values
and surface appropriate UI (a clear message, not a silent failure).

### Self-hosting friction

A self-hoster wishing to remove limits must locate and modify `Speechwave.Plans`
— meaningful friction that requires understanding the codebase. This is
intentional. The BSL Additional Use Grant permits non-commercial self-hosting
with modifications; the design simply does not advertise or trivialize it. Limits
are not exposed as environment variables.

### Billing integration

The `pro` and `org` plans are wired into enforcement logic from the start but
gated behind "coming soon" UI. When Stripe is integrated, it writes to the
`plan` field on the user record. The enforcement layer requires no changes at
that point.

---

## Deployment

No changes to the deployment model for this phase. The Phoenix app continues to
run on Fly.io with a managed PostgreSQL database. The Fly.io app will be
renamed as part of the subsequent renaming/rebranding phase.

---

## Out of Scope

The following are explicitly deferred and will be addressed in subsequent design
phases:

- Renaming (`joyconf` → `speechwave`) — source, config, and Fly.io changes
- User authentication and registration (`mix phx.gen.auth`)
- User roles and permissions (speaker, event organizer)
- Event and Organization models
- Billing and payment integration (Stripe)
- Pro and Organization tier feature implementations
- Chrome extension Chrome Web Store publication
