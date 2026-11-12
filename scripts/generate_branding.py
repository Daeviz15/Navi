"""
Navi Brand Asset & Icon Generator.
Generates:
  - Master 1024x1024 app icon (assets/branding/app_icon_1024.png)
  - Adaptive icon foreground (assets/branding/app_icon_foreground.png)
  - Android mipmap PNGs: mdpi (48), hdpi (72), xhdpi (96), xxhdpi (144), xxxhdpi (192)
  - Android round mipmap PNGs: ic_launcher_round.png
  - Android adaptive foreground drawables
"""

import math
import os
from PIL import Image, ImageDraw, ImageFilter

def create_master_icon(size=1024):
    # Render at 4x for extreme antialiasing quality
    s = size * 4
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    # 1. Background squircle / rounded rect with subtle deep obsidian gradient
    pad = s * 0.04
    radius = s * 0.22

    # Draw gradient background squircle
    bg_mask = Image.new("L", (s, s), 0)
    bg_mask_draw = ImageDraw.Draw(bg_mask)
    bg_mask_draw.rounded_rectangle([pad, pad, s - pad, s - pad], radius=radius, fill=255)

    # Base background (Pure Black #000000)
    bg_grad = Image.new("RGBA", (s, s), (0, 0, 0, 255))

    # Composite background into squircle
    final_bg = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    final_bg.paste(bg_grad, (0, 0), bg_mask)

    # Squircle border stroke (ultra fine gold accent)
    border_draw = ImageDraw.Draw(final_bg)
    border_draw.rounded_rectangle([pad, pad, s - pad, s - pad], radius=radius, outline=(245, 158, 11, 40), width=int(s * 0.005))

    # 2. Main Symbol: Architectural "N" Compass Needle
    # Designed with precision coordinates centered in the icon
    symbol_layer = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    sym_draw = ImageDraw.Draw(symbol_layer)

    mid_x = s * 0.5
    mid_y = s * 0.52

    # Dimensions of the 'N' geometry
    w = s * 0.46
    h = s * 0.48
    stem_w = s * 0.095

    left_x = mid_x - w * 0.5
    right_x = mid_x + w * 0.5
    top_y = mid_y - h * 0.5
    bot_y = mid_y + h * 0.5

    # Left pillar: angled bottom and top cut
    p_left = [
        (left_x, top_y + stem_w * 0.6),
        (left_x + stem_w, top_y),
        (left_x + stem_w, bot_y),
        (left_x, bot_y - stem_w * 0.6),
    ]

    # Right pillar: matching left pillar
    p_right = [
        (right_x - stem_w, top_y),
        (right_x, top_y + stem_w * 0.6),
        (right_x, bot_y - stem_w * 0.6),
        (right_x - stem_w, bot_y),
    ]

    # Dynamic Diagonal Chevron (Points like a North-East compass arrow)
    p_diag = [
        (left_x, top_y + stem_w * 0.6),
        (left_x + stem_w * 1.05, top_y),
        (right_x, bot_y - stem_w * 0.6),
        (right_x - stem_w * 1.05, bot_y),
    ]

    # Draw left pillar with deep warm amber tone
    sym_draw.polygon(p_left, fill=(217, 119, 6, 255))

    # Draw right pillar with warm amber tone
    sym_draw.polygon(p_right, fill=(245, 158, 11, 255))

    # Draw the dynamic diagonal with a brilliant glowing gold gradient
    diag_mask = Image.new("L", (s, s), 0)
    diag_mask_draw = ImageDraw.Draw(diag_mask)
    diag_mask_draw.polygon(p_diag, fill=255)

    diag_grad = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d_draw = ImageDraw.Draw(diag_grad)
    for y in range(int(top_y), int(bot_y)):
        t = (y - top_y) / (bot_y - top_y)
        # Gradient from bright luminous yellow-gold at top-left to deep amber at bottom-right
        r = int(254 - 30 * t)
        g = int(240 - 70 * t)
        b = int(138 - 110 * t)
        d_draw.line([(0, y), (s, y)], fill=(r, g, b, 255))

    symbol_layer.paste(diag_grad, (0, 0), diag_mask)

    # 3. Add inner navigation needle highlight (a sharp faceted prism cut on diagonal)
    needle_facet = [
        (left_x + stem_w * 0.2, top_y + stem_w * 0.5),
        (left_x + stem_w * 0.85, top_y + stem_w * 0.1),
        (right_x - stem_w * 0.2, bot_y - stem_w * 0.5),
    ]
    sym_draw.polygon(needle_facet, fill=(255, 255, 255, 75))

    # 4. Compass Needle Waypoint Beacon (Golden glowing star/orb at top-right or center)
    beacon_x = right_x - stem_w * 0.5
    beacon_y = top_y + stem_w * 0.3
    beacon_r = s * 0.038

    # Outer soft glow around beacon
    for glow_i in range(int(beacon_r * 2.8), int(beacon_r), -4):
        alpha = int(45 * (1.0 - glow_i / (beacon_r * 2.8)))
        sym_draw.ellipse(
            [beacon_x - glow_i, beacon_y - glow_i, beacon_x + glow_i, beacon_y + glow_i],
            fill=(251, 191, 36, alpha),
        )

    # Inner core beacon
    sym_draw.ellipse(
        [beacon_x - beacon_r, beacon_y - beacon_r, beacon_x + beacon_r, beacon_y + beacon_r],
        fill=(255, 255, 255, 255),
    )

    # Subtle drop shadow of the symbol onto background
    shadow = symbol_layer.copy()
    shadow = shadow.filter(ImageFilter.GaussianBlur(radius=s * 0.025))
    shadow_dark = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    shadow_mask = shadow.split()[3]
    shadow_dark_draw = ImageDraw.Draw(shadow_dark)
    shadow_dark_draw.rectangle([0, 0, s, s], fill=(0, 0, 0, 160))
    shadow_applied = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    shadow_applied.paste(shadow_dark, (0, int(s * 0.015)), shadow_mask)

    # Combine everything
    result = Image.alpha_composite(final_bg, shadow_applied)
    result = Image.alpha_composite(result, symbol_layer)

    # Downscale to target size with high-quality Lanczos resampling
    final = result.resize((size, size), Image.Resampling.LANCZOS)
    return final


def create_foreground_icon(size=1024):
    """Generates the centered symbol on transparent background for Android adaptive icons."""
    s = size * 4
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))

    mid_x = s * 0.5
    mid_y = s * 0.5

    # Dimensions: scaled to fit comfortably inside the adaptive icon safe circle (66% of canvas)
    w = s * 0.38
    h = s * 0.40
    stem_w = s * 0.08

    left_x = mid_x - w * 0.5
    right_x = mid_x + w * 0.5
    top_y = mid_y - h * 0.5
    bot_y = mid_y + h * 0.5

    symbol_layer = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    sym_draw = ImageDraw.Draw(symbol_layer)

    p_left = [
        (left_x, top_y + stem_w * 0.6),
        (left_x + stem_w, top_y),
        (left_x + stem_w, bot_y),
        (left_x, bot_y - stem_w * 0.6),
    ]

    p_right = [
        (right_x - stem_w, top_y),
        (right_x, top_y + stem_w * 0.6),
        (right_x - stem_w, bot_y),
        (right_x, bot_y - stem_w * 0.6),
    ]

    p_diag = [
        (left_x, top_y + stem_w * 0.6),
        (left_x + stem_w * 1.05, top_y),
        (right_x, bot_y - stem_w * 0.6),
        (right_x - stem_w * 1.05, bot_y),
    ]

    sym_draw.polygon(p_left, fill=(217, 119, 6, 255))
    sym_draw.polygon(p_right, fill=(245, 158, 11, 255))

    diag_mask = Image.new("L", (s, s), 0)
    diag_mask_draw = ImageDraw.Draw(diag_mask)
    diag_mask_draw.polygon(p_diag, fill=255)

    diag_grad = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d_draw = ImageDraw.Draw(diag_grad)
    for y in range(int(top_y), int(bot_y)):
        t = (y - top_y) / (bot_y - top_y)
        r = int(254 - 30 * t)
        g = int(240 - 70 * t)
        b = int(138 - 110 * t)
        d_draw.line([(0, y), (s, y)], fill=(r, g, b, 255))
    symbol_layer.paste(diag_grad, (0, 0), diag_mask)

    needle_facet = [
        (left_x + stem_w * 0.2, top_y + stem_w * 0.5),
        (left_x + stem_w * 0.85, top_y + stem_w * 0.1),
        (right_x - stem_w * 0.2, bot_y - stem_w * 0.5),
    ]
    sym_draw.polygon(needle_facet, fill=(255, 255, 255, 75))

    beacon_x = right_x - stem_w * 0.5
    beacon_y = top_y + stem_w * 0.3
    beacon_r = s * 0.032

    for glow_i in range(int(beacon_r * 2.8), int(beacon_r), -4):
        alpha = int(45 * (1.0 - glow_i / (beacon_r * 2.8)))
        sym_draw.ellipse(
            [beacon_x - glow_i, beacon_y - glow_i, beacon_x + glow_i, beacon_y + glow_i],
            fill=(251, 191, 36, alpha),
        )

    sym_draw.ellipse(
        [beacon_x - beacon_r, beacon_y - beacon_r, beacon_x + beacon_r, beacon_y + beacon_r],
        fill=(255, 255, 255, 255),
    )

    final = symbol_layer.resize((size, size), Image.Resampling.LANCZOS)
    return final


def create_round_icon(size=1024):
    """Generates a circular variant for Android round launcher icons."""
    master = create_master_icon(size)
    mask = Image.new("L", (size, size), 0)
    draw = ImageDraw.Draw(mask)
    draw.ellipse([size * 0.03, size * 0.03, size * 0.97, size * 0.97], fill=255)
    
    round_img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    round_img.paste(master, (0, 0), mask)
    return round_img


def main():
    base_dir = r"c:\Users\David\Documents\codes\navi"
    assets_dir = os.path.join(base_dir, "assets", "branding")
    res_dir = os.path.join(base_dir, "android", "app", "src", "main", "res")
    os.makedirs(assets_dir, exist_ok=True)

    print("Generating master 1024x1024 icon...")
    master = create_master_icon(1024)
    master.save(os.path.join(assets_dir, "app_icon_1024.png"), "PNG")

    print("Generating foreground 1024x1024 icon...")
    fg = create_foreground_icon(1024)
    fg.save(os.path.join(assets_dir, "app_icon_foreground.png"), "PNG")

    print("Generating round 1024x1024 icon...")
    round_master = create_round_icon(1024)
    round_master.save(os.path.join(assets_dir, "app_icon_round.png"), "PNG")

    # Mipmap specifications
    mipmaps = {
        "mipmap-mdpi": 48,
        "mipmap-hdpi": 72,
        "mipmap-xhdpi": 96,
        "mipmap-xxhdpi": 144,
        "mipmap-xxxhdpi": 192,
    }

    for folder, px in mipmaps.items():
        folder_path = os.path.join(res_dir, folder)
        os.makedirs(folder_path, exist_ok=True)

        # Standard icon
        icon_resized = master.resize((px, px), Image.Resampling.LANCZOS)
        icon_resized.save(os.path.join(folder_path, "ic_launcher.png"), "PNG")

        # Round icon
        round_resized = round_master.resize((px, px), Image.Resampling.LANCZOS)
        round_resized.save(os.path.join(folder_path, "ic_launcher_round.png"), "PNG")

        # Foreground for adaptive
        fg_resized = fg.resize((px, px), Image.Resampling.LANCZOS)
        fg_resized.save(os.path.join(folder_path, "ic_launcher_foreground.png"), "PNG")
        print(f"Saved {folder} ({px}x{px})")

    # Also save ic_launcher_foreground into drawable
    drawable_dir = os.path.join(res_dir, "drawable")
    os.makedirs(drawable_dir, exist_ok=True)
    fg_108 = fg.resize((432, 432), Image.Resampling.LANCZOS)
    fg_108.save(os.path.join(drawable_dir, "ic_launcher_foreground.png"), "PNG")

    print("All branding assets generated successfully!")

if __name__ == "__main__":
    main()

