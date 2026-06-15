#!/usr/bin/env bash
# PostToolUse hook — design-system mirror reminder.
#
# Fires after Edit/Write/MultiEdit. If the edited file is design-relevant Swift
# (Theme/Components/SoulGlass/BottomNav/DesignSystem or a Features view), it nudges
# Claude to update the matching design-system/ mirror file in the same change and
# to remind the user to run /sync-design push.
#
# Reminder ONLY: a shell hook can't translate Swift->HTML or push to claude.ai
# (DesignSync needs a live session). It just keeps flow #1 in CLAUDE.md reliable.
set -euo pipefail
input=$(cat)
printf '%s' "$input" | python3 -c '
import sys, json
try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(0)
fp = (data.get("tool_input") or {}).get("file_path", "") or ""
if not fp.endswith(".swift"):
    sys.exit(0)
relevant = (
    fp.endswith("/Core/DesignSystem/Theme.swift")
    or fp.endswith("/Core/DesignSystem/Components.swift")
    or "/Core/DesignSystem/" in fp
    or fp.endswith("/App/BottomNav.swift")
    or "/Features/" in fp
)
if not relevant:
    sys.exit(0)
msg = (
    "[design-mirror] " + fp + " is design-relevant. Per CLAUDE.md -> "
    "\"Design <-> Code Sync\": if this edit changed anything visual "
    "(tokens / components / screen layout / copy), update the matching "
    "design-system/ mirror file in THIS same change, then remind the user to "
    "run /sync-design push to publish to Claude Design. If the edit was purely "
    "logic/backend with no visual effect, ignore this."
)
print(json.dumps({
    "hookSpecificOutput": {
        "hookEventName": "PostToolUse",
        "additionalContext": msg,
    }
}))
'
