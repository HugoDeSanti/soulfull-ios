// delete-account
//
// Permanently deletes the CALLER's own account (App Store Guideline 5.1.1(v):
// apps offering account creation must offer in-app deletion). Identified from
// the caller's JWT — a user can only ever delete themselves.
//
// Steps: best-effort delete the Stripe customer (removes PII + saved payment
// methods; charges remain as immutable financial records) → best-effort revoke
// the user's Sign in with Apple grant → delete the auth user with the service
// role, which cascades to `profiles` + `bookings` + `apple_credentials`.
//
// THE APPLE REVOKE IS NOT OPTIONAL. Guideline 5.1.1(v): an app offering both
// Sign in with Apple and account deletion "must use the Sign in with Apple REST
// API to revoke the user tokens when the account is deleted". Deleting the
// Supabase user does not do that — without the revoke the app keeps appearing
// under Settings → Apple ID → Sign in with Apple, which is what a reviewer
// checks. The refresh token it needs was captured at sign-in by
// `store-apple-token`; see ../_shared/apple.ts for the whole picture.
//
// Deploy:  supabase functions deploy delete-account
//          (keep JWT verification ON — the default — so only authenticated
//           callers reach it.)
// Secrets: STRIPE_API_KEY (already set),
//          APPLE_TEAM_ID / APPLE_KEY_ID / APPLE_PRIVATE_KEY / APPLE_CLIENT_ID.
//          SUPABASE_* are auto-injected.

import Stripe from "npm:stripe@17";
import { createClient } from "jsr:@supabase/supabase-js@2";
import { appleConfig, revokeRefreshToken } from "../_shared/apple.ts";

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

    // Revoke the Sign in with Apple grant (Guideline 5.1.1(v)).
    //
    // Best-effort, deliberately: the user's right to delete their account
    // outranks a third-party outage, and the existing Stripe step already sets
    // that precedent. But unlike Stripe this is a compliance obligation, so a
    // failure is logged loudly and reported back in the response rather than
    // swallowed. Read the token BEFORE deleting the user — the row cascades
    // away with them.
    //
    // `appleRevoked` is null when the account never used Apple (nothing to do).
    let appleRevoked: boolean | null = null;
    const usedApple = user.identities?.some((i) => i.provider === "apple") ?? false;

    if (usedApple) {
      appleRevoked = false;
      try {
        const config = appleConfig();
        if (!config) {
          console.error(
            "[delete-account] Apple secrets are not set — cannot revoke tokens for an " +
              "Apple account. This is a Guideline 5.1.1(v) gap; set APPLE_TEAM_ID, " +
              "APPLE_KEY_ID, APPLE_PRIVATE_KEY and APPLE_CLIENT_ID.",
          );
        } else {
          const { data: cred } = await admin
            .from("apple_credentials")
            .select("refresh_token")
            .eq("user_id", user.id)
            .maybeSingle();
          const refreshToken = cred?.refresh_token as string | null | undefined;

          if (!refreshToken) {
            // An account that signed in with Apple before store-apple-token
            // shipped, or one whose exchange failed every time since. Nothing
            // to revoke with; deletion still proceeds.
            console.error(
              `[delete-account] No stored Apple refresh token for ${user.id}; ` +
                "deleting without revocation.",
            );
          } else {
            await revokeRefreshToken(config, refreshToken);
            appleRevoked = true;
          }
        }
      } catch (e) {
        console.error("[delete-account] Apple revocation failed (continuing):", (e as Error).message);
      }
    }

    // Delete the auth user. This cascades to public.profiles and
    // public.apple_credentials, and ANONYMISES rather than erases
    // public.bookings and public.practice_plays (both are
    // `on delete set null` — see 0009 and 0008): a paid reservation and a
    // creator's earned play both have to survive the member, and RLS hides the
    // orphaned rows from every client because `auth.uid() = NULL` is NULL.
    const { error: delErr } = await admin.auth.admin.deleteUser(user.id);
    if (delErr) {
      console.error("[delete-account] deleteUser failed", delErr);
      return json({ error: "Couldn't delete the account. Please try again." }, 500);
    }

    return json({ deleted: true, apple_revoked: appleRevoked });
  } catch (e) {
    console.error("[delete-account]", e);
    return json({ error: "Couldn't delete the account. Please try again." }, 500);
  }
});
