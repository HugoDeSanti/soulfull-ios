# Brochure-light card backups

These are the **original brochure-light** versions of the Mallorca post-purchase
screens, as pulled from Claude Design (cream/espresso/terracotta palette,
Cormorant Garamond + Pinyon Script).

They are kept here, **outside** `design-system/`, on purpose: the live mirror
cards in `design-system/screens/` use the UX team's **warm-espresso** dark
direction (terracotta/olive/gold on espresso, all-Geist; ported to Swift as
`RetreatPalette`), and these backups preserve the original brochure-light look in
case we want to revisit it. They live
outside the synced tree so the Claude Design `@dsCard` indexer can't pick them up
as duplicate cards and `/sync-design push` can't publish them.

Files: `mallorca-welcome`, `mallorca-guides`, `mallorca-chatbot`,
`retreat-checkout`, `retreat-todos`.
