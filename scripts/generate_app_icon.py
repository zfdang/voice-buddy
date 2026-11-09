#!/usr/bin/env python3
"""
Generate Voice Buddy application icon (AppIcon.icns), mascot.png, and menubar icons
from supplied artwork with transparent backgrounds.
"""
from pathlib import Path
from PIL import Image
import numpy as np
import subprocess
import tempfile

root = Path(__file__).resolve().parent.parent
icons_dir = root / 'icons'
res_dir = root / 'Sources' / 'VoiceBuddyApp' / 'Resources'
res_dir.mkdir(parents=True, exist_ok=True)

# 1. App Icon & Mascot
app_src = icons_dir / 'voice_buddy_color_512.png'
app_img = Image.open(app_src)
app_1024 = app_img.resize((1024, 1024), Image.Resampling.LANCZOS)
app_1024.save(res_dir / 'mascot.png')

docs_mascot = root / 'docs' / 'ui' / 'assets' / 'voice-buddy-mascot.png'
if docs_mascot.parent.exists():
    app_1024.save(docs_mascot)

with tempfile.TemporaryDirectory() as tmp_dir:
    iconset_dir = Path(tmp_dir) / 'AppIcon.iconset'
    iconset_dir.mkdir(exist_ok=True)
    sizes = [
        (16, "icon_16x16.png"),
        (32, "icon_16x16@2x.png"),
        (32, "icon_32x32.png"),
        (64, "icon_32x32@2x.png"),
        (128, "icon_128x128.png"),
        (256, "icon_128x128@2x.png"),
        (256, "icon_256x256.png"),
        (512, "icon_256x256@2x.png"),
        (512, "icon_512x512.png"),
        (1024, "icon_512x512@2x.png"),
    ]
    for sz, filename in sizes:
        app_img.resize((sz, sz), Image.Resampling.LANCZOS).save(iconset_dir / filename)
    subprocess.run(['iconutil', '-c', 'icns', str(iconset_dir), '-o', str(res_dir / 'AppIcon.icns')], check=True)

# 2. Status / MenuBar Icons
# Inactive: icons / 'voice_buddy_template_512.png'
# Active: icons / 'voice_buddy_mono_red_dot_512.png'
inactive_img = Image.open(icons_dir / 'voice_buddy_template_512.png')
active_img = Image.open(icons_dir / 'voice_buddy_mono_red_dot_512.png')

status_sources = [
    (inactive_img, ['MenuBarIcon', 'MenuBarIconTemplate']),
    (active_img, ['MenuBarIconColor', 'MenuBarIconActiveTemplate'])
]

boxes = [img.getchannel('A').point(lambda value: 255 if value >= 10 else 0).getbbox()
         for img, _ in status_sources]
left = min(box[0] for box in boxes)
top = min(box[1] for box in boxes)
right = max(box[2] for box in boxes)
bottom = max(box[3] for box in boxes)
side = max(right - left, bottom - top)
side = int(side * 1.05)
if side % 2 != 0:
    side += 1
center_x, center_y = (left + right) // 2, (top + bottom) // 2
crop = (center_x - side // 2, center_y - side // 2,
        center_x - side // 2 + side, center_y - side // 2 + side)

for source, names in status_sources:
    cropped = source.crop(crop)
    for scale in (1, 2):
        suffix = '@2x' if scale == 2 else ''
        sz = 22 * scale
        resized = cropped.resize((sz, sz), Image.Resampling.LANCZOS)
        for name in names:
            arr = np.array(resized.convert('RGBA'))
            arr[:, :, 0] = 0
            arr[:, :, 1] = 0
            arr[:, :, 2] = 0
            Image.fromarray(arr).save(res_dir / f'{name}{suffix}.png')
