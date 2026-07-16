#!/usr/bin/env python3
"""Render in-app screenshots of the Dual-Tank data field (horizontal bars),
mirroring DualTankView.drawBar, at several depletion states; plus a palettized
8-bit device-icon fallback."""
import os, sys
from PIL import Image, ImageDraw, ImageFont

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

# palette identical to the Monkey C constants
PCR_DULL   = (0x5A, 0x3A, 0x6E)
PCR_BRIGHT = (0xB4, 0x4D, 0xFF)
GLY_DULL   = (0x2E, 0x5A, 0x3A)
GLY_BRIGHT = (0x37, 0xE8, 0x5A)
RED        = (0xFF, 0x00, 0x00)
BLACK      = (0, 0, 0)
WHITE      = (255, 255, 255)

def font(sz):
    """Always return a scalable FreeTypeFont at size `sz`; never a bitmap fallback.

    Output text metrics are now font-dependent — Linux resolves DejaVu, macOS/Windows
    resolve Arial — so caption sizing (and thus the committed PNGs) can differ across
    machines. Generate on a box with fonts-dejavu-core (CI pins it) for byte-stable assets.
    This rewrite also incidentally closes the bare-`except:` tracked in #45.
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

def contrast(bg):
    r, g, b = bg
    lum = (r*30 + g*59 + b*11) // 100
    return BLACK if lum > 140 else WHITE

def draw_bar(d, x, y, bw, bh, pct, is_pcr, cons, flash_on, fg):
    r = max(2, bh // 3)   # rounded 'tank' corners
    d.rounded_rectangle([x, y, x + bw, y + bh], radius=r, outline=fg, width=3)
    depleted = pct <= 3.0
    draining = cons > 0
    col = PCR_DULL if is_pcr else GLY_DULL
    if depleted:
        if not flash_on:
            return
        col = RED
        fillw = bw - 3
    else:
        if draining:
            col = PCR_BRIGHT if is_pcr else GLY_BRIGHT
        fillw = int((bw - 3) * pct / 100.0)
        fillw = max(0, min(bw - 3, fillw))
    if fillw > 0:
        rr = max(1, min(r - 1, fillw // 2, (bh - 4) // 2))
        d.rounded_rectangle([x + 2, y + 2, x + 2 + fillw, y + bh - 2], radius=rr, fill=col)
    # live consumption readout while draining (inside the bar, right-aligned)
    if draining and not depleted:
        wtxt = "-{}W".format(int(cons))
        f = font(int(bh * 0.34))
        tb = d.textbbox((0, 0), wtxt, font=f)
        # text sits over the bright fill on the left / bg on the right; use fg for legibility
        d.text((x + bw - 10 - (tb[2]-tb[0]), y + bh//2 - (tb[3]-tb[1])//2 - tb[1]), wtxt, font=f, fill=fg)

def render_field(W, H, st, bg=BLACK):
    """st = dict(pctP,pctG,consP,consG,flash); bg = field background color"""
    fg = contrast(bg)
    img = Image.new("RGB", (W, H), bg)
    d = ImageDraw.Draw(img)
    pad = int(W * 0.035)
    labelW = int(W * 0.11)
    valueW = int(W * 0.17)
    barH = min(int(H * 0.30), (H - 3 * pad) // 2)
    yTop = pad + int(H * 0.04)
    yBot = H - pad - barH - int(H * 0.04)
    xBar = pad + labelW
    barW = W - xBar - valueW - pad

    draw_bar(d, xBar, yTop, barW, barH, st["pctP"], True,  st["consP"], st["flash"], fg)
    draw_bar(d, xBar, yBot, barW, barH, st["pctG"], False, st["consG"], st["flash"], fg)

    lf = font(int(barH * 0.5))
    vf = font(int(barH * 0.52))
    for (yy, lab) in [(yTop, "PCr"), (yBot, "GLY")]:
        lb = d.textbbox((0, 0), lab, font=lf)
        d.text((pad, yy + barH//2 - (lb[3]-lb[1])//2 - lb[1]), lab, font=lf, fill=fg)
    for (yy, pct) in [(yTop, st["pctP"]), (yBot, st["pctG"])]:
        t = "{}%".format(int(round(pct)))
        tb = d.textbbox((0, 0), t, font=vf)
        d.text((W - pad - (tb[2]-tb[0]), yy + barH//2 - (tb[3]-tb[1])//2 - tb[1]), t, font=vf, fill=fg)
    return img

def draw_bar_v(d, x, y, bw, bh, pct, is_pcr, cons, flash_on, fg):
    r = max(2, bw // 3)   # rounded 'tank' corners
    d.rounded_rectangle([x, y, x + bw, y + bh], radius=r, outline=fg, width=3)
    depleted = pct <= 3.0
    draining = cons > 0
    col = PCR_DULL if is_pcr else GLY_DULL
    if depleted:
        if not flash_on:
            return
        col = RED
        fillh = bh - 3
    else:
        if draining:
            col = PCR_BRIGHT if is_pcr else GLY_BRIGHT
        fillh = int((bh - 3) * pct / 100.0)
        fillh = max(0, min(bh - 3, fillh))
    if fillh > 0:
        rr = max(1, min(r - 1, fillh // 2, (bw - 4) // 2))
        d.rounded_rectangle([x + 2, y + bh - 2 - fillh, x + bw - 2, y + bh - 2], radius=rr, fill=col)  # bottom-up
    if draining and not depleted:
        wtxt = "-{}W".format(int(cons))
        f = font(max(12, int(bw * 0.20)))
        tb = d.textbbox((0, 0), wtxt, font=f)
        d.text((x + bw//2 - (tb[2]-tb[0])//2, y + 6), wtxt, font=f, fill=fg)

def draw_vertical_region(d, x0, y0, W, hh, st, fg):
    """Two vertical bars side by side within (x0,y0,W,hh)."""
    pad = int(W * 0.04)
    gap = int(W * 0.05)
    colW = (W - 2*pad - gap) // 2
    lf = font(int(colW * 0.34))
    vf = font(int(colW * 0.30))
    lH = d.textbbox((0,0), "PCr", font=lf)[3]
    vH = d.textbbox((0,0), "100%", font=vf)[3]
    barTop = y0 + pad + lH + 6
    barBot = y0 + hh - pad - vH - 6
    barH = barBot - barTop
    lx = x0 + pad
    rx = x0 + pad + colW + gap
    draw_bar_v(d, lx, barTop, colW, barH, st["pctP"], True,  st["consP"], st["flash"], fg)
    draw_bar_v(d, rx, barTop, colW, barH, st["pctG"], False, st["consG"], st["flash"], fg)
    for (cx, lab) in [(lx + colW//2, "PCr"), (rx + colW//2, "GLY")]:
        tb = d.textbbox((0,0), lab, font=lf)
        d.text((cx - (tb[2]-tb[0])//2, y0 + pad), lab, font=lf, fill=fg)
    for (cx, pct) in [(lx + colW//2, st["pctP"]), (rx + colW//2, st["pctG"])]:
        t = "{}%".format(int(round(pct)))
        tb = d.textbbox((0,0), t, font=vf)
        d.text((cx - (tb[2]-tb[0])//2, barBot + 6), t, font=vf, fill=fg)

def render_field_v(W, H, st, bg=BLACK):
    """Vertical side-by-side layout (square/tall slot)."""
    fg = contrast(bg)
    img = Image.new("RGB", (W, H), bg)
    d = ImageDraw.Draw(img)
    draw_vertical_region(d, 0, 0, W, H, st, fg)
    return img

def render_field_full(W, H, st, bg=BLACK):
    """Large single-field screen: vertical tanks on top, summary stats below."""
    fg = contrast(bg)
    img = Image.new("RGB", (W, H), bg)
    d = ImageDraw.Draw(img)
    topH = H * 3 // 5
    draw_vertical_region(d, 0, 0, W, topH, st, fg)
    d.line([6, topH, W-6, topH], fill=fg, width=2)

    sf = font(int(W * 0.058))
    vf = font(int(W * 0.085))
    def ctext(cx, yc, s, f):
        tb = d.textbbox((0,0), s, font=f)
        d.text((cx - (tb[2]-tb[0])//2, yc - (tb[3]-tb[1])//2 - tb[1]), s, font=f, fill=fg)
    half = W // 2
    avail = H - topH
    yHdr = topH + int(avail*0.16); yKj = topH + int(avail*0.46); yFat = topH + int(avail*0.78)
    ctext(W//2, yHdr, "DEPLETED (kJ)", sf)
    ctext(half//2, yKj, "PCr {:.1f}".format(st["kjP"]), vf)
    ctext(half + half//2, yKj, "GLY {:.1f}".format(st["kjG"]), vf)
    fat = int(round(0.75 * (1 - st["pctG"]/100.0) * 100))
    ctext(W//2, yFat, "Fatigue {}%".format(fat), vf)
    return img

def render_field_pair(W, H, st, bg=BLACK):
    """Very-wide layout: two horizontal bars side by side (PCr | GLY)."""
    fg = contrast(bg)
    img = Image.new("RGB", (W, H), bg)
    d = ImageDraw.Draw(img)
    pad = int(W * 0.015)
    gap = int(W * 0.02)
    labelW = int(W * 0.075)
    valueW = int(W * 0.075)
    halfW = (W - gap) // 2
    barH = min(int(H * 0.62), H - 2*pad)
    y = (H - barH) // 2
    lf = font(int(barH * 0.42))
    vf = font(int(barH * 0.48))

    lBarX = pad + labelW
    lBarW = halfW - labelW - valueW - pad
    draw_bar(d, lBarX, y, lBarW, barH, st["pctP"], True, st["consP"], st["flash"], fg)
    rx = halfW + gap
    rBarX = rx + labelW
    rBarW = W - rBarX - valueW - pad
    draw_bar(d, rBarX, y, rBarW, barH, st["pctG"], False, st["consG"], st["flash"], fg)

    def vtext(x, s, f, anchor_right=False):
        tb = d.textbbox((0,0), s, font=f)
        tx = x - (tb[2]-tb[0]) if anchor_right else x
        d.text((tx, y + barH//2 - (tb[3]-tb[1])//2 - tb[1]), s, font=f, fill=fg)
    vtext(pad, "PCr", lf)
    vtext(halfW, "{}%".format(int(round(st["pctP"]))), vf, anchor_right=True)
    vtext(rx, "GLY", lf)
    vtext(W - pad, "{}%".format(int(round(st["pctG"]))), vf, anchor_right=True)
    return img

def device_frame(field, caption):
    """Wrap a field render in a simple Edge-like bezel with a caption chin.
    Brand on the first chin line, caption centered on a second line (so it never
    collides on narrow/portrait frames)."""
    fw, fh = field.size
    bez = 34
    chin = 96
    W, H = fw + 2*bez, fh + 2*bez + chin
    body = Image.new("RGB", (W, H), (32, 34, 40))
    d = ImageDraw.Draw(body)
    d.rounded_rectangle([0, 0, W-1, H-1], radius=42, fill=(44, 46, 54))
    # side buttons
    d.rounded_rectangle([-6, H//2-40, 6, H//2+40], radius=6, fill=(24,25,30))
    d.rounded_rectangle([W-6, int(H*0.32)-26, W+6, int(H*0.32)+26], radius=6, fill=(24,25,30))
    # screen inset
    body.paste(field, (bez, bez))
    d.rectangle([bez-2, bez-2, bez+fw+1, bez+fh+1], outline=(12,12,14), width=3)
    # chin line 1: brand (left)
    d.text((bez, bez+fh+12), "GARMIN  EDGE", font=font(18), fill=(140,145,155))
    # chin line 2: caption (centered), shrunk to fit
    cs = 26
    cf = font(cs)
    while cs > 12 and d.textbbox((0,0), caption, font=cf)[2] > W - 2*bez:
        cs -= 2
        cf = font(cs)
    tb = d.textbbox((0,0), caption, font=cf)
    d.text((W//2 - (tb[2]-tb[0])//2, bez+fh+44), caption, font=cf, fill=(228,231,238))
    return body

STATES = [
    ("full",   "Easy — tanks full",        dict(pctP=100, pctG=100, consP=0,   consG=0,   flash=True, kjP=0.0,  kjG=0.0)),
    ("surge",  "Surge — spending PCr",      dict(pctP=58,  pctG=96,  consP=190, consG=0,   flash=True, kjP=8.4,  kjG=0.2)),
    ("sustain","Sustained — into glycolytic",dict(pctP=24, pctG=44,  consP=55,  consG=135, flash=True, kjP=12.6, kjG=9.5)),
    ("empty",  "PCr spent — red flash",     dict(pctP=1,   pctG=17,  consP=0,   consG=90,  flash=True, kjP=18.2, kjG=21.0)),
]

def make_screens():
    FW, FH = 900, 300
    frames = []
    for key, cap, st in STATES:
        field = render_field(FW, FH, st)
        dev = device_frame(field, cap)
        p = os.path.join(OUT, "screenshot_{}.png".format(key))
        dev.save(p, "PNG")
        frames.append((cap, dev))
        print("screenshot:", p, os.path.getsize(p)//1024, "KB")
    # combined 2x2 strip for the gallery/README
    cols, rows = 2, 2
    gw, gh = frames[0][1].size
    gap = 30
    strip = Image.new("RGB", (cols*gw + (cols+1)*gap, rows*gh + (rows+1)*gap), (16,17,22))
    for i,(cap,dev) in enumerate(frames):
        r,c = divmod(i, cols)
        strip.paste(dev, (gap + c*(gw+gap), gap + r*(gh+gap)))
    sp = os.path.join(OUT, "screenshots_grid.png")
    strip.save(sp, "PNG")
    print("grid:", sp, os.path.getsize(sp)//1024, "KB")

    # light-background proof: same states rendered on a white field
    WHITE_BG = (255, 255, 255)
    lframes = []
    for key, cap, st in STATES:
        field = render_field(FW, FH, st, bg=WHITE_BG)
        lframes.append((cap, device_frame(field, cap + "  (light)")))
    lstrip = Image.new("RGB", (cols*gw + (cols+1)*gap, rows*gh + (rows+1)*gap), (16,17,22))
    for i,(cap,dev) in enumerate(lframes):
        r,c = divmod(i, cols)
        lstrip.paste(dev, (gap + c*(gw+gap), gap + r*(gh+gap)))
    lp = os.path.join(OUT, "screenshots_grid_light.png")
    lstrip.save(lp, "PNG")
    print("grid(light):", lp, os.path.getsize(lp)//1024, "KB")

    # vertical / side-by-side layout for a square-or-tall (e.g. 1x2) cell
    VW, VH = 360, 560
    vframes = []
    for key, cap, st in STATES:
        field = render_field_v(VW, VH, st)
        dev = device_frame(field, cap)
        p = os.path.join(OUT, "screenshot_v_{}.png".format(key))
        dev.save(p, "PNG")
        vframes.append(dev)
    vgw, vgh = vframes[0].size
    vstrip = Image.new("RGB", (4*vgw + 5*gap, vgh + 2*gap), (16,17,22))
    for i, dev in enumerate(vframes):
        vstrip.paste(dev, (gap + i*(vgw+gap), gap))
    vp = os.path.join(OUT, "screenshots_vertical.png")
    vstrip.save(vp, "PNG")
    print("vertical:", vp, os.path.getsize(vp)//1024, "KB")

    # very-wide layout: two horizontal bars side by side, states stacked in one column
    PW, PH = 1500, 150
    pframes = [device_frame(render_field_pair(PW, PH, st), cap) for _, cap, st in STATES]
    pgw, pgh = pframes[0].size
    pstrip = Image.new("RGB", (pgw + 2*gap, 4*pgh + 5*gap), (16,17,22))
    for i, dev in enumerate(pframes):
        pstrip.paste(dev, (gap, gap + i*(pgh+gap)))
    pp = os.path.join(OUT, "screenshots_wide.png")
    pstrip.save(pp, "PNG")
    print("wide:", pp, os.path.getsize(pp)//1024, "KB")

    # large single-field screen: vertical tanks + summary stats
    LW, LH = 560, 920
    lfrs = [device_frame(render_field_full(LW, LH, st), cap) for _, cap, st in STATES]
    lgw, lgh = lfrs[0].size
    lful = Image.new("RGB", (4*lgw + 5*gap, lgh + 2*gap), (16,17,22))
    for i, dev in enumerate(lfrs):
        lful.paste(dev, (gap + i*(lgw+gap), gap))
    fp = os.path.join(OUT, "screenshots_full.png")
    lful.save(fp, "PNG")
    print("full:", fp, os.path.getsize(fp)//1024, "KB")

def make_palette_icon():
    src_path = os.path.join(OUT, "device_icon_128_24bit.png")
    if not os.path.exists(src_path):
        print("skip palette icon: {} not found — run make_assets.py first "
              "(its make_icons() generates it).".format(src_path))
        return
    src = Image.open(src_path).convert("RGB")
    pal = src.convert("P", palette=Image.ADAPTIVE, colors=256)
    p = os.path.join(OUT, "device_icon_128_8bit_palette.png")
    pal.save(p, "PNG")
    print("palette icon:", p, os.path.getsize(p)//1024, "KB")

if __name__ == "__main__":
    try:
        make_screens()
        make_palette_icon()
    except Exception as e:
        print("ERROR: {}".format(e), file=sys.stderr)
        sys.exit(1)
