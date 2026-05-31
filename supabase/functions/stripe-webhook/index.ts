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

async function upsertBooking(pi: Stripe.PaymentIntent, status: string) {
  const userId = pi.metadata?.user_id;
  const retreatId = pi.metadata?.retreat_id;
  if (!userId || !retreatId) {
    console.error("[stripe-webhook] PaymentIntent missing metadata", pi.id);
    return;
  }
  const { error } = await admin.from("bookings").upsert(
    {
      user_id: userId,
      retreat_id: Number(retreatId),
      amount_usd: Math.round((pi.amount_received || pi.amount) / 100),
      currency: pi.currency,
      status,
      stripe_payment_intent_id: pi.id,
    },
    { onConflict: "stripe_payment_intent_id" },
  );
  if (error) console.error("[stripe-webhook] booking upsert failed", error);
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
