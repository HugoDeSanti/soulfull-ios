// create-payment-intent
//
// Authenticated Edge Function. Given a { retreat_id }, it:
//   1. identifies the caller from their Supabase JWT (must be a permanent account),
//   2. reads the AUTHORITATIVE price from the retreats table (never trusts the client),
//   3. reuses or creates the caller's Stripe customer (stored on profiles.stripe_customer_id),
//   4. returns a PaymentIntent client secret + ephemeral key for Stripe's PaymentSheet.
//
// Deploy:  supabase functions deploy create-payment-intent
// Secrets: STRIPE_API_KEY (use a RESTRICTED key, rk_…, with Customers + PaymentIntents write),
//          STRIPE_PUBLISHABLE_KEY
//          (SUPABASE_URL / SUPABASE_ANON_KEY / SUPABASE_SERVICE_ROLE_KEY are auto-injected.)

import Stripe from "npm:stripe@17";
import { createClient } from "jsr:@supabase/supabase-js@2";

// The ephemeral key must be minted with the SAME API version the Stripe mobile
// SDK pins. The app sends its STPAPIClient.apiVersion in the request body, so we
// use that and never have to keep a server constant in sync. This fallback only
// applies if an (older) client omits it.
const FALLBACK_API_VERSION = "2024-06-20";

// No constructor apiVersion: server-side calls (customer/PaymentIntent create)
// use the account's default version, which the user keeps current in the
// dashboard. Only the ephemeral key is version-pinned, to the client's value.
const stripe = new Stripe(Deno.env.get("STRIPE_API_KEY")!, {
  httpClient: Stripe.createFetchHttpClient(),
});

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, "Content-Type": "application/json" },
  });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });

  try {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) return json({ error: "Missing Authorization header" }, 401);

    // Identify the caller from their JWT.
    const authClient = createClient(SUPABASE_URL, ANON_KEY, {
      global: { headers: { Authorization: authHeader } },
    });
    const { data: { user }, error: userErr } = await authClient.auth.getUser();
    if (userErr || !user) return json({ error: "Not authenticated" }, 401);
    if (user.is_anonymous) return json({ error: "A permanent account is required to reserve." }, 403);

    const { retreat_id, stripe_api_version } = await req.json().catch(() => ({}));
    if (retreat_id === undefined || retreat_id === null) {
      return json({ error: "Missing retreat_id" }, 400);
    }
    const ephemeralKeyApiVersion = stripe_api_version || FALLBACK_API_VERSION;

    const admin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);

    // Authoritative price + name from the DB.
    const { data: retreat, error: rErr } = await admin
      .from("retreats")
      .select("id, name, price_usd")
      .eq("id", retreat_id)
      .single();
    if (rErr || !retreat) return json({ error: "Retreat not found" }, 404);

    const amount = Math.round(Number(retreat.price_usd) * 100); // dollars → cents
    if (!Number.isFinite(amount) || amount <= 0) {
      return json({ error: "Retreat has no valid price" }, 422);
    }

    // Reuse or create the Stripe customer, stored on the profile.
    const { data: profile } = await admin
      .from("profiles")
      .select("stripe_customer_id, email, full_name")
      .eq("id", user.id)
      .single();

    let customerId = profile?.stripe_customer_id as string | null | undefined;
    if (!customerId) {
      const customer = await stripe.customers.create({
        email: profile?.email ?? user.email ?? undefined,
        name: profile?.full_name ?? undefined,
        metadata: { supabase_user_id: user.id },
      });
      customerId = customer.id;
      await admin.from("profiles").update({ stripe_customer_id: customerId }).eq("id", user.id);
    }

    const ephemeralKey = await stripe.ephemeralKeys.create(
      { customer: customerId },
      { apiVersion: ephemeralKeyApiVersion },
    );

    const paymentIntent = await stripe.paymentIntents.create({
      amount,
      currency: "usd",
      customer: customerId,
      automatic_payment_methods: { enabled: true },
      // Read back by the webhook to write the booking row.
      metadata: {
        user_id: user.id,
        retreat_id: String(retreat.id),
        retreat_name: retreat.name ?? "",
      },
    });

    return json({
      paymentIntentClientSecret: paymentIntent.client_secret,
      ephemeralKeySecret: ephemeralKey.secret,
      customerId,
      publishableKey: Deno.env.get("STRIPE_PUBLISHABLE_KEY"),
      amount,
      currency: "usd",
    });
  } catch (e) {
    console.error("[create-payment-intent]", e);
    return json({ error: (e as Error).message ?? "Unexpected error" }, 500);
  }
});
