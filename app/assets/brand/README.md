# Flap brand assets

Everything here comes from Flap's own official Media Kit. Nothing was taken from a third-party
logo site.

- Kit page: <https://docs.flap.sh/en/flap/v2/media-kit> ("Flap's logos and brand assets, for
  articles, listings and partner pages.")
- Download: <https://docs.flap.sh/gitbook-files/assets/Flap%20Media%20Kit.zip>
- Downloaded: 25 Nov 2026, 1,270,928 bytes
- SHA-256: `6bf1cbafffa5274c67eff060859c03a2a6311fa23470e0e58296c84442de9050`

The files were treated as untrusted data: nothing was executed, and each SVG was read as text. They
contain only `<svg>` and `<path>` elements with a single fill colour (no scripts, no event
handlers, no links, no embedded or external content).

## Files in this folder

| File | What it is | Source inside the kit | Changed? |
| --- | --- | --- | --- |
| `flap.png` | Full logo (mark + FLAP), fluorescent green, transparent, 1400 x 340. **The one the app uses** on its dark background. | `Flap_logo_png/A1_Logo/Logotype/LogoType-02.png` (8000 x 4500) | Transparent margin cropped evenly around the centre (to 7000 x 1700), then scaled down in proportion. Artwork, colour and proportions untouched; a margin of about a third of the logo height is kept on every side. |
| `flap_mark.png` | Logomark only (the butterfly), fluorescent green, transparent, 512 x 512. | `Flap_logo_png/A1_Logo/Logomark/Logo_02.png` (5417 x 5417) | Scaled down in proportion only. |
| `flap.svg` | Full logo, fluorescent green `#D0FF00`, 140 x 24. | `Flap_logo_svg/Flap_logo_green.svg` | No, byte-for-byte copy. |
| `flap_purple.svg` | Full logo, purple `#5B31FF`, 140 x 24. | `Flap_logo_svg/Flap_logo_purple.svg` | No. |
| `flap_mark.svg` | Logomark, fluorescent green, 80 x 80. | `Flap_logo_svg/Flap_Green.svg` | No. |
| `flap_mark_purple.svg` | Logomark, purple, 80 x 80. | `Flap_logo_svg/Flap_Purple.svg` | No. |
| `original/Flap-Media-Kit.zip` | The kit exactly as downloaded (renamed only). | Download link above | No. |

Only `flap.png` and `flap_mark.png` are registered in `pubspec.yaml`. The SVGs are here for the
web page, slides and the README; the app has no SVG package, so do not load them with
`Image.asset`. The zip and this README are not bundled into the app.

Not copied out of the zip (still inside `original/Flap-Media-Kit.zip`): the purple, black and white
PNG variants of the logomark, wordmark and logotype, `C1_MainColor.png`, `flap_logo.eps`, the X
profile pictures and header backgrounds (those are for Flap's own account, not for us), and
`Brand Considerations.docx`.

## Usage rules

The kit's only written rules are in `Brand Considerations.docx`. Quoted from it:

- **Logo size and position, clear space:** "The use of the logo should not be oversized and should
  preferably be positioned at a visually balanced midpoint. The logo should also not be placed too
  close to other elements."
- **Colours:** "The primary colors are purple and fluorescent green, used in combination."
- **On other companies' pages (that is us):** "fixed colors are not necessary, and black and white
  can also be used. Be cautious about using colors other than Primary Colors."
- **Font:** "The font currently selected for Flap is Inter (from Google Font)." This is about Flap's
  own posts; it does not ask partners to change their font.

From the kit page: the vector files are "for print and any size".

Colour values:

| Colour | Docs page and SVG files | `C1_MainColor.png` in the kit |
| --- | --- | --- |
| Purple | `#5B31FF` | `#5533FF` |
| Fluorescent green | `#D0FF00` | `#DAFF00` |

The two sources disagree slightly. We never repaint the logo, so the app simply shows the colours
baked into the official files.

### What the kit does not say

- No exact clear-space measurement and no minimum size. The document points to "the logo integrity
  range in the VI Guidelines" and "the color misuse guidelines in the VI Guidelines", but the VI
  Guidelines are not in the kit and are not published on docs.flap.sh.
- No approved partner wording such as "Built on Flap" or "Powered by Flap", and no badge.
- No explicit list of prohibited uses and no licence or trademark terms.

### How Cypher Run applies this

- Use the logo once, small, as an attribution next to the plain text "Built on Flap" (the About card on the
  Account screen). Never as the app icon, splash, or in place of the product name.
- Green logo on the dark background; purple on a light background. Do not recolour, tint, stretch,
  rotate, outline, add effects, or cut the mark out of the full logo. Use `flap_mark.png` when only
  the mark fits.
- Keep clear space of at least the height of the mark on every side (`flap.png` already carries
  about a third of that; add padding in the layout). Keep the full logo at least 16 px tall.
- Wording: "Built on Flap". Do not write or imply that Flap sponsors, endorses, audits or operates
  Cypher Run, or that Flap provides wallets. Check-ins are attested by our own server.
- These conservative rules are our own reading where the kit is silent, not Flap's text.

## To ask the Flap team at the venue

1. May hackathon projects show the Flap logo in the app and on the demo page with the text "Built on
   Flap"? Is there preferred wording or an official badge?
2. Can we have the VI Guidelines the kit refers to (logo integrity range / clear space, minimum
   size, colour misuse examples)?
3. Which values are correct: `#5B31FF` / `#D0FF00` (docs and SVGs) or `#5533FF` / `#DAFF00`
   (`C1_MainColor.png`)?
4. Is the green logo on a near-black glass background acceptable, and is the logomark alone allowed
   at small sizes?
5. Anything we must not do with the logo or the name (store listings, social posts, the pitch deck)?
