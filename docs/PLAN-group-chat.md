# Future Plan — Per-Retreat Group Chat

**Status:** Parked / superseded for now. The cohort "group chat" ships as an **external WhatsApp group link**, not an in-app chat. The experience hub's group tile opens `RetreatExperience.PostBooking.groupChatURL` (a WhatsApp invite). This document is kept so we can build a native in-app chat later if we decide to bring the conversation in-house.

## Goal (if built in-app)

A live chat **per retreat**, visible only to members with a **paid booking** for that retreat. Anonymous guests and non-purchasers are excluded.

## Recommended mechanism — Supabase Realtime

Natural fit: the backend is already Supabase. No third-party chat SDK.

### Database
- **`retreat_messages`** — `id`, `retreat_id` (fk), `user_id` (fk → `auth.users`), `body`, `created_at`. Index on `(retreat_id, created_at)`.
- **RLS** — read/insert gated on a paid booking:
  ```sql
  exists (
    select 1 from bookings b
    where b.retreat_id = retreat_messages.retreat_id
      and b.user_id   = auth.uid()
      and b.status    = 'paid'
  )
  ```
  So only paying members can read or post; insert policy also forces `user_id = auth.uid()`.
- Enable **Realtime replication** on the table.

### Client (iOS)
- `RetreatChatView` + `RetreatChatViewModel` (`@Observable`):
  - Load recent messages (paginated, newest-last).
  - Subscribe to Realtime inserts for the retreat → live append.
  - Send = insert; optimistic local echo, reconciled with the Realtime echo (dedupe on a client-generated id or matched insert).
  - Sender name/initials resolved from `profiles.full_name`.
- Entry point: replace the hub's WhatsApp tile with an in-app destination.

### Edge cases
- Optimistic-vs-Realtime echo dedupe.
- Scrollback pagination.
- Send-failure retry.
- RLS-deny for non-members / anonymous (gate the entry on `auth.hasAccount` + a paid booking).

### Incremental later
- Typing indicators / online presence (Realtime Presence).
- Unread counts & a badge.
- Image messages (Supabase Storage).
- Moderation: report/block, basic profanity filter.

## Complexity

**Medium.** Supabase Realtime does the heavy lifting: ~1 migration (table + RLS + realtime) + one VM with a Realtime subscription + a chat UI. Presence/unread/media/moderation are additive. No new infrastructure.

## Why WhatsApp first
- Zero backend/build cost; members already live in WhatsApp.
- Lets us validate that cohorts actually want a group channel before investing in native chat, moderation, and notifications.
- Trade-off: the conversation lives outside the app (no in-app notifications, no membership-gating beyond the invite link, no moderation surface).

## Touch points (if/when built)
- `supabase/migrations/` (new migration: table + RLS + realtime — the dir is empty since 2026-09-07; earlier SQL is at `git show d20e3f6:supabase/migrations/`)
- `SoulfullGatherings/Features/Retreats/PostPurchase/` (new `RetreatChatView` + VM)
- `RetreatExperience.PostBooking.groupChatURL` → currently the WhatsApp link; would become an in-app route.
