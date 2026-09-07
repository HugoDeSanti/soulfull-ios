// stripe-webhook
//
// Receives Stripe webhook events, verifies the signature, and writes booking
// rows with the service role (bypassing RLS). This is the ONLY writer of
// payment state — the app never inserts bookings.
//
// Deploy (must skip Supabase JWT verification — Stripe sends its own signature):
//   supabase functions deploy stripe-webhook --no-verify-jwt
// Secrets: STRIPE_API_KEY (restricted key, rk_…), STRIPE_WEBHOOK_SECRET
//   (set STRIPE_WEBHOOK_SECRET to the signing secret from the Stripe dashboard
//    webhook endpoint pointing at this function's URL).
//
// Subscribe the endpoint to: payment_intent.succeeded, payment_intent.payment_failed.

import Stripe from "npm:stripe@17";
import { createClient } from "jsr:@supabase/supabase-js@2";

// Only used for local signature verification (constructEventAsync) — no API
// calls — so the API version is irrelevant here.
const stripe = new Stripe(Deno.env.get("STRIPE_API_KEY")!, {
  httpClient: Stripe.createFetchHttpClient(),
});
const cryptoProvider = Stripe.createSubtleCryptoProvider();

const WEBHOOK_SECRET = Deno.env.get("STRIPE_WEBHOOK_SECRET")!;
const admin = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
);

// Every failure in here THROWS rather than logging and moving on, and the
// handler below turns that into a non-2xx — which is the only thing that makes
// Stripe redeliver the event.
//
// This used to log and return success. The consequence was the worst failure
// this system has: a transient Postgres error left a CHARGED customer with no
// booking row, Stripe saw 200 and never retried, and on next launch the app's
// `loadExistingBooking` found nothing, reverted the CTA to "Reserve" and
// invited a second charge — because `create-payment-intent`'s already_booked
// guard reads the very row that was never written.
async function upsertBooking(pi: Stripe.PaymentIntent, status: string) {
  const userId = pi.metadata?.user_id;
  const retreatId = pi.metadata?.retreat_id;
  if (!userId || !retreatId) {
    // Not retryable — redelivery won't add metadata — but it must still be
    // loud. A PaymentIntent reaching here without metadata means someone
    // created one outside create-payment-intent.
    throw new Error(`PaymentIntent ${pi.id} has no user_id/retreat_id metadata`);
  }
  const { error } = await admin.from("bookings").upsert(
    {
      user_id: userId,
      retreat_id: Number(retreatId),
      // Stripe's native minor unit. Storing whole dollars (the old
      // `amount_usd`) rounded cents away — see 0009_integrity_hardening.sql.
      amount_cents: pi.amount_received || pi.amount,
      currency: pi.currency,
      status,
      stripe_payment_intent_id: pi.id,
    },
    { onConflict: "stripe_payment_intent_id" },
  );
  if (error) throw new Error(`booking upsert failed for ${pi.id}: ${error.message}`);
}

Deno.serve(async (req) => {
  const signature = req.headers.get("Stripe-Signature");
  const body = await req.text();
  if (!signature) return new Response("Missing Stripe-Signature", { status: 400 });

  let event: Stripe.Event;
  try {
    event = await stripe.webhooks.constructEventAsync(
      body,
      signature,
      WEBHOOK_SECRET,
      undefined,
      cryptoProvider,
    );
  } catch (err) {
    return new Response(`Signature verification failed: ${(err as Error).message}`, { status: 400 });
  }

  try {
    switch (event.type) {
      case "payment_intent.succeeded":
        await upsertBooking(event.data.object as Stripe.PaymentIntent, "paid");
        break;
      case "payment_intent.payment_failed":
        await upsertBooking(event.data.object as Stripe.PaymentIntent, "failed");
        break;
      default:
        break; // ignore other event types
    }
  } catch (e) {
    console.error("[stripe-webhook] handler error", e);
    return new Response("handler error", { status: 500 });
  }

  return new Response(JSON.stringify({ received: true }), {
    headers: { "Content-Type": "application/json" },
  });
});
