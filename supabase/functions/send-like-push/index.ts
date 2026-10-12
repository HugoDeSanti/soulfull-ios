// send-like-push
//
// Turns one row of `notifications` into a push to every device the recipient
// has registered. Called by the `notifications_push` database trigger (0017)
// through pg_net — NOT by the app — and deployed with --no-verify-jwt because
// pg_net carries no user session. The `x-webhook-secret` header, matched
// against PUSH_WEBHOOK_SECRET, is what stands in for authentication; the same
// value sits in Vault as `push_webhook_secret`.
//
// The push is a courtesy on top of the in-app bell. Every failure here is
// logged and answered with 200 so pg_net doesn't retry a like into a storm;
// the notification row already exists and the app shows it regardless.
//
// Deploy:  supabase functions deploy send-like-push --no-verify-jwt
// Secrets: PUSH_WEBHOOK_SECRET, plus the four APPLE_* secrets Sign in with
//          Apple already uses (the .p8 must have the APNs service enabled —
//          APPLE_CLIENT_ID, the bundle id, doubles as the apns-topic).

import { createClient } from "jsr:@supabase/supabase-js@2";
import { appleConfig } from "../_shared/apple.ts";
import { type ApnsEnvironment, sendAlert } from "../_shared/apns.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const WEBHOOK_SECRET = Deno.env.get("PUSH_WEBHOOK_SECRET");

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

Deno.serve(async (req) => {
  if (!WEBHOOK_SECRET) {
    console.error("[send-like-push] PUSH_WEBHOOK_SECRET is not set; refusing everything.");
    return json({ error: "not configured" }, 503);
  }
  if (req.headers.get("x-webhook-secret") !== WEBHOOK_SECRET) {
    return json({ error: "forbidden" }, 403);
  }

  let notificationId: string | undefined;
  try {
    notificationId = (await req.json())?.notification_id;
  } catch { /* fall through */ }
  if (!notificationId) return json({ error: "notification_id required" }, 400);

  const admin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);

  // The row itself, from `notifications` — NOT the `member_notifications`
  // view the app reads. That view joins `community_members`, whose guest
  // filter (0029) asks `caller_has_account()` about `auth.uid()`, which is
  // empty under the service role: it filtered as it would for a guest and
  // dropped every liker who hadn't shared a finished practice in the last 30
  // days. Their likes reached the bell and never buzzed.
  const { data: note, error: noteErr } = await admin
    .from("notifications")
    .select("id, user_id, kind, actor_id, play_id")
    .eq("id", notificationId)
    .maybeSingle();
  if (noteErr || !note) {
    console.error("[send-like-push] notification not found:", notificationId, noteErr?.message);
    return json({ sent: 0, reason: "not found" });
  }

  // A block ends the like and its notification both ways (0028's trigger),
  // but one that raced the block must not buzz.
  if (note.actor_id) {
    const { data: blocks } = await admin
      .from("member_blocks")
      .select("blocker_id")
      .or(
        `and(blocker_id.eq.${note.user_id},blocked_id.eq.${note.actor_id}),` +
          `and(blocker_id.eq.${note.actor_id},blocked_id.eq.${note.user_id})`,
      )
      .limit(1);
    if (blocks && blocks.length > 0) return json({ sent: 0, reason: "blocked" });
  }

  // The liker as every member sees them ("Mary Ann S.", or "A member" for an
  // objectionable name): the same `community_display_name()` the views use,
  // from the name's two parts (0033). Deploy only after 0033 is applied: before
  // it, the select fails and every push says "Someone".
  // A deleted account (actor_id null) stays "Someone".
  let actorName: string | null = null;
  if (note.actor_id) {
    const { data: profile } = await admin
      .from("profiles")
      .select("first_name, last_name")
      .eq("id", note.actor_id)
      .maybeSingle();
    if (profile) {
      const { data: shown } = await admin.rpc("community_display_name", {
        first_name: profile.first_name,
        last_name: profile.last_name,
      });
      if (typeof shown === "string") actorName = shown;
    }
  }

  let contentTitle: string | null = null;
  if (note.play_id) {
    const { data: play } = await admin
      .from("practice_plays")
      .select("content_title")
      .eq("id", note.play_id)
      .maybeSingle();
    contentTitle = play?.content_title ?? null;
  }

  const { data: tokens } = await admin
    .from("device_tokens")
    .select("token, environment")
    .eq("user_id", note.user_id);
  if (!tokens || tokens.length === 0) return json({ sent: 0, reason: "no devices" });

  const config = appleConfig();
  if (!config) {
    console.error("[send-like-push] Apple secrets are not set; cannot reach APNs.");
    return json({ sent: 0, reason: "no apple config" });
  }

  const { count: unread } = await admin
    .from("notifications")
    .select("id", { count: "exact", head: true })
    .eq("user_id", note.user_id)
    .is("read_at", null);

  const actor = actorName ?? "Someone";
  const title = `${actor} liked your practice`;
  const body = contentTitle ?? "Open Community to see it.";

  let sent = 0;
  const dead: string[] = [];
  for (const t of tokens) {
    const outcome = await sendAlert(config, config.clientId, t.environment as ApnsEnvironment, t.token, {
      title,
      body,
      badge: unread ?? undefined,
      threadId: "likes",
      data: { kind: note.kind, notification_id: note.id },
    });
    if (outcome.ok) {
      sent++;
    } else {
      console.error(`[send-like-push] APNs refused ${t.token.slice(0, 8)}…: ${outcome.reason}`);
      if (outcome.unregister) dead.push(t.token);
    }
  }
  if (dead.length > 0) {
    await admin.from("device_tokens").delete().in("token", dead);
  }
  return json({ sent, removed: dead.length });
});
