# Auth emails

The HTML files here are the Soulfull-branded versions of the Supabase auth
emails the app can send. They are **not** part of the Xcode build and not applied
by `supabase db push` — see *Applying them* below.

| File | Supabase template | When it fires |
|---|---|---|
| `confirm-email-change.html` | **Change Email Address** | The normal sign-up. `AuthManager.createAccount` upgrades the anonymous guest in place with `auth.update(email:password:)`, which GoTrue treats as an email *change* on an existing user. |
| `confirm-signup.html` | **Confirm signup** | The fallback path — `signUp` when there was no anonymous session to upgrade (e.g. anonymous sign-ins are off, or launch-time auth failed). |
| `reset-password.html` | **Reset Password** | "Forgot password?" on the sign-in sheet (`AuthManager.requestPasswordReset`). Subject: *Reset your password · Soulfull Gatherings*. |

The two confirmation emails are both needed because the app can produce either,
and the user can't tell the difference; their copy and design are deliberately
identical.

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
   - **Sender email**: `info@soulfullgatherings.com` — must be on the verified
     domain, and it should stay in step with `LegalLinks.supportEmail`, because
     replies to a confirmation email land wherever this points.
   - **Sender name**: `Soulfull Gatherings`
   - host / port / username / password from the provider.
3. Save, then send yourself a test sign-up.

This is not only cosmetic. The built-in service is explicitly **not for
production**: it is rate-limited to a handful of emails per hour across the whole
project and its deliverability is best-effort. A review session — or two people
signing up in the same minute — can exhaust it, and the sign-up then fails with
no email at all. Set custom SMTP before submitting.

## Applying the templates

Paste them in the dashboard (Authentication → **Emails** → pick the template →
paste the file's contents → Save).

`scripts/apply-auth-emails.sh` used to do this from the command line; it was
removed on 2026-09-07. To use it again:

```bash
git show d20e3f6:scripts/apply-auth-emails.sh > /tmp/apply-auth-emails.sh
chmod +x /tmp/apply-auth-emails.sh
SUPABASE_ACCESS_TOKEN=sbp_… /tmp/apply-auth-emails.sh --dry-run
```

The script PATCHes **only** the four confirmation `mailer_*` fields on the
project's auth config. It predates `reset-password.html`, which was applied on
2026-10-07 by PATCHing just `mailer_subjects_recovery` and
`mailer_templates_recovery_content` the same way; add those two if you revive it.
It deliberately avoids `supabase config push`, which pushes the entire
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

## Why the reset email has a code and no link

`reset-password.html` deliberately leaves out `{{ .ConfirmationURL }}`. A
confirmation link opened on the wrong device still does its job, because the
address is confirmed server-side and the app notices. A recovery link opened
anywhere but this iPhone does nothing useful: the browser can't open
`soulfull://`, and GoTrue has spent the token on the way, so the code in the
same email stops working too. Mail scanners that prefetch links spend it the
same way. The app finishes a reset only with the typed code (`verifyOTP` with
`type: .recovery`), so there is no recovery deep link to handle and no extra
redirect URL to allow-list. Don't add the link back.

## Template variables

The code's length is the project's **`mailer_otp_length`** (6 on this project; the
dashboard allows 6–10). Nothing in the app or the templates hardcodes it — don't
reintroduce a fixed length in either, so changing the dashboard setting can't
strand users on a field that rejects every real code.

`confirm-signup.html`: `{{ .Token }}`, `{{ .ConfirmationURL }}`, `{{ .Email }}`.
`confirm-email-change.html`: `{{ .Token }}`, `{{ .ConfirmationURL }}`, `{{ .NewEmail }}`
(`{{ .Email }}` is empty for a guest upgrade — the guest had no address).
`reset-password.html`: `{{ .Token }}`, `{{ .Email }}`.

## Related dashboard settings

- **Authentication → URL Configuration → Redirect URLs** must allow-list
  `soulfull://auth-callback`, or the link won't reopen the app even on the right
  device.
- **Authentication → Providers → Email → Confirm email** decides whether any of
  this runs. With it off, `createAccount` completes immediately and the confirm
  panel is skipped.
