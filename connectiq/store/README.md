# Store assets — Dual-Tank Anaerobic

Marketing/store imagery for the Connect IQ app. Two glossy fuel tanks:
**purple = PCr (phosphocreatine)**, **green = GLY (glycolytic)**, matching the data-field palette.

| File | Purpose | Spec | Actual |
|---|---|---|---|
| `hero_1440x720.png` | Hero image | 1440×720, ≤ 2048 KB (JPG/GIF/PNG) | 1440×720 PNG, ~108 KB |
| `cover_500x500.png` | Cover image (web/mobile) | 500×500 | 500×500 PNG |
| `device_icon_128_24bit.png` | Device icon | 128×128, 24-bit color | 128×128, 8-bit/ch RGB (24-bit) |
| `device_icon_128_64bit.png` | Device icon | 128×128, 64-bit color | 128×128, 16-bit/ch RGBA (64-bit) |

Regenerate all four with:

```bash
python3 make_assets.py     # requires Pillow; writes into this folder
```

Palette (RGB): PCr bright `#B44DFF` / deep `#6C26A8`; GLY bright `#37E85A` / deep `#1A8C3A`.

## In-app screenshots

Renders of the live data field (horizontal bars) mirroring `DualTankView.drawBar`, at four states:

| File | State |
|---|---|
| `screenshot_full.png` | Easy — both tanks full (dull purple / green) |
| `screenshot_surge.png` | Short surge — PCr bright + `-190W`, glycolytic barely touched |
| `screenshot_sustain.png` | Sustained supra-CP — both draining (bright) |
| `screenshot_empty.png` | PCr spent — full-width red flash |
| `screenshots_grid.png` | 2×2 gallery of all four (preview) |
| `screenshots_grid_light.png` | same four states on a **light** background (theme-adaptation proof) |
| `screenshots_vertical.png` | vertical **side-by-side** layout for a square/tall (e.g. 1×2) cell |
| `screenshots_wide.png` | **very-wide** layout: two horizontal bars side by side |
| `screenshots_full.png` | **large single-field** layout: vertical tanks + depleted-kJ & fatigue summary |

Regenerate with `python3 make_screens.py`. These are representative renders for the gallery;
for official store submission, capture at true device resolution from the Connect IQ **simulator**
(it exports device-correct PNGs).

## Icon fallback

| File | Format |
|---|---|
| `device_icon_128_8bit_palette.png` | 128×128, 8-bit **palettized** PNG (color-type 3) — use if the store rejects the 64-bit icon |

> The field adapts to light **and** dark themes: `DualTankView.contrastColor()` picks black or white
> foreground by background luminance, so labels, outlines and readouts stay legible either way.

> The field **adapts its layout to the cell's aspect ratio**: a wide/short slot stacks two
> horizontal bars; a square or tall slot (like a 1×2 cell) shows two vertical bars side by side; a **very wide** slot shows two horizontal bars side by side.
