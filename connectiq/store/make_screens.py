#!/usr/bin/env python3
"""Render in-app screenshots of the Dual-Tank data field (horizontal bars),
mirroring DualTankView.drawBar, at several depletion states; plus a palettized
8-bit device-icon fallback."""
import os
from PIL import Image, ImageDraw, ImageFont

OUT = "/home/user/AnaerobicFuelTanks/connectiq/store"
os.makedirs(OUT, exist_ok=True)
FONT = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"

# palette identical to the Monkey C constants
PCR_DULL   = (0x5A, 0x3A, 0x6E)
PCR_BRIGHT = (0xB4, 0x4D, 0xFF)
GLY_DULL   = (0x2E, 0x5A, 0x3A)
GLY_BRIGHT = (0x37, 0xE8, 0x5A)
RED        = (0xFF, 0x00, 0x00)
BLACK      = (0, 0, 0)
WHITE      = (255, 255, 255)

def font(sz):
    try: return ImageFont.truetype(FONT, sz)
    except: return ImageFont.load_default()

def draw_bar(d, x, y, bw, bh, pct, is_pcr, cons, flash_on):
    # outline track (fg white), matches dc.drawRectangle
    d.rectangle([x, y, x + bw, y + bh], outline=WHITE, width=3)
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
    d.rectangle([x + 2, y + 2, x + 2 + fillw, y + bh - 2], fill=col)
    # live consumption readout while draining (inside the bar, right-aligned)
    if draining and not depleted:
        wtxt = "-{}W".format(int(cons))
        f = font(int(bh * 0.34))
        tb = d.textbbox((0, 0), wtxt, font=f)
        d.text((x + bw - 10 - (tb[2]-tb[0]), y + bh//2 - (tb[3]-tb[1])//2 - tb[1]), wtxt, font=f, fill=WHITE)

def render_field(W, H, st):
    """st = dict(pctP,pctG,consP,consG,flash)"""
    img = Image.new("RGB", (W, H), BLACK)
    d = ImageDraw.Draw(img)
    pad = int(W * 0.035)
    labelW = int(W * 0.11)
    valueW = int(W * 0.17)
    barH = min(int(H * 0.30), (H - 3 * pad) // 2)
    yTop = pad + int(H * 0.04)
    yBot = H - pad - barH - int(H * 0.04)
    xBar = pad + labelW
    barW = W - xBar - valueW - pad

    draw_bar(d, xBar, yTop, barW, barH, st["pctP"], True,  st["consP"], st["flash"])
    draw_bar(d, xBar, yBot, barW, barH, st["pctG"], False, st["consG"], st["flash"])

    lf = font(int(barH * 0.5))
    vf = font(int(barH * 0.52))
    for (yy, lab) in [(yTop, "PCr"), (yBot, "GLY")]:
        lb = d.textbbox((0, 0), lab, font=lf)
        d.text((pad, yy + barH//2 - (lb[3]-lb[1])//2 - lb[1]), lab, font=lf, fill=WHITE)
    for (yy, pct) in [(yTop, st["pctP"]), (yBot, st["pctG"])]:
        t = "{}%".format(int(round(pct)))
        tb = d.textbbox((0, 0), t, font=vf)
        d.text((W - pad - (tb[2]-tb[0]), yy + barH//2 - (tb[3]-tb[1])//2 - tb[1]), t, font=vf, fill=WHITE)
    return img

def device_frame(field, caption):
    """Wrap a field render in a simple Edge-like bezel with a caption chin."""
    fw, fh = field.size
    bez = 34
    chin = 74
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
    # chin: brand + caption
    d.text((bez, bez+fh+16), "GARMIN  EDGE", font=font(20), fill=(150,155,165))
    cf = font(26)
    tb = d.textbbox((0,0), caption, font=cf)
    d.text((W - bez - (tb[2]-tb[0]), bez+fh+13), caption, font=cf, fill=(225,228,235))
    return body

STATES = [
    ("full",   "Easy — tanks full",        dict(pctP=100, pctG=100, consP=0,   consG=0,   flash=True)),
    ("surge",  "Surge — spending PCr",      dict(pctP=58,  pctG=96,  consP=190, consG=0,   flash=True)),
    ("sustain","Sustained — into glycolytic",dict(pctP=24, pctG=44,  consP=55,  consG=135, flash=True)),
    ("empty",  "PCr spent — red flash",     dict(pctP=1,   pctG=17,  consP=0,   consG=90,  flash=True)),
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

def make_palette_icon():
    src = Image.open(os.path.join(OUT, "device_icon_128_24bit.png")).convert("RGB")
    pal = src.convert("P", palette=Image.ADAPTIVE, colors=256)
    p = os.path.join(OUT, "device_icon_128_8bit_palette.png")
    pal.save(p, "PNG")
    print("palette icon:", p, os.path.getsize(p)//1024, "KB")

if __name__ == "__main__":
    make_screens()
    make_palette_icon()
