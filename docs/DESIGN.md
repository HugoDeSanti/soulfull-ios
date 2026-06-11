# Soulfull — Design Overhaul

Working doc for the 2026-06 UI overhaul. Direction, component inventory, per-screen plan,
and verification notes. Keep this current as screens land.

## Direction: "Quiet luxury, editorial"

The app already speaks dark/olive/cream Geist. The overhaul keeps that voice and adds
**atmosphere and physics**: everything breathes, responds to touch with weight, and moves
with intent. Three pillars:

1. **Atmosphere** — custom Metal shaders give every surface life: film grain over photos,
   slow aurora drift behind hero moments, specular shimmer on glass, noise-dissolve for
   stage changes. Nothing strobes; everything drifts at breath pace (4–6s cycles).
2. **Physics** — every tap squishes (springs, scale ~0.96, haptic on touch-down), every push
   is a zoom hero (`navigationTransition(.zoom)`), pinch-out zooms scrolling views into a
   magazine "catalog" contact sheet.
3. **Editorial** — magazine layout rules: oversized Geist headlines with tight kerning,
   eyebrow caps, full-bleed photography with scroll parallax, generous whitespace,
   numbered folios (01/07) instead of dots-and-chrome.

## Foundation (Core/DesignSystem/)

| File | Contents |
|---|---|
| `Shaders.metal` | `filmGrain` (colorEffect), `aurora` (colorEffect, tone-tinted fbm drift), `shimmer` (layerEffect specular sweep), `noiseDissolve` (layerEffect, used by custom Transition), `ripple` (distortionEffect) |
| `ShaderFX.swift` | SwiftUI wrappers: `.filmGrain(intensity:)`, `AuroraBackground(tones:)` (TimelineView-driven), `.shimmerSweep(trigger:)`, `NoiseDissolve` custom `Transition`, `.heroRipple(...)` |
| `SoulGlass.swift` | `.soulGlass(in:)` — real `glassEffect` on iOS 26+, `.ultraThinMaterial` + stroke fallback on 18–25. One abstraction point; all cards/pills go through it. |
| `Pressable.swift` | `.pressable(scale:haptic:)` — touch-down spring squish + haptic; replaces ad-hoc DragGesture press handling |
| `ZoomableCatalog.swift` | Pinch-driven layout morph: LazyVGrid column-count morph (1 ⇄ 2) driven by `MagnifyGesture`, interactive scale scrub during the gesture, spring commit + haptic detent. Used by Practice landing/lists; Retreats has a bespoke morph. |
| `Parallax.swift` | `.scrollParallax(...)` via `visualEffect` — imagery drifts counter to scroll |

Min deployment stays **iOS 18**; iOS 26 Liquid Glass (`glassEffect`, `glassEffectID`,
`GlassEffectContainer`) is adopted behind `if #available(iOS 26.0, *)` inside `SoulGlass`
only — feature code never branches on OS.

## Per-screen plan

- **RootView** — stage changes use `NoiseDissolve` transition; loading = breathing logo on
  `AuroraBackground` (no bare ProgressView).
- **BottomNav** — one continuous glass capsule; active tab gets a sliding cream "lens"
  (matchedGeometry) that squish-stretches as it lands; active label fades in beside icon;
  grain-free, true liquid glass on 26+.
- **Welcome** — splash logo breathes over aurora; slides crossfade through dissolve with
  parallax on the backdrop; folio (01/03) instead of dots.
- **Onboarding** — chips become glass tiles that bloom honey when selected (shimmer sweep);
  thin honey progress line at top; question text transitions blur+rise.
- **Home** — sections reveal via `scrollTransition`; card imagery gets `scrollParallax`;
  mood chips bloom; retreat/program cards are zoom-hero sources; ritual card gets a slow
  aurora rim.
- **Retreats stack** — keep the typographic stack (it's the signature); add pinch-out →
  magazine-cover grid (each retreat a cover with name/dates/folio), tap a cover to refocus
  the stack; backdrop crossfade gains a ripple; detail push is a zoom hero from the
  bottom card.
- **Retreat detail** — becomes scrollable editorial: stretchy full-bleed hero at rest
  identical to today's layout, scroll reveals story sections (blurb, tags as "the days",
  meta), liquid-glass reserve bar pinned at bottom.
- **Practice** — landing cards in a `ZoomableCatalog` (pinch out to contact sheet);
  list rows get bigger imagery + zoom-hero into player/detail.
- **Player** — custom now-playing for audio: aurora tinted from artwork, breathing circle
  synced to nothing-in-particular (6s), custom scrubber with haptic detents, ±15s,
  play/pause icon morph. Video keeps AVKit inside custom chrome.
- **Detail screens** — Journal: writing room (prompt as pull-quote, focused editor);
  Recipe: magazine spread (hero, meta folio, ingredient checklist with spring checks);
  Exercise/Massage: numbered editorial steps; placeholders get aurora + grain.

## Decisions

- **Shader effects never wrap platform-backed views.** `layerEffect`/`colorEffect`/
  `distortionEffect` over a subtree containing `NavigationStack` (UIKit-backed), video
  players, or sheets fails to rasterize and renders the yellow ⃠ placeholder. Keep
  shaders on leaf imagery/backdrops; stage transitions use `NoiseDissolve` only for
  pure-SwiftUI stages (loading/welcome/onboarding) — main gets a native scale+fade.

- No external image generation: no API keys in this environment. Existing photography +
  shader grading carries the look. (If keys appear later, recipes/journals deserve bespoke art.)
- Reduce Motion: heavy motion (aurora drift, parallax, dissolves) checks
  `accessibilityReduceMotion` and falls back to crossfades/static gradients.
- Grain is applied per-backdrop (not globally) so sheets/system UI stay clean.

## Verification

- Build per phase: `xcodegen generate && xcodebuild … -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`.
- `SoulfullUITests` tour test drives Welcome → Onboarding → Home → Retreats (pinch, push) →
  Practice (pinch, player) → You, attaching screenshots; extracted from the `.xcresult`
  and reviewed visually.
- Commits land per phase (foundation, nav, welcome/onboarding, home, retreats, practice,
  player, details, verification fixes).
