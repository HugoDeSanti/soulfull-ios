// store-apple-token
//
// Authenticated Edge Function. Called by the app immediately after a
// successful Sign in with Apple. Given the `{ authorization_code }` that
// `ASAuthorizationAppleIDCredential` handed the client, it:
//   1. identifies the caller from their Supabase JWT,
//   2. confirms they actually signed in with Apple,
//   3. exchanges the code with Apple for a long-lived refresh token,
//   4. checks the token really belongs to this user,
//   5. stores it in `apple_credentials`, readable only by the service role.
//
// `delete-account` later feeds that refresh token to Apple's `/auth/revoke`,
// which is what App Store Guideline 5.1.1(v) requires of any app that offers
// both Sign in with Apple and account deletion. See ../_shared/apple.ts.
//
// This runs on EVERY Apple sign-in, not just the first. Apple mints a new
// authorization code each time, so re-running simply refreshes what we hold —
// which is how an account that predates this function (or that missed the call
// once) heals itself.
//
// Deploy:  supabase functions deploy store-apple-token   (keep JWT verification ON — the default)
// Secrets: APPLE_TEAM_ID, APPLE_KEY_ID, APPLE_PRIVATE_KEY, APPLE_CLIENT_ID
//          (SUPABASE_URL / SUPABASE_ANON_KEY / SUPABASE_SERVICE_ROLE_KEY are auto-injected.)

import { createClient } from "jsr:@supabase/supabase-js@2";
import { appleConfig, exchangeAuthorizationCode } from "../_shared/apple.ts";

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
    const config = appleConfig();
    if (!config) {
      // Nothing is configured yet. Say so plainly rather than pretending to
      // have stored something — the client logs this, and a reviewer deleting
      // an account would otherwise get a silent non-revocation.
      console.error("[store-apple-token] Apple secrets are not set; cannot store a refresh token.");
      return json({ error: "Sign in with Apple is not configured on this project." }, 501);
    }

    const authHeader = req.headers.get("Authorization");
    if (!authHeader) return json({ error: "Missing Authorization header" }, 401);

    const authClient = createClient(SUPABASE_URL, ANON_KEY, {
      global: { headers: { Authorization: authHeader } },
    });
    const { data: { user }, error: userErr } = await authClient.auth.getUser();
    if (userErr || !user) return json({ error: "Not authenticated" }, 401);
    if (user.is_anonymous) {
      return json({ error: "A guest session has no Apple identity to store." }, 403);
    }

    // Only an account that actually carries an Apple identity has anything to
    // revoke. This also stops an email/password caller parking someone else's
    // token on their own row.
    const appleIdentity = user.identities?.find((i) => i.provider === "apple");
    if (!appleIdentity) {
      return json({ error: "This account did not sign in with Apple." }, 403);
    }

    const body = await req.json().catch(() => null) as { authorization_code?: string } | null;
    const code = body?.authorization_code?.trim();
    if (!code) return json({ error: "Missing authorization_code" }, 400);

    const { refreshToken, appleSub } = await exchangeAuthorizationCode(config, code);

    // The code is single-use and short-lived, but it still travels through the
    // client. Confirm Apple's answer describes THIS user before storing it —
    // otherwise a replayed code would bolt someone else's Apple grant to this
    // account, and deleting this account would revoke that stranger's.
    const expectedSub =
      (appleIdentity.identity_data?.sub as string | undefined) ?? appleIdentity.id;
    if (appleSub && expectedSub && appleSub !== expectedSub) {
      console.error("[store-apple-token] Apple subject mismatch; refusing to store.");
      return json({ error: "That authorization code belongs to a different Apple ID." }, 403);
    }

    const admin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);
    const { error: upsertErr } = await admin
      .from("apple_credentials")
      .upsert(
        { user_id: user.id, refresh_token: refreshToken, updated_at: new Date().toISOString() },
        { onConflict: "user_id" },
      );

    if (upsertErr) {
      console.error("[store-apple-token] upsert failed", upsertErr);
      return json({ error: "Couldn't store the Apple token." }, 500);
    }

    return json({ stored: true });
  } catch (e) {
    // Never echo the exception to the client: it can carry Apple's raw error
    // body. The log keeps it; the caller gets a shape it can decode.
    console.error("[store-apple-token]", e);
    return json({ error: "Couldn't store the Apple token." }, 500);
  }
});
