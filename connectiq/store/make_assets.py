#!/usr/bin/env python3
"""Generate Connect IQ store assets for the Dual-Tank Anaerobic app.
Two glossy fuel tanks: purple = PCr (phosphocreatine), green = GLY (glycolytic)."""
import os, sys, zlib, struct
from PIL import Image, ImageDraw, ImageFont, ImageFilter

OUT = os.path.dirname(os.path.abspath(__file__))
os.makedirs(OUT, exist_ok=True)

# Scalable-font candidates tried in order (cross-platform). font() resolves one once and
# caches it; if none is a scalable TrueType it raises loudly rather than falling back to a
# bitmap font (which would silently emit wrong-sized text).
FONT_CANDIDATES = [
    "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",  # Debian/Ubuntu
    "/usr/share/fonts/TTF/DejaVuSans-Bold.ttf",              # Arch/others
    "/Library/Fonts/Arial Bold.ttf",                         # macOS
    "/System/Library/Fonts/Supplemental/Arial Bold.ttf",     # macOS
    "C:\\Windows\\Fonts\\arialbd.ttf",                        # Windows
    "DejaVuSans-Bold.ttf", "Arial Bold.ttf", "Arialbd.ttf",  # let PIL resolve by name
]
_FONT_PATH = None  # resolved once, then cached

# ---- brand palette (matches the data field) ----
PURPLE_BRIGHT = (180, 77, 255)
PURPLE_DEEP   = (108, 38, 168)
PURPLE_EMPTY  = (64, 44, 88)
GREEN_BRIGHT  = (55, 232, 90)
GREEN_DEEP    = (26, 140, 58)
GREEN_EMPTY   = (40, 66, 48)
WHITE = (255, 255, 255)

def font(sz):
    """Always return a scalable FreeTypeFont at size `sz`; never a bitmap fallback.

    Output text metrics are now font-dependent — Linux resolves DejaVu, macOS/Windows
    resolve Arial — so text sizing (and thus the committed PNGs) can differ across
    machines. Generate on a box with fonts-dejavu-core (CI pins it) for byte-stable assets.
    This rewrite also incidentally closes the bare-`except:` tracked in #45. (make_hero's
    fitfont already tracks size in a local int, so no font `.size` read exists here.)
    """
    global _FONT_PATH
    if _FONT_PATH is not None:
        return ImageFont.truetype(_FONT_PATH, sz)
    for cand in FONT_CANDIDATES:
        try:
            f = ImageFont.truetype(cand, sz)   # raises if missing / not scalable
            _FONT_PATH = cand
            return f
        except (OSError, IOError):
            continue
    raise RuntimeError(
        "No scalable TrueType font found. Install one (e.g. "
        "`apt-get install fonts-dejavu-core`) or add a path to FONT_CANDIDATES. Tried: "
        + ", ".join(FONT_CANDIDATES))

def lerp(a, b, t):
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(3))

def vgradient(size, top, bot):
    """Vertical gradient background image (RGB)."""
    w, h = size
    img = Image.new("RGB", size, top)
    px = img.load()
    for y in range(h):
        c = lerp(top, bot, y / max(1, h - 1))
        for x in range(w):
            px[x, y] = c
    return img

def rounded_mask(size, radius):
    m = Image.new("L", size, 0)
    d = ImageDraw.Draw(m)
    d.rounded_rectangle([0, 0, size[0] - 1, size[1] - 1], radius=radius, fill=255)
    return m

def draw_tank(base, box, frac, bright, deep, empty, label, label_sz,
              show_label=True, outline_w=None):
    """Draw a glossy vertical tank into `base` (RGBA). box=(x0,y0,x1,y1)."""
    x0, y0, x1, y1 = box
    w, h = x1 - x0, y1 - y0
    radius = int(w * 0.28)
    if outline_w is None:
        outline_w = max(2, int(w * 0.04))

    tank = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    mask = rounded_mask((w, h), radius)

    # body fill: empty (dull) everywhere, bright gradient in the filled bottom part
    body = Image.new("RGB", (w, h), empty)
    bp = body.load()
    fill_top = int(h * (1.0 - frac))
    for y in range(h):
        if y >= fill_top:
            t = (y - fill_top) / max(1, (h - fill_top))
            c = lerp(bright, deep, t)          # brighter at surface, deeper at base
        else:
            c = lerp(empty, tuple(int(v * 0.7) for v in empty), y / max(1, h))
        for x in range(w):
            bp[x, y] = c
    tank.paste(body, (0, 0), mask)

    d = ImageDraw.Draw(tank)
    # liquid surface highlight
    if 0.02 < frac < 0.99:
        sy = fill_top
        surf = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        sd = ImageDraw.Draw(surf)
        sd.ellipse([outline_w, sy - max(3, h*0.02), w - outline_w, sy + max(3, h*0.02)],
                   fill=tuple(list(lerp(bright, WHITE, 0.45)) + [200]))
        surf.putalpha(Image.composite(surf.getchannel("A"), Image.new("L", (w, h), 0), mask))
        tank = Image.alpha_composite(tank, surf)
        d = ImageDraw.Draw(tank)

    # gloss: soft white vertical stripe on the left
    gloss = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    gd = ImageDraw.Draw(gloss)
    gx0, gx1 = int(w * 0.16), int(w * 0.34)
    gd.rounded_rectangle([gx0, int(h*0.06), gx1, int(h*0.94)],
                         radius=(gx1 - gx0)//2, fill=(255, 255, 255, 60))
    gloss = gloss.filter(ImageFilter.GaussianBlur(w * 0.02))
    gloss.putalpha(Image.composite(gloss.getchannel("A"), Image.new("L", (w, h), 0), mask))
    tank = Image.alpha_composite(tank, gloss)
    d = ImageDraw.Draw(tank)

    # bubbles in the filled region
    if frac > 0.15:
        import math
        for i, (bx, by, br) in enumerate([(0.62,0.82,0.045),(0.7,0.6,0.03),
                                          (0.5,0.68,0.025),(0.66,0.45,0.02)]):
            if (1.0 - by) < frac:
                cx, cy, r = int(w*bx), int(h*by), max(2, int(w*br))
                d.ellipse([cx-r, cy-r, cx+r, cy+r], outline=(255,255,255,120), width=max(1,r//3))

    # outline
    d.rounded_rectangle([outline_w//2, outline_w//2, w - 1 - outline_w//2, h - 1 - outline_w//2],
                        radius=radius, outline=tuple(list(lerp(deep,(0,0,0),0.2)) + [255]),
                        width=outline_w)

    base.alpha_composite(tank, (x0, y0))

    # cap / nozzle on top
    cd = ImageDraw.Draw(base)
    cap_w = int(w * 0.34); cap_h = int(h * 0.05)
    ccx = x0 + w//2
    cd.rounded_rectangle([ccx - cap_w//2, y0 - cap_h, ccx + cap_w//2, y0 + cap_h//2],
                         radius=cap_h//2, fill=tuple(list(lerp(deep,(0,0,0),0.1)) + [255]))

    # label + percentage
    if show_label:
        f = font(label_sz)
        pf = font(int(label_sz * 0.72))
        pct = "{}%".format(int(round(frac * 100)))
        tb = cd.textbbox((0, 0), label, font=f)
        cd.text((ccx - (tb[2]-tb[0])//2, y1 + int(h*0.03)), label, font=f, fill=WHITE)
        pb = cd.textbbox((0, 0), pct, font=pf)
        cd.text((ccx - (pb[2]-pb[0])//2, y1 + int(h*0.03) + (tb[3]-tb[1]) + int(label_sz*0.35)),
                pct, font=pf, fill=lerp(bright, WHITE, 0.2))

# ============================ HERO 1440x720 ============================
def make_hero():
    W, H = 1440, 720
    img = vgradient((W, H), (26, 28, 44), (9, 10, 17)).convert("RGBA")
    # subtle radial vignette glow behind tanks
    glow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    gd.ellipse([W*0.2, H*0.1, W*0.8, H*1.05], fill=(120, 80, 200, 40))
    glow = glow.filter(ImageFilter.GaussianBlur(120))
    img = Image.alpha_composite(img, glow)

    # tanks on the left third
    tw, th = 300, 430
    ty = 168
    lx = 90
    draw_tank(img, (lx, ty, lx + tw, ty + th), 0.78,
              PURPLE_BRIGHT, PURPLE_DEEP, PURPLE_EMPTY, "PCr", 46)
    lx2 = lx + tw + 80
    draw_tank(img, (lx2, ty, lx2 + tw, ty + th), 0.41,
              GREEN_BRIGHT, GREEN_DEEP, GREEN_EMPTY, "GLY", 46)

    d = ImageDraw.Draw(img)
    # title/copy block on the right, kept inside a safe right margin
    tx = 800
    right_margin = W - 40

    def fitfont(text, size, maxw):
        f = font(size)
        while size > 10 and d.textbbox((0, 0), text, font=f)[2] > maxw:
            size -= 2; f = font(size)
        return f

    maxw = right_margin - tx
    d.text((tx, 196), "Dual-Tank", font=fitfont("Dual-Tank", 84, maxw), fill=WHITE)
    d.text((tx, 292), "Anaerobic", font=fitfont("Anaerobic", 84, maxw),
           fill=lerp(PURPLE_BRIGHT, WHITE, 0.15))
    subf = font(28)
    for i, line in enumerate(["Track your phosphocreatine",
                              "and glycolytic reserves —",
                              "live, from power."]):
        subf = fitfont(line, 28, maxw) if i == 0 else subf
        d.text((tx, 424 + i * 40), line, font=subf, fill=(200, 205, 220))
    # accent chips
    d.rounded_rectangle([tx, 566, tx+150, 610], radius=22, fill=PURPLE_DEEP)
    d.text((tx+34, 576), "PCr", font=font(26), fill=WHITE)
    d.rounded_rectangle([tx+168, 566, tx+318, 610], radius=22, fill=GREEN_DEEP)
    d.text((tx+198, 576), "GLY", font=font(26), fill=WHITE)

    out = os.path.join(OUT, "hero_1440x720.png")
    rgb = img.convert("RGB")
    rgb.save(out, "PNG")
    if os.path.getsize(out) > 2048 * 1024:
        rgb.save(os.path.join(OUT, "hero_1440x720.jpg"), "JPEG", quality=90)
        os.remove(out); out = os.path.join(OUT, "hero_1440x720.jpg")
    return out

# ============================ COVER 500x500 ============================
def make_cover():
    W = H = 500
    img = vgradient((W, H), (28, 30, 48), (10, 11, 18)).convert("RGBA")
    glow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(glow).ellipse([60, 40, 440, 470], fill=(120, 80, 200, 45))
    img = Image.alpha_composite(img, glow.filter(ImageFilter.GaussianBlur(70)))

    tw, th = 150, 250
    gap = 44
    ty = 96
    cx = W // 2
    draw_tank(img, (cx - tw - gap//2, ty, cx - gap//2, ty + th), 0.78,
              PURPLE_BRIGHT, PURPLE_DEEP, PURPLE_EMPTY, "PCr", 30)
    draw_tank(img, (cx + gap//2, ty, cx + gap//2 + tw, ty + th), 0.41,
              GREEN_BRIGHT, GREEN_DEEP, GREEN_EMPTY, "GLY", 30)

    d = ImageDraw.Draw(img)
    t = "DUAL-TANK"
    f = font(40)
    tb = d.textbbox((0, 0), t, font=f)
    d.text((W//2 - (tb[2]-tb[0])//2, 430), t, font=f, fill=WHITE)
    out = os.path.join(OUT, "cover_500x500.png")
    img.convert("RGB").save(out, "PNG")
    return out

# ============================ DEVICE ICON 128x128 ============================
def render_icon_rgba():
    W = H = 128
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    # rounded dark badge background
    badge = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(badge).rounded_rectangle([0, 0, W-1, H-1], radius=26, fill=(18, 20, 32, 255))
    img = Image.alpha_composite(img, badge)
    # two compact tanks, no text (readable small)
    tw, th = 34, 78
    gap = 16
    ty = 26
    cx = W // 2
    draw_tank(img, (cx - tw - gap//2, ty, cx - gap//2, ty + th), 0.78,
              PURPLE_BRIGHT, PURPLE_DEEP, PURPLE_EMPTY, "", 1,
              show_label=False, outline_w=3)
    draw_tank(img, (cx + gap//2, ty, cx + gap//2 + tw, ty + th), 0.41,
              GREEN_BRIGHT, GREEN_DEEP, GREEN_EMPTY, "", 1,
              show_label=False, outline_w=3)
    # clip everything to the rounded badge shape
    m = rounded_mask((W, H), 26)
    img.putalpha(Image.composite(img.getchannel("A"), Image.new("L", (W, H), 0), m))
    return img

def write_png16(rgba_img, path):
    """Write a 16-bit-per-channel RGBA PNG (64-bit color) manually."""
    W, H = rgba_img.size
    src = rgba_img.tobytes()  # RGBA 8-bit
    raw = bytearray()
    i = 0
    for y in range(H):
        raw.append(0)  # filter none
        for x in range(W):
            for c in range(4):
                v = src[i + c]
                raw.append(v); raw.append(v)  # v*257 -> hi=v, lo=v
            i += 4
    def chunk(typ, data):
        return struct.pack(">I", len(data)) + typ + data + struct.pack(">I", zlib.crc32(typ + data) & 0xffffffff)
    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", W, H, 16, 6, 0, 0, 0))  # 16-bit, RGBA
    png += chunk(b"IDAT", zlib.compress(bytes(raw), 9))
    png += chunk(b"IEND", b"")
    with open(path, "wb") as f:
        f.write(png)

def make_icons():
    icon = render_icon_rgba()
    # 24-bit color: 8-bit RGB (flatten alpha over dark to keep the badge)
    bg = Image.new("RGB", icon.size, (18, 20, 32))
    bg.paste(icon, (0, 0), icon)
    p24 = os.path.join(OUT, "device_icon_128_24bit.png")
    bg.save(p24, "PNG")  # PIL RGB = 8bpc = 24-bit color
    # 64-bit color: 16-bit RGBA written manually
    p64 = os.path.join(OUT, "device_icon_128_64bit.png")
    write_png16(icon, p64)
    return p24, p64

if __name__ == "__main__":
    try:
        h = make_hero(); print("hero:", h, os.path.getsize(h)//1024, "KB")
        c = make_cover(); print("cover:", c, os.path.getsize(c)//1024, "KB")
        a, b = make_icons()
        print("icon24:", a, os.path.getsize(a)//1024, "KB")
        print("icon64:", b, os.path.getsize(b)//1024, "KB")
    except Exception as e:
        print("ERROR: {}".format(e), file=sys.stderr)
        sys.exit(1)
