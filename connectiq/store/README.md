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
