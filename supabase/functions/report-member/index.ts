// report-member
//
// Files one report about a member and emails it to the team. The server half
// of the app's Report sheet (`Features/Community/ReportMemberSheet.swift`),
// and half of what App Store Guideline 1.2 asks of an app with user-generated
// content: a way to report offensive content and a timely response to it.
// (The other half, Block, is plain RLS — 0028.)
//
// Flow: verify the caller's JWT → refuse a report about yourself or over the
// rate limit → snapshot what was reported (name, photo, the practice line) →
// insert into `member_reports` with the service role (clients have no access
// to that table at all) → email the team. The row is the record; the email is
// the alarm. If the email fails the report still stands, and the function
// still answers 200 — the reporter did their part, and the team's inbox is
// not something they can fix. docs/MODERATION.md is the runbook the email
// links to.
//
// **A guest may report.** Safety isn't gated behind an account: anyone who
// can see the feed can report what's in it. The JWT is still required (an
// anonymous session has one), so this is never an open relay, and guests share
// one hourly allowance (GUEST_HOURLY_LIMIT), because a guest id is free.
//
// **The reported member is never told who reported them**, and nothing in
// this function writes anywhere they can read.
//
// Deploy:  supabase functions deploy report-member
//          (keep JWT verification ON — the default.) Apply 0029 first: this
//          version writes `member_reports.reporter_is_guest`.
// Secrets: RESEND_API_KEY (shared with send-retreat-enquiry), and optionally
//          REPORTS_TO / REPORTS_FROM. SUPABASE_* are auto-injected.

import { createClient } from "jsr:@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const RESEND_API_KEY = Deno.env.get("RESEND_API_KEY");

// The monitored inbox (LegalLinks.supportEmail in the app).
const TO = Deno.env.get("REPORTS_TO") ?? "info@soulfullgatherings.com";
// Any address on the domain verified in Resend.
const FROM = Deno.env.get("REPORTS_FROM") ??
  "Soulfull Gatherings <safety@soulfullgatherings.com>";

/// Reports one reporter may file in a day. Generous for a real person, and a
/// ceiling on how much one session can put in the team's inbox.
const DAILY_LIMIT = 20;

/// Reports all guests together may file in an hour. A guest id costs nothing —
/// a loop of anonymous sign-ins is a new reporter every time — so the limit
/// above put no ceiling at all on what guests could send the team. Members
/// keep their own limit only: an account can't be minted for free. Needs
/// `member_reports.reporter_is_guest` (0029).
const GUEST_HOURLY_LIMIT = 30;

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

/// The reasons, as the app's sheet words them (`ReportReason.title`). Kept in
/// step by hand, like the enquiry questions.
const REASONS = {
  photo: "Inappropriate photo",
  name: "Offensive name",
  harassment: "Harassment or unwanted contact",
  spam: "Spam or a fake account",
  other: "Something else",
} as const;
type Reason = keyof typeof REASONS;

interface Payload {
  reported_id?: string;
  play_id?: string | null;
  reason?: string;
  details?: string | null;
}

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/// "Hugo De Santiago" → "Hugo D." — the name the reporter saw. Mirrors
/// `community_display_name()` closely enough for an email subject; the row
/// keeps the full name.
function shortName(full: string | null): string {
  const words = (full ?? "").trim().split(/\s+/).filter(Boolean);
  if (words.length === 0) return "A member";
  if (words.length === 1) return words[0];
  return `${words[0]} ${words[1][0]}.`;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  try {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) return json({ error: "Missing Authorization header" }, 401);

    const authClient = createClient(SUPABASE_URL, ANON_KEY, {
      global: { headers: { Authorization: authHeader } },
    });
    const { data: { user }, error: userError } = await authClient.auth.getUser();
    if (userError || !user) return json({ error: "Not authenticated" }, 401);

    const body = (await req.json()) as Payload;
    const reportedID = typeof body.reported_id === "string" ? body.reported_id.trim() : "";
    const playID = typeof body.play_id === "string" && UUID.test(body.play_id) ? body.play_id : null;
    const reason = body.reason as Reason;
    const details = typeof body.details === "string" ? body.details.trim().slice(0, 1000) : "";

    if (!UUID.test(reportedID)) return json({ error: "Who is being reported?" }, 400);
    if (!(reason in REASONS)) return json({ error: "Unknown reason" }, 400);
    if (reportedID === user.id) return json({ error: "You can't report yourself" }, 400);

    const admin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
      auth: { persistSession: false },
    });

    const since = new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString();
    const { count, error: countError } = await admin
      .from("member_reports")
      .select("id", { count: "exact", head: true })
      .eq("reporter_id", user.id)
      .gte("created_at", since);
    if (countError) throw countError;
    if ((count ?? 0) >= DAILY_LIMIT) {
      return json({ error: "Too many reports today" }, 429);
    }

    const isGuest = user.is_anonymous === true;
    if (isGuest) {
      const hourAgo = new Date(Date.now() - 60 * 60 * 1000).toISOString();
      const { count: guestCount, error: guestError } = await admin
        .from("member_reports")
        .select("id", { count: "exact", head: true })
        .eq("reporter_is_guest", true)
        .gte("created_at", hourAgo);
      if (guestError) throw guestError;
      if ((guestCount ?? 0) >= GUEST_HOURLY_LIMIT) {
        return json({ error: "Too many reports right now" }, 429);
      }
    }

    // What was reported, as it is right now.
    const { data: reported, error: profileError } = await admin
      .from("profiles")
      .select("full_name, avatar_url, email")
      .eq("id", reportedID)
      .maybeSingle();
    if (profileError) throw profileError;
    if (!reported) return json({ error: "No such member" }, 404);

    let contentTitle: string | null = null;
    if (playID) {
      const { data: play } = await admin
        .from("practice_plays")
        .select("content_title, user_id")
        .eq("id", playID)
        .maybeSingle();
      // Only a line that is actually theirs.
      if (play && play.user_id === reportedID) contentTitle = play.content_title;
    }

    const { data: row, error: insertError } = await admin
      .from("member_reports")
      .insert({
        reporter_id: user.id,
        reporter_is_guest: isGuest,
        reported_id: reportedID,
        play_id: contentTitle ? playID : null,
        reason,
        details: details || null,
        reported_name: reported.full_name,
        reported_avatar_url: reported.avatar_url,
        content_title: contentTitle,
      })
      .select("id")
      .single();
    if (insertError) throw insertError;

    // The alarm. Best-effort: the row above is what counts.
    if (!RESEND_API_KEY) {
      console.error(`RESEND_API_KEY is not set — report ${row.id} filed but nobody was emailed`);
    } else {
      const { data: reporterProfile } = await admin
        .from("profiles")
        .select("full_name")
        .eq("id", user.id)
        .maybeSingle();
      const reporterLine = isGuest
        ? `A guest (not signed in) — ${user.id}`
        : `${reporterProfile?.full_name ?? "A member"} <${user.email ?? "no email"}> — ${user.id}`;
      const photo = reported.avatar_url
        ? `${SUPABASE_URL}/storage/v1/object/public/${reported.avatar_url}`
        : "(no photo)";

      const text = [
        `A member was reported in the Soulfull Gatherings app. Please review it within 24 hours.`,
        ``,
        `Reason: ${REASONS[reason]}`,
        `Note from the reporter: ${details || "(none)"}`,
        ``,
        `Reported member: ${reported.full_name ?? "(no name)"} (shown as "${shortName(reported.full_name)}")`,
        `Member id: ${reportedID}`,
        `Email: ${reported.email ?? "(none)"}`,
        `Photo: ${photo}`,
        contentTitle ? `On their practice: ${contentTitle}` : `Reported from: their profile row`,
        ``,
        `Reported by: ${reporterLine}`,
        `Report id: ${row.id}`,
        ``,
        `What to do next is in docs/MODERATION.md: remove a photo, clear a name, suspend or delete the account, and mark the report actioned or dismissed.`,
      ].join("\n");

      const send = await fetch("https://api.resend.com/emails", {
        method: "POST",
        headers: {
          Authorization: `Bearer ${RESEND_API_KEY}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          from: FROM,
          to: [TO],
          subject: `Member report — ${REASONS[reason]} — ${shortName(reported.full_name)}`,
          text,
        }),
      });
      if (!send.ok) {
        console.error(`Resend rejected report ${row.id} (${send.status}): ${await send.text()}`);
      }
    }

    console.log(`Report ${row.id} filed by ${user.id} about ${reportedID} (${reason})`);
    return json({ reported: true, id: row.id });
  } catch (error) {
    console.error("report-member failed:", error);
    return json({ error: "Could not file the report" }, 500);
  }
});
