// _shared/apns.ts
//
// Sends one alert through Apple Push Notification service, authenticated with
// a provider token (an ES256 JWT signed by an Apple key that has the APNs
// service enabled — here the same .p8 as Sign in with Apple, so the same four
// APPLE_* secrets serve both).
//
// The token is cached and reused for 50 minutes: Apple asks for a refresh at
// least hourly and no more often than every 20 minutes.

import * as jose from "npm:jose@5";
import { type AppleConfig, signingKey } from "./apple.ts";

export type ApnsEnvironment = "sandbox" | "production";

const HOSTS: Record<ApnsEnvironment, string> = {
  sandbox: "https://api.sandbox.push.apple.com",
  production: "https://api.push.apple.com",
};

let cached: { teamId: string; keyId: string; token: string; mintedAt: number } | null = null;

async function providerToken(config: AppleConfig): Promise<string> {
  const now = Date.now();
  if (cached && cached.teamId === config.teamId && cached.keyId === config.keyId &&
      now - cached.mintedAt < 50 * 60 * 1000) {
    return cached.token;
  }
  const key = await signingKey(config.privateKey);
  const token = await new jose.SignJWT({})
    .setProtectedHeader({ alg: "ES256", kid: config.keyId })
    .setIssuer(config.teamId)
    .setIssuedAt()
    .sign(key);
  cached = { teamId: config.teamId, keyId: config.keyId, token, mintedAt: now };
  return token;
}

export interface ApnsAlert {
  title: string;
  body: string;
  /** App icon badge after this notification. */
  badge?: number;
  /** Groups notifications in Notification Center. */
  threadId?: string;
  /** Custom keys the app reads when the notification is tapped. */
  data?: Record<string, unknown>;
}

export type ApnsOutcome =
  | { ok: true }
  /** The token is dead — remove it. */
  | { ok: false; unregister: true; reason: string }
  | { ok: false; unregister: false; reason: string };

/**
 * Posts one alert to one device. `topic` is the app's bundle id.
 *
 * APNs answers 200 with an empty body, or a JSON `{ reason }`. 410 and
 * BadDeviceToken/Unregistered/DeviceTokenNotForTopic mean the token will
 * never work again; everything else is transient or our bug.
 */
export async function sendAlert(
  config: AppleConfig,
  topic: string,
  environment: ApnsEnvironment,
  deviceToken: string,
  alert: ApnsAlert,
): Promise<ApnsOutcome> {
  const payload = {
    aps: {
      alert: { title: alert.title, body: alert.body },
      sound: "default",
      ...(alert.badge !== undefined ? { badge: alert.badge } : {}),
      ...(alert.threadId ? { "thread-id": alert.threadId } : {}),
    },
    ...(alert.data ?? {}),
  };
  const res = await fetch(`${HOSTS[environment]}/3/device/${deviceToken}`, {
    method: "POST",
    headers: {
      authorization: `bearer ${await providerToken(config)}`,
      "apns-topic": topic,
      "apns-push-type": "alert",
      "apns-priority": "10",
      "content-type": "application/json",
    },
    body: JSON.stringify(payload),
  });
  if (res.ok) return { ok: true };
  let reason = `${res.status}`;
  try {
    const body = await res.json();
    if (body?.reason) reason = `${res.status} ${body.reason}`;
  } catch { /* empty body */ }
  const dead = res.status === 410 ||
    /BadDeviceToken|Unregistered|DeviceTokenNotForTopic/.test(reason);
  return { ok: false, unregister: dead, reason };
}
