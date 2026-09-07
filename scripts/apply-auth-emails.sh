#!/usr/bin/env bash
#
# Applies the branded Soulfull auth email templates to the live Supabase project.
#
# It PATCHes ONLY the four mailer_* fields on the project's auth config — it does
# not touch providers, redirect URLs, anonymous sign-ins or SMTP credentials.
# (This is deliberately not `supabase config push`: that pushes the *whole*
# resolved auth config, and every setting missing from a local config.toml would
# be reset to the CLI default — which would, among other things, switch anonymous
# sign-ins back off and take the app down.)
#
# Usage:
#   SUPABASE_ACCESS_TOKEN=sbp_… ./scripts/apply-auth-emails.sh          # apply
#   SUPABASE_ACCESS_TOKEN=sbp_… ./scripts/apply-auth-emails.sh --dry-run
#
# Get the token at https://supabase.com/dashboard/account/tokens.
# The sender NAME ("Supabase Auth" by default) is not set here — it comes from
# SMTP settings; see supabase/templates/README.md.

set -euo pipefail

cd "$(dirname "$0")/.."

REF="${SUPABASE_PROJECT_REF:-$(cat supabase/.temp/project-ref 2>/dev/null || true)}"
: "${REF:?Set SUPABASE_PROJECT_REF (or run 'supabase link' first)}"
: "${SUPABASE_ACCESS_TOKEN:?Set SUPABASE_ACCESS_TOKEN (https://supabase.com/dashboard/account/tokens)}"

PAYLOAD="$(mktemp)"
trap 'rm -f "$PAYLOAD"' EXIT

python3 - "$PAYLOAD" <<'PY'
import json, sys, pathlib

root = pathlib.Path("supabase/templates")
payload = {
    "mailer_subjects_confirmation": "Confirm your email · Soulfull Gatherings",
    "mailer_templates_confirmation_content": (root / "confirm-signup.html").read_text(),
    "mailer_subjects_email_change": "Confirm your email · Soulfull Gatherings",
    "mailer_templates_email_change_content": (root / "confirm-email-change.html").read_text(),
}
pathlib.Path(sys.argv[1]).write_text(json.dumps(payload))
PY

if [[ "${1:-}" == "--dry-run" ]]; then
  echo "Would PATCH https://api.supabase.com/v1/projects/$REF/config/auth with:"
  python3 -c 'import json,sys;d=json.load(open(sys.argv[1]));[print(f"  {k}: {len(v)} chars" if len(v)>80 else f"  {k}: {v}") for k,v in d.items()]' "$PAYLOAD"
  exit 0
fi

echo "Applying auth email templates to project $REF …"
curl --fail-with-body -sS -X PATCH \
  "https://api.supabase.com/v1/projects/$REF/config/auth" \
  -H "Authorization: Bearer $SUPABASE_ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  --data-binary "@$PAYLOAD" \
  -o /dev/null -w 'HTTP %{http_code}\n'

echo "Done. Send yourself a test sign-up to check it."
