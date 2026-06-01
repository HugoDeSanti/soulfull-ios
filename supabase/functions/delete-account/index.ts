// delete-account
//
// Permanently deletes the CALLER's own account (App Store Guideline 5.1.1(v):
// apps offering account creation must offer in-app deletion). Identified from
// the caller's JWT — a user can only ever delete themselves.
//
// Steps: best-effort delete the Stripe customer (removes PII + saved payment
// methods; charges remain as immutable financial records) → delete the auth
// user with the service role, which cascades to `profiles` + `bookings`.
//
// Deploy:  supabase functions deploy delete-account
//          (keep JWT verification ON — the default — so only authenticated
//           callers reach it.)
// Secrets: STRIPE_API_KEY (already set). SUPABASE_* are auto-injected.

import Stripe from "npm:stripe@17";
import { createClient } from "jsr:@supabase/supabase-js@2";

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

    // Identify the caller — they can only delete their own account.
    const authClient = createClient(SUPABASE_URL, ANON_KEY, {
      global: { headers: { Authorization: authHeader } },
    });
    const { data: { user }, error: userErr } = await authClient.auth.getUser();
    if (userErr || !user) return json({ error: "Not authenticated" }, 401);

    const admin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);

    // Best-effort Stripe cleanup. Read the customer id BEFORE deleting the user
    // (the profile row cascades away with it). Don't let a Stripe hiccup block
    // account deletion — compliance requires the delete to succeed.
    const { data: profile } = await admin
      .from("profiles")
      .select("stripe_customer_id")
      .eq("id", user.id)
      .maybeSingle();
    const customerId = profile?.stripe_customer_id as string | null | undefined;
    if (customerId) {
      try {
        await stripe.customers.del(customerId);
      } catch (e) {
        console.error("[delete-account] Stripe customer delete failed (continuing):", (e as Error).message);
      }
    }

    // Delete the auth user — cascades to public.profiles + public.bookings.
    const { error: delErr } = await admin.auth.admin.deleteUser(user.id);
    if (delErr) return json({ error: delErr.message }, 500);

    return json({ deleted: true });
  } catch (e) {
    console.error("[delete-account]", e);
    return json({ error: (e as Error).message ?? "Unexpected error" }, 500);
  }
});
