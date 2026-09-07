# Auth emails

The two HTML files here are the Soulfull-branded versions of the Supabase auth
emails the app can send. They are **not** part of the Xcode build and not applied
by `supabase db push` — see *Applying them* below.

| File | Supabase template | When it fires |
|---|---|---|
| `confirm-email-change.html` | **Change Email Address** | The normal sign-up. `AuthManager.createAccount` upgrades the anonymous guest in place with `auth.update(email:password:)`, which GoTrue treats as an email *change* on an existing user. |
| `confirm-signup.html` | **Confirm signup** | The fallback path — `signUp` when there was no anonymous session to upgrade (e.g. anonymous sign-ins are off, or launch-time auth failed). |

Both are needed because the app can produce either, and the user can't tell the
difference; the copy and design are deliberately identical.

## The sender still says "Supabase Auth" until you set up SMTP

Editing the templates changes the *body* only. The **From** name and address come
from the mail server, and the built-in one Supabase gives every project sends as
`Supabase Auth <noreply@mail.app.supabase.io>` — that string is not editable, on
any plan.

Fixing the sender means switching to custom SMTP:

1. Pick a provider and verify the sending domain (SPF + DKIM on
   `soulfullgatherings.com`). Resend, Postmark, SendGrid and AWS SES all work;
   Resend and Postmark are the least ceremony for this volume.
2. Dashboard → **Project Settings → Authentication → SMTP Settings** →
   *Enable Custom SMTP*, then fill in:
   - **Sender email**: `hello@soulfullgatherings.com` (must be on the verified domain)
   - **Sender name**: `Soulfull Gatherings`
   - host / port / username / password from the provider.
3. Save, then send yourself a test sign-up.

This is not only cosmetic. The built-in service is explicitly **not for
production**: it is rate-limited to a handful of emails per hour across the whole
project and its deliverability is best-effort. A review session — or two people
signing up in the same minute — can exhaust it, and the sign-up then fails with
no email at all. Set custom SMTP before submitting.

## Applying the templates

Either paste them in the dashboard (Authentication → **Emails** → pick the
template → paste the file's contents → Save), or run:

```bash
SUPABASE_ACCESS_TOKEN=sbp_… ./scripts/apply-auth-emails.sh          # apply
SUPABASE_ACCESS_TOKEN=sbp_… ./scripts/apply-auth-emails.sh --dry-run
```

The script PATCHes **only** the four `mailer_*` fields on the project's auth
config. It deliberately avoids `supabase config push`, which pushes the entire
resolved auth config — every setting absent from a local `config.toml` would be
reset to the CLI default, which would (among other things) switch anonymous
sign-ins back off and take the app down.

## Why the code leads and the link is secondary

Both templates put the `{{ .Token }}` code first and the
`{{ .ConfirmationURL }}` link second, labelled as the same-device option.

The link redirects to `soulfull://auth-callback` and completes with PKCE, whose
code verifier lives in **this iPhone's Keychain** — open it on a laptop and the
browser can't even resolve the scheme. Opening it elsewhere does still confirm
the address server-side, but nothing tells the phone; the app now covers that
with `AuthManager.refreshConfirmationState()` (polled while the confirm panel is
up, and once at launch). The code is the path with no such caveat: read it
anywhere, type it into the app, and `verifyOTP` returns a real session.

So keep `{{ .Token }}` in any redesign of these emails. Dropping it puts the app
back to "confirmation only works if you open the email on the phone you signed
up on".

## Template variables

The code's length is the project's **`mailer_otp_length`** (6 on this project; the
dashboard allows 6–10). Nothing in the app or the templates hardcodes it — don't
reintroduce a fixed length in either, so changing the dashboard setting can't
strand users on a field that rejects every real code.

`confirm-signup.html`: `{{ .Token }}`, `{{ .ConfirmationURL }}`, `{{ .Email }}`.
`confirm-email-change.html`: `{{ .Token }}`, `{{ .ConfirmationURL }}`, `{{ .NewEmail }}`
(`{{ .Email }}` is empty for a guest upgrade — the guest had no address).

## Related dashboard settings

- **Authentication → URL Configuration → Redirect URLs** must allow-list
  `soulfull://auth-callback`, or the link won't reopen the app even on the right
  device.
- **Authentication → Providers → Email → Confirm email** decides whether any of
  this runs. With it off, `createAccount` completes immediately and the confirm
  panel is skipped.
