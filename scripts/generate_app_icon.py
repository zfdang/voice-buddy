#!/usr/bin/env python3
"""
Generate Voice Buddy application icon (AppIcon.icns) and mascot.png from
01_3d_plush_menubar_icon_1024.jpg with edge defringing, soft shadow, and centering.
"""

import os
import sys
import tempfile
import subprocess
import cv2
import numpy as np
from PIL import Image, ImageFilter
from scipy.ndimage import binary_fill_holes

def main():
    root_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
    src_path = os.path.join(root_dir, "icons", "icon_concepts", "01_3d_plush_menubar_icon_1024.jpg")
    res_dir = os.path.join(root_dir, "Sources", "VoiceBuddyApp", "Resources")

    if not os.path.exists(src_path):
        print(f"Error: Source image not found at {src_path}", file=sys.stderr)
        sys.exit(1)

    os.makedirs(res_dir, exist_ok=True)
    print(f"==> Processing plush mascot from {src_path}...")

    # 1. Load image
    img = cv2.imread(src_path)
    if img is None:
        print(f"Error: Failed to read image {src_path}", file=sys.stderr)
        sys.exit(1)

    # 2. GrabCut foreground segmentation
    mask = np.zeros(img.shape[:2], np.uint8)
    bgd_model = np.zeros((1, 65), np.float64)
    fgd_model = np.zeros((1, 65), np.float64)
    rect = (175, 75, 785, 815)
    cv2.grabCut(img, mask, rect, bgd_model, fgd_model, 5, cv2.GC_INIT_WITH_RECT)
    mask_bin = np.where((mask == 2) | (mask == 0), 0, 1).astype(np.uint8)

    # Keep largest connected component and fill holes
    num_labels, labels, stats, _ = cv2.connectedComponentsWithStats(mask_bin)
    largest_label = 1 + np.argmax(stats[1:, cv2.CC_STAT_AREA])
    mask_clean = (labels == largest_label)
    mask_clean = binary_fill_holes(mask_clean).astype(np.uint8) * 255

    # 3. Soft alpha edge transition
    dist_in = cv2.distanceTransform(mask_clean, cv2.DIST_L2, 5)
    dist_out = cv2.distanceTransform(255 - mask_clean, cv2.DIST_L2, 5)
    alpha = np.clip((dist_in - dist_out + 1.2) / 2.4, 0.0, 1.0)

    # 4. Color defringing against white studio background
    F = img.astype(float)
    W = 254.0
    safe_alpha = np.maximum(alpha[:, :, None], 0.01)
    unblended = (F - (1.0 - alpha[:, :, None]) * W) / safe_alpha
    unblended = np.clip(unblended, 0, 255).astype(np.uint8)

    unblended_rgb = cv2.cvtColor(unblended, cv2.COLOR_BGR2RGB)
    rgba_pil = Image.fromarray(np.dstack([unblended_rgb, (alpha * 255).astype(np.uint8)]))

    # 5. Center mascot on 1024x1024 canvas
    bbox = rgba_pil.getbbox()
    cx = (bbox[0] + bbox[2]) / 2.0
    cy = (bbox[1] + bbox[3]) / 2.0
    shift_x = int(round(512 - cx))
    shift_y = int(round(512 - cy))

    centered_mascot = Image.new("RGBA", (1024, 1024), (0, 0, 0, 0))
    centered_mascot.paste(rgba_pil, (shift_x, shift_y), rgba_pil)

    # 6. Subtle macOS ambient drop shadow
    alpha_channel = centered_mascot.split()[3]
    shadow_mask = Image.new("L", (1024, 1024), 0)
    shadow_mask.paste(alpha_channel, (0, 14))
    shadow_blur = shadow_mask.filter(ImageFilter.GaussianBlur(radius=20))
    shadow_layer = Image.new("RGBA", (1024, 1024), (0, 0, 0, 0))
    shadow_alpha = np.array(shadow_blur).astype(float) * 0.35
    shadow_layer.putalpha(Image.fromarray(shadow_alpha.astype(np.uint8)))

    final_icon = Image.alpha_composite(shadow_layer, centered_mascot)

    # Save mascot.png
    mascot_png = os.path.join(res_dir, "mascot.png")
    final_icon.save(mascot_png, "PNG")
    print(f"==> Saved {mascot_png}")

    # 7. Generate AppIcon.iconset & compile AppIcon.icns
    with tempfile.TemporaryDirectory() as tmp_dir:
        iconset_dir = os.path.join(tmp_dir, "AppIcon.iconset")
        os.makedirs(iconset_dir, exist_ok=True)

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
            resized = final_icon.resize((sz, sz), Image.Resampling.LANCZOS)
            resized.save(os.path.join(iconset_dir, filename), "PNG")

        icns_path = os.path.join(res_dir, "AppIcon.icns")
        subprocess.run(["iconutil", "-c", "icns", iconset_dir, "-o", icns_path], check=True)
        print(f"==> Generated {icns_path} ({os.path.getsize(icns_path)} bytes)")

    print("==> App icon generation complete!")

if __name__ == "__main__":
    main()
