---
date: 2026-04-26
topic: Hero Image
---

# Speechwave Hero Image

## Purpose

A 1200×630 hero image for use in the project portfolio and documentation.

## Design decisions

- **Style:** Bold wordmark + floating emojis ("Emoji Wave" direction). Chosen over a product-flow diagram or conference-scene illustration because it reads instantly at small sizes and carries strong brand energy.
- **Dimensions:** 1200×630 — standard Open Graph / portfolio banner ratio.
- **Wordmark:** "Speechwave" at 96px, weight 900, gradient left→right: blue `#60a5fa` → indigo `#818cf8` → purple `#c084fc` → pink `#e879f9`.
- **Tagline:** "Real-time audience reactions for speakers" at 22px, slate `#94a3b8`.
- **Wave underline:** SVG sine wave between wordmark and tagline, same gradient as wordmark.
- **Background:** Dark `#0d1117` with a centered radial glow (`#19203a`) and a subtle 32px dot grid. Blue bloom left, pink bloom right to echo the gradient.
- **Emojis:** The app's five emojis (❤️ 😂 🔥 👏 🤯) scattered on both sides. Opacity and size decrease bottom→top to imply upward float motion.

## Output

`docs/hero.html` — open in browser at 100% zoom and screenshot the 1200×630 card.

Screenshot tips:
- `⌘⇧4` drag-select the card
- Or DevTools → Device Toolbar → 1200×630 → full-page screenshot
