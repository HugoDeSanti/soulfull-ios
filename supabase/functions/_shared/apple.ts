// _shared/apple.ts
//
// Sign in with Apple server-side token handling, shared by `store-apple-token`
// (exchange an authorization code for a refresh token) and `delete-account`
// (revoke that refresh token).
//
// WHY THIS EXISTS — App Store Guideline 5.1.1(v):
//
//   "If your app offers Sign in with Apple, you must use the Sign in with Apple
//    REST API to revoke the user tokens when the account is deleted."
//
// Deleting the Supabase auth user is NOT enough. Until `/auth/revoke` is
// called, the app keeps appearing under Settings -> Apple ID -> Sign in with
// Apple on the user's device — which is exactly what a reviewer checks. This
// is a documented rejection reason, not a nicety.
//
// Both calls need a "client secret": a short-lived ES256 JWT signed with a
// Sign in with Apple private key (.p8) from the Apple Developer portal. We mint
// one per request rather than caching a long-lived secret.
//
// Secrets (set with `supabase secrets set …`):
//   APPLE_TEAM_ID      Apple Developer Team ID, e.g. W346837424       (JWT `iss`)
//   APPLE_KEY_ID       Key ID of the Sign in with Apple .p8 key       (JWT `kid`)
//   APPLE_PRIVATE_KEY  The .p8 file's contents, PKCS#8 PEM. Literal "\n"
//                      escapes are accepted, since shells mangle real newlines.
//   APPLE_CLIENT_ID    The app's BUNDLE ID, com.soulfullgatherings.app (JWT `sub`)
//
// Note APPLE_CLIENT_ID is the bundle ID, not a Services ID. This app uses the
// NATIVE Sign in with Apple flow only (ASAuthorizationAppleIDProvider ->
// Supabase signInWithIdToken); there is no web OAuth flow anywhere in it, which
// is also why the Supabase Apple provider's "Secret Key" field is left blank.
// A Services ID would be the right `sub` only for the web flow.

import * as jose from "npm:jose@5";

const APPLE_ISSUER = "https://appleid.apple.com";
const TOKEN_URL = `${APPLE_ISSUER}/auth/token`;
const REVOKE_URL = `${APPLE_ISSUER}/auth/revoke`;

export interface AppleConfig {
  teamId: string;
  keyId: string;
  privateKey: string;
  clientId: string;
}

/** Thrown when the Apple secrets are absent or Apple rejects a call. */
export class AppleError extends Error {}

/**
 * Reads the four Apple secrets. Returns `null` (rather than throwing) when
 * none of them are set, so a project that has not configured Sign in with
 * Apple yet still deploys and runs — callers decide whether that is fatal.
 * A PARTIAL configuration is always an error: it means someone set some of
 * them and believes revocation works when it does not.
 */
export function appleConfig(): AppleConfig | null {
  const teamId = Deno.env.get("APPLE_TEAM_ID");
  const keyId = Deno.env.get("APPLE_KEY_ID");
  const privateKey = Deno.env.get("APPLE_PRIVATE_KEY");
  const clientId = Deno.env.get("APPLE_CLIENT_ID");

  const present = [teamId, keyId, privateKey, clientId].filter(Boolean).length;
  if (present === 0) return null;
  if (present < 4) {
    throw new AppleError(
      "Apple secrets are partially configured. Set all of APPLE_TEAM_ID, " +
        "APPLE_KEY_ID, APPLE_PRIVATE_KEY and APPLE_CLIENT_ID, or none.",
    );
  }
  return { teamId: teamId!, keyId: keyId!, privateKey: privateKey!, clientId: clientId! };
}

// Importing a PKCS#8 key costs a few ms; warm instances reuse it.
// Whatever jose hands back on this runtime — avoids pinning CryptoKey vs KeyObject.
type AppleSigningKey = Awaited<ReturnType<typeof jose.importPKCS8>>;

let cachedKey: { pem: string; key: AppleSigningKey } | null = null;

async function signingKey(pem: string): Promise<AppleSigningKey> {
  if (cachedKey?.pem === pem) return cachedKey.key;
  const normalised = normalisePem(pem);
  let key: AppleSigningKey;
  try {
    key = await jose.importPKCS8(normalised, "ES256");
  } catch (e) {
    throw new AppleError(
      `APPLE_PRIVATE_KEY is not a usable PKCS#8 EC key: ${(e as Error).message}. ` +
        "It should be the .p8 file's contents verbatim, including the BEGIN/END lines.",
    );
  }
  cachedKey = { pem, key };
  return key;
}

/**
 * Accepts the three shapes a .p8 arrives in after a trip through a shell and a
 * secrets store: a real multi-line PEM, the same PEM with literal backslash-n
 * instead of newlines, and the bare base64 body with the armour stripped off.
 * Anything else still reaches `importPKCS8` and fails there with a clear error.
 */
function normalisePem(raw: string): string {
  const text = raw.replace(/\\n/g, "\n").trim();
  if (text.includes("-----BEGIN")) return text;
  // Bare base64: re-wrap at 64 columns and put the armour back.
  const body = text.replace(/\s+/g, "");
  const lines = body.match(/.{1,64}/g)?.join("\n") ?? body;
  return `-----BEGIN PRIVATE KEY-----\n${lines}\n-----END PRIVATE KEY-----`;
}

/**
 * Mints the client secret Apple expects in place of a static secret: an ES256
 * JWT issued by the team, subject the client id, audience Apple.
 *
 * Apple permits up to 6 months of life; we use 5 minutes because the secret is
 * minted per request and never stored. A short window means a leaked secret
 * from a log is worthless almost immediately.
 */
async function clientSecret(config: AppleConfig): Promise<string> {
  const key = await signingKey(config.privateKey);
  return await new jose.SignJWT({})
    .setProtectedHeader({ alg: "ES256", kid: config.keyId })
    .setIssuer(config.teamId)
    .setIssuedAt()
    .setExpirationTime("5m")
    .setAudience(APPLE_ISSUER)
    .setSubject(config.clientId)
    .sign(key);
}

async function postForm(url: string, params: Record<string, string>): Promise<Response> {
  return await fetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams(params).toString(),
  });
}

/** The bits of Apple's `/auth/token` response we act on. */
export interface AppleTokens {
  refreshToken: string;
  /** Apple's stable user identifier (`sub` of the returned id_token), if present. */
  appleSub: string | null;
}

/**
 * Exchanges the authorization code the iOS client got from
 * `ASAuthorizationAppleIDCredential` for a long-lived refresh token.
 *
 * The code is SINGLE-USE and expires in about five minutes, so this has to run
 * immediately after sign-in. It is safe to run on every Apple sign-in: Apple
 * issues a fresh code each time, and re-exchanging simply supersedes the
 * stored token.
 */
export async function exchangeAuthorizationCode(
  config: AppleConfig,
  code: string,
): Promise<AppleTokens> {
  // No `redirect_uri`: that parameter belongs to the web flow. For a native
  // app authorization Apple requires it to be absent.
  const res = await postForm(TOKEN_URL, {
    grant_type: "authorization_code",
    code,
    client_id: config.clientId,
    client_secret: await clientSecret(config),
  });

  const raw = await res.text();
  if (!res.ok) {
    // Apple's errors are terse ("invalid_grant", "invalid_client"). Log the
    // body — it never contains the user's tokens, only the failure reason.
    throw new AppleError(`Apple token exchange failed (${res.status}): ${raw}`);
  }

  let body: { refresh_token?: string; id_token?: string };
  try {
    body = JSON.parse(raw);
  } catch {
    throw new AppleError("Apple token exchange returned a non-JSON body.");
  }
  if (!body.refresh_token) {
    throw new AppleError("Apple token exchange returned no refresh_token.");
  }

  return { refreshToken: body.refresh_token, appleSub: subjectOf(body.id_token) };
}

/**
 * Revokes a refresh token, invalidating the app's Sign in with Apple grant.
 * This is the call Guideline 5.1.1(v) is about.
 *
 * Apple answers 200 with an empty body on success — and also for a token that
 * was already revoked, so this is safely idempotent.
 */
export async function revokeRefreshToken(config: AppleConfig, refreshToken: string): Promise<void> {
  const res = await postForm(REVOKE_URL, {
    client_id: config.clientId,
    client_secret: await clientSecret(config),
    token: refreshToken,
    token_type_hint: "refresh_token",
  });
  if (!res.ok) {
    throw new AppleError(`Apple token revocation failed (${res.status}): ${await res.text()}`);
  }
}

/**
 * Reads `sub` out of an Apple id_token WITHOUT verifying its signature.
 *
 * That is deliberate and safe here: this token did not come from a client. It
 * arrived in the TLS response body of a request we made to appleid.apple.com,
 * authenticated with our own client secret. Verifying a signature on a
 * response we just received over an authenticated channel adds a JWKS fetch
 * and no security. (Never reuse this for a token handed in by a client.)
 */
function subjectOf(idToken: string | undefined): string | null {
  if (!idToken) return null;
  try {
    const segment = idToken.split(".")[1];
    if (!segment) return null;
    // base64url -> base64, re-padded. `atob` tolerates missing padding, but
    // being explicit costs nothing and removes the question.
    const b64 = segment.replace(/-/g, "+").replace(/_/g, "/")
      .padEnd(segment.length + ((4 - (segment.length % 4)) % 4), "=");
    const bytes = Uint8Array.from(atob(b64), (c) => c.charCodeAt(0));
    const sub = JSON.parse(new TextDecoder().decode(bytes))?.sub;
    return typeof sub === "string" ? sub : null;
  } catch {
    return null;
  }
}
