#!/usr/bin/env python3
"""v6.19: builds the X9 iPhone/iPad app icon set (ios/Runner/Assets.xcassets/AppIcon.appiconset) from the brand
artwork x9-icon-1024.png. iOS icons must be square, opaque (no alpha) PNGs; iOS rounds the corners itself.
Run:  python3 tool/make_ios_icons.py   (needs Pillow)."""
import json
import os
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, '..', 'ios', 'Runner', 'Assets.xcassets', 'AppIcon.appiconset')
BRAND = os.environ.get('X9_BRAND_DIR', os.path.join(HERE, '..', '..', 'x9_core', 'assets', 'brand'))

# (idiom, size in points, scale)
ICONS = [
    ('iphone', 20, 2), ('iphone', 20, 3), ('iphone', 29, 1), ('iphone', 29, 2), ('iphone', 29, 3),
    ('iphone', 40, 2), ('iphone', 40, 3), ('iphone', 60, 2), ('iphone', 60, 3),
    ('ipad', 20, 1), ('ipad', 20, 2), ('ipad', 29, 1), ('ipad', 29, 2), ('ipad', 40, 1), ('ipad', 40, 2),
    ('ipad', 76, 1), ('ipad', 76, 2), ('ipad', 83.5, 2),
    ('ios-marketing', 1024, 1),
]


def fmt(v):
    return ('%g' % v)


def main():
    src = Image.open(os.path.join(BRAND, 'x9-icon-1024.png')).convert('RGBA')
    flat = Image.new('RGB', src.size, (230, 28, 36))
    flat.paste(src, (0, 0), src)
    os.makedirs(OUT, exist_ok=True)
    images, done = [], {}
    for idiom, pt, scale in ICONS:
        px = round(pt * scale)
        name = 'Icon-App-%sx%s@%dx.png' % (fmt(pt), fmt(pt), scale)
        if name not in done:
            flat.resize((px, px), Image.LANCZOS).save(os.path.join(OUT, name), optimize=True)
            done[name] = px
        images.append({'size': '%sx%s' % (fmt(pt), fmt(pt)), 'idiom': idiom, 'filename': name, 'scale': '%dx' % scale})
    with open(os.path.join(OUT, 'Contents.json'), 'w') as f:
        json.dump({'images': images, 'info': {'version': 1, 'author': 'xcode'}}, f, indent=2)
    print('wrote %d icons to %s' % (len(done), os.path.normpath(OUT)))


if __name__ == '__main__':
    main()
