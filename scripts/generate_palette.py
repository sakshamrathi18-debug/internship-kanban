#!/usr/bin/env python3
"""Single source of truth for the app's colours.

Writes Shared/Palette.xcassets (light + dark variant per colour, used by the
app and the widget) and checks every text colour against every card fill for WCAG AA (4.5:1).

Run from the repo root:  python3 scripts/generate_palette.py
"""
import json
import os
import shutil
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ASSETS = os.path.join(ROOT, "Shared", "Palette.xcassets")


def hex_rgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def to_hex(rgb):
    return "#" + "".join(f"{round(c):02X}" for c in rgb)


def blend(top, bottom, alpha):
    """`top` at `alpha` over `bottom`."""
    t, b = hex_rgb(top), hex_rgb(bottom)
    return to_hex(tuple(b[i] + (t[i] - b[i]) * alpha for i in range(3)))


def luminance(h):
    def channel(c):
        c = c / 255
        return c / 12.92 if c <= 0.03928 else ((c + 0.055) / 1.055) ** 2.4
    r, g, b = (channel(c) for c in hex_rgb(h))
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def contrast(a, b):
    la, lb = sorted((luminance(a), luminance(b)), reverse=True)
    return (la + 0.05) / (lb + 0.05)


# DESIGN.md v2 "Priority sections". Priority is the only colour on the board.
# name: (light, dark[, light_alpha, dark_alpha])
colors = {
    "AccentColor": ("#4F6D9A", "#7896C2"),           # system focus ring only
    "Background": ("#F8F7F4", "#131110"),
    "WidgetBackground": ("#F8F7F4", "#131110"),
    "Hairline": ("#000000", "#FFFFFF", 0.08, 0.08),
    "TextPrimary": ("#201C19", "#F0EEEB"),
    "TextSecondary": ("#514C48", "#B9B7B3"),
    "TextTertiary": ("#68625E", "#96938E"),  # dark nudged from #8F8C87 to pass AA on the dark fills
    "Field": ("#000000", "#FFFFFF", 0.045, 0.06),
    "ButtonPrimary": ("#221E1C", "#EAE7E3"),
    "ButtonPrimaryText": ("#FAF8F5", "#181614"),
    "WIPWarning": ("#9A5505", "#F5C076"),
    "Overdue": ("#B23B1D", "#FFA282"),
}
PRIORITIES = {
    #          fill (L, D)            border L, (D hex, D alpha)    ink (L, D)             sep dark alpha
    "High":   (("#FFEAE5", "#3F221E"), "#F3C4BC", ("#BB6E62", 0.32), ("#AF3E30", "#FCA391"), 0.20),
    "Medium": (("#FDF3DA", "#362B17"), "#EAD5AB", ("#C19F61", 0.28), ("#945F0E", "#F0C876"), 0.18),
    "Low":    (("#E7F6EB", "#1F2D23"), "#C1DDC9", ("#6F9F80", 0.28), ("#316847", "#A0D2B1"), 0.18),
}
for name, (fill, border_light, (border_dark, border_alpha), ink, sep_alpha) in PRIORITIES.items():
    colors[f"{name}Fill"] = fill
    colors[f"{name}Border"] = (border_light, border_dark, 1.0, border_alpha)
    colors[f"{name}Ink"] = ink
    colors[f"{name}Separator"] = (border_light, border_dark, 0.70, sep_alpha)
# No priority, and the Done panel.
colors["NoneFill"] = ("#FEFDFC", "#1D1B1A")
colors["NoneBorder"] = ("#000000", "#FFFFFF", 0.08, 0.07)
colors["NoneInk"] = colors["TextTertiary"]
colors["NoneSeparator"] = ("#000000", "#FFFFFF", 0.07, 0.06)


def check_contrast():
    failures = []
    def need(fg_name, bg_light, bg_dark, label, minimum=4.5):
        fl, fd = colors[fg_name][:2]
        for mode, fg, bg in (("light", fl, bg_light), ("dark", fd, bg_dark)):
            r = contrast(fg, bg)
            if r < minimum:
                failures.append(f"{fg_name} on {label} ({mode}): {r:.2f}")
    bg_l, bg_d = colors["Background"]
    for text in ("TextPrimary", "TextSecondary", "TextTertiary", "WIPWarning", "Overdue"):
        need(text, bg_l, bg_d, "Background")
    for p in ("High", "Medium", "Low", "None"):
        fl, fd = colors[f"{p}Fill"]
        for text in ("TextPrimary", "TextSecondary", "TextTertiary", "Overdue", f"{p}Ink"):
            need(text, fl, fd, f"{p}Fill")
    need("ButtonPrimaryText", colors["ButtonPrimary"][0], colors["ButtonPrimary"][1], "ButtonPrimary")
    return failures


def colorset(light, dark, light_alpha=1.0, dark_alpha=1.0):
    def components(h, a):
        r, g, b = hex_rgb(h)
        return {"color-space": "srgb", "components": {
            "red": f"0x{r:02X}", "green": f"0x{g:02X}", "blue": f"0x{b:02X}", "alpha": f"{a:.3f}"}}
    return {
        "colors": [
            {"idiom": "universal", "color": components(light, light_alpha)},
            {"idiom": "universal", "appearances": [{"appearance": "luminosity", "value": "dark"}],
             "color": components(dark, dark_alpha)},
        ],
        "info": {"author": "xcode", "version": 1},
    }


def write_assets():
    if os.path.isdir(ASSETS):
        shutil.rmtree(ASSETS)
    os.makedirs(ASSETS)
    with open(os.path.join(ASSETS, "Contents.json"), "w") as f:
        json.dump({"info": {"author": "xcode", "version": 1}}, f, indent=2)
    for name, value in sorted(colors.items()):
        light, dark = value[0], value[1]
        la, da = (value[2], value[3]) if len(value) == 4 else (1.0, 1.0)
        folder = os.path.join(ASSETS, f"{name}.colorset")
        os.makedirs(folder)
        with open(os.path.join(folder, "Contents.json"), "w") as f:
            json.dump(colorset(light, dark, la, da), f, indent=2)


if __name__ == "__main__":
    problems = check_contrast()
    if problems:
        print("WCAG AA failures:\n  " + "\n  ".join(problems))
        sys.exit(1)
    write_assets()
    print(f"Wrote {len(colors)} colours; all text passes WCAG AA on every surface.")
