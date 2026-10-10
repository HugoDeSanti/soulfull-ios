# Soulfull Gatherings — iOS

The iPhone app for Soulfull Gatherings, a wellness retreat and community
platform: in-person retreats (Gatherings), free self-paced digital retreats,
guided practices, guide profiles and a small community feed. Browsing needs no
account; one is asked for only when someone reaches for something personal.

SwiftUI, iOS 18 minimum, Swift 6, MVVM with Observation. The backend is
Supabase (Postgres, Storage, Auth, Edge Functions). There is no in-app payment
in v1.

## Build and run

You need **Xcode 26** (the app adopts Liquid Glass behind `#available`, which
needs the iOS 26 SDK), its **Metal toolchain** (`xcodebuild -downloadComponent
MetalToolchain` if the build says it "cannot execute tool 'metal'"), and
[XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```bash
cp Config/Secrets.xcconfig.example Config/Secrets.xcconfig
# fill in SUPABASE_HOST (host only, no https://) and SUPABASE_ANON_KEY
# from Supabase Dashboard → Settings → API

xcodegen generate                   # again after editing project.yml or adding any file
open SoulfullGatherings.xcodeproj   # ⌘R on an iPhone simulator
```

The `.xcodeproj`, `Info.plist` and entitlements are generated from
`project.yml` and are not in git. Missing Supabase values crash at launch with
setup instructions, on purpose.

## Tests

```bash
xcodebuild test -project SoulfullGatherings.xcodeproj -scheme SoulfullGatherings \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:SoulfullTests
```

The UI journeys run against the live backend and need a simulator nobody is
signed in on. How to run them, and which change needs which test, is in
[`CLAUDE.md` → Testing](CLAUDE.md#testing).

## Where things are documented

| Document | What it covers |
|---|---|
| [`CLAUDE.md`](CLAUDE.md) | Architecture, conventions, the backend schema and its gotchas, testing policy, current state |
| [`docs/ADDING-A-RETREAT.md`](docs/ADDING-A-RETREAT.md) | Publishing a retreat and its brochure, with no app release |
| [`docs/ADDING-A-WRITTEN-PRACTICE.md`](docs/ADDING-A-WRITTEN-PRACTICE.md) | Journal prompts, movement sequences and recipes |
| [`docs/ADDING-AN-INSTRUCTOR.md`](docs/ADDING-AN-INSTRUCTOR.md) | Guides: profiles, credits, linking a guide's account |
| [`docs/CREATOR-PAYOUTS.md`](docs/CREATOR-PAYOUTS.md) | Setting a month's pool and paying guides |
| [`docs/MODERATION.md`](docs/MODERATION.md) | Member reports and blocks, and the 24-hour review promise |
| [`docs/APP-REVIEW-NOTES.md`](docs/APP-REVIEW-NOTES.md) | The submission checklist and the notes for App Review |
| [`supabase/functions/README.md`](supabase/functions/README.md) | Deploying the Edge Functions and their secrets |
| [`supabase/templates/README.md`](supabase/templates/README.md) | The branded auth emails |
| [`design-system/README.md`](design-system/README.md) | The HTML mirror of the UI synced to Claude Design |
