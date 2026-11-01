#!/usr/bin/env python3
"""Builds the X9 user-app launcher icons from the brand artwork in /root/x9/brand
(x9-icon-1024.png = full-bleed icon, x9-icon-foreground.png = transparent mark) and writes, under
android/app/src/main/res: mipmap-*/ic_launcher.png, ic_launcher_round.png, ic_launcher_foreground.png
(adaptive layer, 108dp) and drawable-*/splash_mark.png (white splash).  Run:  python3 tool/make_icons.py
(needs Pillow).  The brand artwork must not be recoloured or stretched; it is only resized."""
import os
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, '..', 'android', 'app', 'src', 'main', 'res')
BRAND = os.environ.get('X9_BRAND_DIR', os.path.join(HERE, '..', '..', '..', 'brand'))
SIZES = {'mdpi': 48, 'hdpi': 72, 'xhdpi': 96, 'xxhdpi': 144, 'xxxhdpi': 192}


def load(name):
    return Image.open(os.path.join(BRAND, name)).convert('RGBA')


def round_icon(src, px):
    s = 4 * px
    big = src.resize((s, s), Image.LANCZOS)
    mask = Image.new('L', (s, s), 0)
    ImageDraw.Draw(mask).ellipse([0, 0, s - 1, s - 1], fill=255)
    out = Image.new('RGBA', (s, s), (0, 0, 0, 0))
    out.paste(big, (0, 0), mask)
    return out.resize((px, px), Image.LANCZOS)


def main():
    icon, fg = load('x9-icon-1024.png'), load('x9-icon-foreground.png')
    for name, px in SIZES.items():
        d = os.path.join(ROOT, 'mipmap-' + name)
        os.makedirs(d, exist_ok=True)
        icon.resize((px, px), Image.LANCZOS).save(os.path.join(d, 'ic_launcher.png'))
        round_icon(icon, px).save(os.path.join(d, 'ic_launcher_round.png'))
        # adaptive foreground: 108dp canvas, artwork scaled into the 72dp safe zone
        canvas = round(px * 108 / 48)
        layer = Image.new('RGBA', (canvas, canvas), (0, 0, 0, 0))
        inner = round(canvas * 72 / 108)
        layer.paste(fg.resize((inner, inner), Image.LANCZOS), ((canvas - inner) // 2,) * 2)
        layer.save(os.path.join(d, 'ic_launcher_foreground.png'))
        # splash mark (white splash screen), 96dp
        sd = os.path.join(ROOT, 'drawable-' + name)
        os.makedirs(sd, exist_ok=True)
        m = round(px * 2)
        load('x9-mark-light.png').resize(
            (m, round(m * load('x9-mark-light.png').height / load('x9-mark-light.png').width)), Image.LANCZOS
        ).save(os.path.join(sd, 'splash_mark.png'))
        print('wrote', name, px)


if __name__ == '__main__':
    main()
