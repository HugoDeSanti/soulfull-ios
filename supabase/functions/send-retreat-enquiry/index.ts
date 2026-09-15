// send-retreat-enquiry
//
// Emails one retreat application to the team's monitored inbox.
//
// This is the server half of `Features/Retreats/Enquiry/` in the app: the
// guest answers the "Join a retreat" questions in `RetreatEnquiryView`, the app
// POSTs the answers here, and this function renders and sends the email. It
// replaced a hand-off to the iPhone's Mail app on 2026-09-14 — that only worked
// on a device with Mail configured, and made delivery depend on whether the
// applicant actually tapped Send in a composer they could edit or abandon.
//
// **The applicant's email address is taken from the JWT, never from the body.**
// It is the address of the account they are signed in to, which is exactly what
// the app shows them in the (locked) Email field, and taking it from the token
// means a modified client cannot put someone else's address on an application.
// That is also why the endpoint keeps JWT verification on: an unauthenticated
// version of this is an open relay into the team's inbox.
//
// **One renderer.** The email body is composed here and nowhere else. The Swift
// side owns the *question text the form shows* (`RetreatEnquiry.Question`); the
// labels below are the same strings so the team reads an application in the
// words it was asked in. If a question changes, change it in both — there is no
// build-time link between them, and a mismatch is invisible until someone reads
// an email that doesn't match the form.
//
// Deploy:  supabase functions deploy send-retreat-enquiry
//          (keep JWT verification ON — the default.)
// Secrets: RESEND_API_KEY, and optionally ENQUIRY_FROM / ENQUIRY_TO.
//          SUPABASE_* are auto-injected.

import { createClient } from "jsr:@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
const RESEND_API_KEY = Deno.env.get("RESEND_API_KEY");

// The monitored inbox — same address the app shows on the form and the three
// published legal pages give for support. Overridable so a staging deploy can
// point somewhere else without a code change.
const TO = Deno.env.get("ENQUIRY_TO") ?? "info@soulfullgatherings.com";
// Must be a domain verified in Resend, or every send is rejected. The applicant
// goes in Reply-To, so hitting reply in the inbox still reaches them.
const FROM = Deno.env.get("ENQUIRY_FROM") ??
  "Soulfull Gatherings <applications@soulfullgatherings.com>";

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

/// The questions, in the order the website's form asks them. Kept in step with
/// `RetreatEnquiry.Question` in the app by hand — see the header note.
const QUESTIONS = {
  name: "Name",
  dateOfBirth: "Date of Birth",
  basedIn: "Where are you based?",
  phone: "Phone",
  instagram: "Instagram",
  retreat: "What retreat are you interested in attending?",
  about: "A little about you and why this retreat called you in.",
  decision: "Where are you in your decision?",
  email: "Email",
  investment:
    "What's the investment you usually allocate when selecting an all-inclusive experience abroad, considering being around people just like you?",
  referral: "Do you know a past member of Soulfull Gatherings? If so, who?",
} as const;

interface Payload {
  first_name?: string;
  last_name?: string;
  date_of_birth?: string;
  based_in?: string;
  phone?: string;
  instagram?: string;
  retreat?: string;
  about?: string;
  decision?: string;
  investment?: string;
  referral?: string;
}

/// Trim and cap. The cap is not validation so much as a blast radius: a
/// modified client shouldn't be able to post a megabyte into someone's inbox.
/// `about` is a free-text paragraph and gets the generous limit.
function clean(value: unknown, max = 200): string {
  return typeof value === "string" ? value.trim().slice(0, max) : "";
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  try {
    if (!RESEND_API_KEY) {
      // Loud, and a 5xx so the app offers a retry rather than telling the
      // applicant they got something wrong.
      console.error("RESEND_API_KEY is not set — no application can be sent");
      return json({ error: "Email is not configured" }, 500);
    }

    const authHeader = req.headers.get("Authorization");
    if (!authHeader) return json({ error: "Missing Authorization header" }, 401);

    // Who is applying. The address on the application is this one, always.
    const authClient = createClient(SUPABASE_URL, ANON_KEY, {
      global: { headers: { Authorization: authHeader } },
    });
    const { data: { user }, error: userError } = await authClient.auth.getUser();
    if (userError || !user) return json({ error: "Not authenticated" }, 401);

    // An anonymous guest has no address to reply to, and the app gates the
    // form on a real account precisely so this can't happen.
    if (user.is_anonymous || !user.email) {
      return json({ error: "An account is required to apply" }, 403);
    }

    const body = (await req.json()) as Payload;

    const answers = {
      firstName: clean(body.first_name, 80),
      lastName: clean(body.last_name, 80),
      dateOfBirth: clean(body.date_of_birth, 10),
      basedIn: clean(body.based_in, 120),
      phone: clean(body.phone, 40),
      instagram: clean(body.instagram, 80),
      retreat: clean(body.retreat, 160),
      about: clean(body.about, 4000),
      decision: clean(body.decision, 120),
      investment: clean(body.investment, 40),
      referral: clean(body.referral, 120),
    };

    // Everything the website marks required. `instagram` and `referral` are
    // optional there and optional here.
    const missing = (["firstName", "lastName", "dateOfBirth", "basedIn", "phone",
      "retreat", "about", "decision", "investment"] as const)
      .filter((key) => answers[key].length === 0);
    if (missing.length > 0) {
      return json({ error: "Incomplete application", missing }, 400);
    }

    const fullName = `${answers.firstName} ${answers.lastName}`;
    const block = (question: string, answer: string) => `${question}\n${answer}`;

    const blocks = [
      block(QUESTIONS.name, fullName),
      block(QUESTIONS.dateOfBirth, answers.dateOfBirth),
      block(QUESTIONS.basedIn, answers.basedIn),
      block(QUESTIONS.phone, answers.phone),
    ];
    if (answers.instagram) blocks.push(block(QUESTIONS.instagram, answers.instagram));
    blocks.push(
      block(QUESTIONS.retreat, answers.retreat),
      block(QUESTIONS.about, answers.about),
      block(QUESTIONS.decision, answers.decision),
      block(QUESTIONS.email, user.email),
      block(QUESTIONS.investment, answers.investment),
    );
    if (answers.referral) blocks.push(block(QUESTIONS.referral, answers.referral));

    const text = [
      "A new retreat application, sent from the Soulfull Gatherings iOS app.",
      "",
      blocks.join("\n\n"),
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
        // So replying in the inbox reaches the applicant directly.
        reply_to: user.email,
        subject: `Retreats Application — ${fullName} — ${answers.retreat}`,
        text,
      }),
    });

    if (!send.ok) {
      const detail = await send.text();
      console.error(`Resend rejected the application email (${send.status}): ${detail}`);
      // Deliberately vague to the client: the applicant can't act on Resend's
      // reason, and a retry is the only useful next step.
      return json({ error: "Could not send the application" }, 502);
    }

    const { id } = await send.json() as { id?: string };
    console.log(`Retreat application sent for ${user.id} (message ${id ?? "?"})`);
    return json({ sent: true, id: id ?? null });
  } catch (error) {
    console.error("send-retreat-enquiry failed:", error);
    return json({ error: "Could not send the application" }, 500);
  }
});
