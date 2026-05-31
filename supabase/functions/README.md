# Supabase Edge Functions — Phase 2 (Stripe payments)

Two functions back retreat reservations:

| Function | Auth | Purpose |
|---|---|---|
| `create-payment-intent` | Caller's Supabase JWT | Reads the authoritative retreat price, reuses/creates the Stripe customer, returns a PaymentIntent client secret + ephemeral key for the iOS PaymentSheet. |
| `stripe-webhook` | Stripe signature (no Supabase JWT) | On `payment_intent.succeeded` / `…payment_failed`, writes a row to `bookings` with the service role. The only writer of payment state. |

## One-time setup

1. **Apply the migration** `supabase/migrations/0002_bookings.sql` (SQL Editor or `supabase db push`).

2. **Set function secrets** (Stripe keys live only here — the app never stores them):
   ```bash
   supabase secrets set STRIPE_API_KEY=rk_test_...           # RESTRICTED key (see below), not sk_
   supabase secrets set STRIPE_PUBLISHABLE_KEY=pk_test_...
   supabase secrets set STRIPE_WEBHOOK_SECRET=whsec_...      # from the webhook endpoint you create in step 4
   ```
   `SUPABASE_URL`, `SUPABASE_ANON_KEY`, and `SUPABASE_SERVICE_ROLE_KEY` are injected automatically.

   **Use a [restricted API key](https://docs.stripe.com/keys/restricted-api-keys) (`rk_…`), not a secret key**, following least privilege. Minimum permissions:
   - `create-payment-intent`: **Customers** = Write, **PaymentIntents** = Write (covers ephemeral keys).
   - `stripe-webhook`: no resource permissions needed (it only verifies signatures locally) — a key with no write scopes is fine; it still needs `STRIPE_WEBHOOK_SECRET`.

   Use separate keys per environment (test/live), and ideally add an IP allowlist to each key.

3. **Deploy:**
   ```bash
   supabase functions deploy create-payment-intent
   supabase functions deploy stripe-webhook --no-verify-jwt   # Stripe sends its own signature, not a Supabase JWT
   ```

4. **Create the Stripe webhook endpoint** (Stripe dashboard → Developers → Webhooks):
   - URL: `https://<project-ref>.functions.supabase.co/stripe-webhook`
   - Events: `payment_intent.succeeded`, `payment_intent.payment_failed`
   - Copy its signing secret into `STRIPE_WEBHOOK_SECRET` (step 2) and redeploy if you set it after deploying.

## API versions

- **Ephemeral key:** the iOS app sends its `STPAPIClient.apiVersion` in the request body and the function mints the key with exactly that — so there's **nothing to keep in sync** when you upgrade `stripe-ios`. (A `FALLBACK_API_VERSION` constant covers a client that omits it.)
- **Server calls** (customer / PaymentIntent create) use the **account's default API version** — keep it current in the Stripe dashboard. The Stripe Node SDK pin (`npm:stripe@17`) can be bumped any time; our API usage is stable across majors.

## Testing

Use Stripe **test mode** keys and the test card `4242 4242 4242 4242` (any future expiry / any CVC / any ZIP). More scenarios via the plugin's `/stripe:test-cards`. Watch logs with `supabase functions logs stripe-webhook`.
