# Supabase Edge Functions

| Function | Auth | Purpose |
|---|---|---|
| `create-payment-intent` | Caller's Supabase JWT | Reads the authoritative retreat price, reuses/creates the Stripe customer, returns a PaymentIntent client secret + ephemeral key for the iOS PaymentSheet. |
| `stripe-webhook` | Stripe signature (no Supabase JWT) | On `payment_intent.succeeded` / `…payment_failed`, writes a row to `bookings` with the service role. The only writer of payment state. |
| `delete-account` | Caller's Supabase JWT | Deletes the caller's own account (App Store 5.1.1(v)): best-effort deletes their Stripe customer, **revokes their Sign in with Apple grant**, then deletes the auth user with the service role — cascading to `profiles` + `bookings` + `apple_credentials`. |
| `send-retreat-enquiry` | Caller's Supabase JWT | Emails one retreat application to `info@soulfullgatherings.com` via Resend. The **applicant's address comes from the JWT, never the body** — it is the account's address, which is why the app shows that field locked. |
| `report-member` | Caller's Supabase JWT (a guest's is fine) | Files a member report (Guideline 1.2): stores it in `member_reports` with the service role and emails the team via Resend. Refuses a report about yourself and more than 20 a day. Runbook: `docs/MODERATION.md`. |
| `store-apple-token` | Caller's Supabase JWT | Runs after every Sign in with Apple. Exchanges Apple's single-use authorization code for a refresh token and stores it in `apple_credentials`, so `delete-account` has something to revoke. |

`_shared/apple.ts` holds the Apple client-secret JWT, the token exchange and the
revoke call, used by the last two.

## One-time setup

1. **The `bookings` table already exists** — 0002 was applied to the live project long before the migrations were removed from the repo (2026-09-07). Recreating it elsewhere: `git show d20e3f6:supabase/migrations/0002_bookings.sql`.

   **`apple_credentials` does not** — apply `../migrations/0010_apple_credentials.sql` before deploying `store-apple-token`, or every Apple sign-in will log an upsert failure.

2. **Set function secrets** (Stripe keys live only here — the app never stores them):
   ```bash
   supabase secrets set STRIPE_API_KEY=rk_test_...           # RESTRICTED key (see below), not sk_
   supabase secrets set STRIPE_PUBLISHABLE_KEY=pk_test_...
   supabase secrets set STRIPE_WEBHOOK_SECRET=whsec_...      # from the webhook endpoint you create in step 4
   ```

   And the Sign in with Apple key, which is what makes account deletion able to
   revoke the Apple grant — see [the section below](#sign-in-with-apple-token-revocation-guideline-511v)
   for how to create it:
   ```bash
   supabase secrets set APPLE_TEAM_ID=W346837424
   supabase secrets set APPLE_KEY_ID=ABCD123456                 # the .p8 key's Key ID
   supabase secrets set APPLE_CLIENT_ID=com.soulfullgatherings.app
   supabase secrets set APPLE_PRIVATE_KEY="$(cat AuthKey_ABCD123456.p8)"
   ```

   And the Resend key, which is what lets a retreat application reach the team
   — see [the section below](#retreat-applications-send-retreat-enquiry):
   ```bash
   supabase secrets set RESEND_API_KEY=re_...
   # Optional overrides; the defaults are the ones below.
   supabase secrets set ENQUIRY_TO=info@soulfullgatherings.com
   supabase secrets set ENQUIRY_FROM="Soulfull Gatherings <applications@soulfullgatherings.com>"
   # report-member uses the same RESEND_API_KEY. Optional overrides:
   supabase secrets set REPORTS_TO=info@soulfullgatherings.com
   supabase secrets set REPORTS_FROM="Soulfull Gatherings <safety@soulfullgatherings.com>"
   ```

   `SUPABASE_URL`, `SUPABASE_ANON_KEY`, and `SUPABASE_SERVICE_ROLE_KEY` are injected automatically.

   **Use a [restricted API key](https://docs.stripe.com/keys/restricted-api-keys) (`rk_…`), not a secret key**, following least privilege. Minimum permissions:
   - `create-payment-intent`: **Customers** = Write, **PaymentIntents** = Write, **Ephemeral Keys** = Write (PaymentSheet requires `rak_ephemeral_key_write` — it is a *separate* permission, not implied by Customers).
   - `stripe-webhook`: no resource permissions needed (it only verifies signatures locally) — a key with no write scopes is fine; it still needs `STRIPE_WEBHOOK_SECRET`.

   Use separate keys per environment (test/live), and ideally add an IP allowlist to each key.

3. **Deploy:**
   ```bash
   supabase functions deploy create-payment-intent
   supabase functions deploy stripe-webhook --no-verify-jwt   # Stripe sends its own signature, not a Supabase JWT
   supabase functions deploy delete-account                   # keep JWT verification ON (default)
   supabase functions deploy store-apple-token                # keep JWT verification ON (default)
   supabase functions deploy send-retreat-enquiry             # keep JWT verification ON (default)
   supabase functions deploy report-member                    # keep JWT verification ON (default); needs 0028
   ```

4. **Create the Stripe webhook endpoint** (Stripe dashboard → Developers → Webhooks):
   - URL: `https://<project-ref>.functions.supabase.co/stripe-webhook`
   - Events: `payment_intent.succeeded`, `payment_intent.payment_failed`
   - Copy its signing secret into `STRIPE_WEBHOOK_SECRET` (step 2) and redeploy if you set it after deploying.

## Retreat applications (`send-retreat-enquiry`)

While reservations are off (`AppFeatures.paymentsEnabled == false`), the retreat
CTA reads **"Request a place"** and opens `RetreatEnquiryView` — the same
questions the "Join a retreat" form on soulfullgatherings.com asks. This
function turns the answers into an email to the team.

**Until `RESEND_API_KEY` is set and this is deployed, every application fails.**
The app says so and keeps the answers for a retry, but nothing reaches the
inbox. It is the one piece of this feature that is not self-contained.

### Why Resend rather than the SMTP already configured for auth

The project has custom SMTP set for Supabase Auth's own emails (the branded
confirm/change-email templates). Reusing those credentials here would work and
is tempting, but:

- **SMTP from a serverless function is the fragile option** — connection setup,
  STARTTLS, and timeouts, all inside a request that has to finish fast. Sending
  is one HTTPS POST instead, with no third-party Deno module in the path.
- **Separate concerns want separate credentials.** Rotating the auth SMTP
  password would silently stop retreat applications, and nothing would say so.
- **A transactional API gives you the send back.** Each call returns a message
  id, and bounces and deliverability live in a dashboard; SMTP from a function
  gives you a log line and hope.

### Setup

1. Create a Resend account and **verify `soulfullgatherings.com`** as a sending
   domain (DNS records, added wherever the domain is managed). Until the domain
   verifies, every send is rejected.
2. Create an API key with **Sending access**, restricted to that domain, and
   set it as `RESEND_API_KEY` (step 2 above).

   **Not full access.** This function makes exactly one call —
   `POST /emails` — and never looks up a domain, reads an audience, or
   fetches an email's status afterwards (the message id it logs comes back
   in the send response). Sending access covers all of that. What full
   access adds is blast radius: the key lives in a function secret, and a
   secret's threat model is *someday this leaks*. A full-access key can then
   delete the verified domain, mint new API keys, read contacts and send as
   any domain on the account; a sending key can send email. Both are bad,
   but only one is recoverable by rotating one secret.
3. `ENQUIRY_FROM` must be an address **at that verified domain**
   (`applications@soulfullgatherings.com` by default). It is not the
   applicant's address — theirs goes in `Reply-To`, so hitting reply in the
   inbox reaches them directly.

   ⚠️ **A domain-restricted key and `ENQUIRY_FROM` are one setting in two
   places.** Point `ENQUIRY_FROM` at an address outside the key's domain and
   Resend answers 403, applications start failing, and nothing about the
   failure points at the API key. Change them together.
4. Deploy, then apply for a place from a signed-in build and check the inbox.

### What it will and won't do

- **It validates.** Every question the website marks required must be present,
  and each answer is capped — a modified client shouldn't be able to post a
  megabyte into someone's inbox.
- **It does not store the application.** A send that fails is offered back to
  the applicant as a retry and is otherwise gone. If applications ever matter
  enough to survive a Resend outage — or you want them listed somewhere other
  than an inbox — the shape is a `retreat_enquiries` table written before the
  send, with RLS allowing the owner to insert their own row and nothing else.
- **It does not rate-limit.** JWT verification means only signed-in accounts
  can reach it, which is the bulk of the protection; a per-user throttle needs
  somewhere to count, i.e. the table above.

## Sign in with Apple: token revocation (Guideline 5.1.1(v))

> **This is a submission blocker, not a nicety.** Apple's rule: an app offering
> both Sign in with Apple and account deletion *"must use the Sign in with Apple
> REST API to revoke the user tokens when the account is deleted."* Deleting the
> Supabase auth user does not do that — until `/auth/revoke` is called, the app
> keeps appearing under **Settings → Apple ID → Sign in with Apple** on the
> user's device. A reviewer deletes the demo account and looks there.

**How it works.** Revoking needs a refresh token; the refresh token comes from
exchanging an authorization code; the code expires in ~5 minutes. So the work is
split in two:

1. **At sign-in** — `AppleSignInButton` captures `authorizationCode` alongside
   the identity token, `AuthManager.signInWithApple` posts it to
   `store-apple-token`, which exchanges it with Apple and writes the refresh
   token to `apple_credentials`. Best-effort: a failure here never blocks the
   sign-in, and Apple issues a fresh code on *every* authorization, so the next
   sign-in repairs it.
2. **At deletion** — `delete-account` reads that token (before deleting the
   user, which cascades the row away) and calls `/auth/revoke`. Also
   best-effort: the member's right to delete outranks an Apple outage, so a
   failure is logged loudly and reported as `apple_revoked: false` in the
   response rather than blocking the delete.

### One-time: create the Sign in with Apple key

1. [Apple Developer portal](https://developer.apple.com/account/resources/authkeys/list)
   → **Certificates, Identifiers & Profiles → Keys → +**.
2. Name it (e.g. `Soulfull Sign in with Apple`), tick **Sign in with Apple**,
   press **Configure**, and pick **`com.soulfullgatherings.app`** as the primary
   App ID. Save → Continue → Register.
3. **Download the `.p8`. Apple lets you download it exactly once** — if it is
   lost, revoke the key and make a new one. Note the **Key ID** shown next to it.
4. Set the four `APPLE_*` secrets above. `APPLE_CLIENT_ID` is the **bundle ID**,
   not a Services ID: this app uses the native flow only (which is also why the
   Supabase Apple provider's *Secret Key* field stays blank). A Services ID
   would be right only for a web OAuth flow, and there isn't one.

### Verifying it

The honest end-to-end check needs a real device and a real Apple ID:

1. Sign in with Apple on a clean install.
2. Confirm the row landed — service role only, so from the SQL editor:
   `select user_id, created_at, updated_at from public.apple_credentials;`
   (An anon-key REST probe returns permission denied, by design.)
3. You tab → **Delete account**.
4. On the device: **Settings → your name → Sign-In & Security → Sign in with
   Apple**. *Soulfull* must be **gone** from the list.
5. `supabase functions logs delete-account` should show no revocation error, and
   the response carries `"apple_revoked": true`.

If step 4 still lists the app, the revoke did not happen — check the logs for
`invalid_client` (wrong `APPLE_CLIENT_ID`/`APPLE_KEY_ID`/team, or a key not
configured for this App ID) or `invalid_grant` (the stored token was already
revoked or belongs to another client).

## API versions

- **Ephemeral key:** the iOS app sends its `STPAPIClient.apiVersion` in the request body and the function mints the key with exactly that — so there's **nothing to keep in sync** when you upgrade `stripe-ios`. (A `FALLBACK_API_VERSION` constant covers a client that omits it.)
- **Server calls** (customer / PaymentIntent create) use the **account's default API version** — keep it current in the Stripe dashboard. The Stripe Node SDK pin (`npm:stripe@17`) can be bumped any time; our API usage is stable across majors.

## Testing

Use Stripe **test mode** keys and the test card `4242 4242 4242 4242` (any future expiry / any CVC / any ZIP). More scenarios via the plugin's `/stripe:test-cards`. Watch logs with `supabase functions logs stripe-webhook`.

## Not a function yet: practice-play verification

`practice_plays` (see `../migrations/0008_practice_progress.sql`) is written
**directly by the client**, and it is the record content-creator payouts are
calculated from. The DB trigger bounds what a client can claim — identity
columns are frozen, `seconds_played` only ever increases, and it is clamped to
the practice's own length — so a buggy or replayed client cannot inflate a
payout beyond one full play per row.

It does **not** stop a determined attacker forging plays for a creator they
want to enrich, because the insert is theirs to make. That is an acceptable
trade while creators are a handful of known guides and payouts are reviewed by
hand. It stops being acceptable the moment payouts run automatically at scale.

The fix, when it is needed, is a `record-practice-play` Edge Function that:

1. takes the play over an authenticated call instead of a direct table write
   (revoke `insert`/`update` on `practice_plays` from `authenticated`);
2. cross-checks the claimed seconds against the **Storage access log** for the
   signed URL that was minted for that `storage_path` — a play with no
   corresponding media fetch never happened;
3. writes with the service role.

Until then, before any real payout run, sanity-check the ledger for rows whose
`seconds_played` is implausible against `play_count` and distinct listeners:

```sql
select creator, listeners, hours_played, plays
  from public.practice_creator_earnings
 where month = date_trunc('month', now() - interval '1 month')
 order by hours_played desc;
```


## send-like-push (push notifications for likes)

Called by the database, not the app: the `notifications_push` trigger (0017)
posts `{ "notification_id" }` to it through pg_net whenever a like creates a
notification. It reads the row through `member_notifications`, finds the
recipient's `device_tokens`, and sends one APNs alert per device. Dead tokens
(410 / BadDeviceToken / Unregistered) are deleted; everything else is logged
and answered 200 so pg_net never retries a like into a storm. The in-app bell
is the record; this is the buzz.

```bash
supabase functions deploy send-like-push --no-verify-jwt --project-ref <ref>
supabase secrets set PUSH_WEBHOOK_SECRET=<random> --project-ref <ref>
```

- `--no-verify-jwt` because pg_net carries no user session. The
  `x-webhook-secret` header, matched against `PUSH_WEBHOOK_SECRET`, is the
  authentication. The same value must be in Vault as `push_webhook_secret`,
  next to `push_function_url` (the function's full URL) — both created at
  apply time, never in a migration:
  `select vault.create_secret('<value>', 'push_webhook_secret');`
- APNs auth reuses the four `APPLE_*` secrets Sign in with Apple uses:
  `APPLE_TEAM_ID` (iss), `APPLE_KEY_ID` (kid), `APPLE_PRIVATE_KEY` (the .p8),
  and `APPLE_CLIENT_ID` (the bundle id, which is also the `apns-topic`).
  **The .p8 must have the Apple Push Notifications service enabled** in the
  developer portal (Keys → the key → Edit → tick APNs). Without it APNs answers
  `403 InvalidProviderToken` for every send, the function logs it, and the
  token is kept (it isn't the token's fault). Nothing else needs to change once
  the service is on — the same key id and secret keep working.
- `device_tokens.environment` picks the host: Debug builds on a device register
  `sandbox`, TestFlight / App Store builds `production`. A token sent to the
  wrong host is a BadDeviceToken and gets deleted, which is correct.
- Read the function's output through the Management API logs (see
  `net._http_response` for what it answered the trigger).
