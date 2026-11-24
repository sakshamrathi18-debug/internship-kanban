#!/usr/bin/env python3
"""The iPhone's colours: Apple's system palette instead of the Mac's warm one.

Writes iOS/Palette.xcassets with the same colour names as Shared/Palette.xcassets
(so the shared views and widget work unchanged), plus a vivid `<Priority>Accent`
per priority for dots and swipe buttons. Grouped grey background, white cards,
cards tinted with system red / orange / green for priority. Text colours are the accessible
variants and are checked for WCAG AA (4.5:1; 3:1 for the large button labels).

Run from the repo root:  python3 scripts/generate_palette_ios.py
"""
import importlib.util
import json
import os
import shutil
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ASSETS = os.path.join(ROOT, "iOS", "Palette.xcassets")

spec = importlib.util.spec_from_file_location("mac_palette", os.path.join(ROOT, "scripts", "generate_palette.py"))
mac = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mac)
contrast, colorset = mac.contrast, mac.colorset

WHITE, CARD_DARK = "#FFFFFF", "#1C1C1E"

# name: (light, dark[, light_alpha, dark_alpha])
colors = {
    "AccentColor": ("#007AFF", "#0A84FF"),
    "Background": ("#F2F2F7", "#000000"),          # systemGroupedBackground
    "WidgetBackground": ("#F2F2F7", "#000000"),
    "Hairline": ("#3C3C43", "#545458", 0.16, 0.60),  # separator
    "TextPrimary": ("#000000", "#FFFFFF"),
    "TextSecondary": ("#3A3A3C", "#D1D1D6"),
    "TextTertiary": ("#636367", "#A9A9B0"),
    "Field": ("#767680", "#767680", 0.12, 0.24),    # tertiarySystemFill
    "ButtonPrimary": ("#007AFF", "#0A84FF"),        # systemBlue
    "ButtonPrimaryText": ("#FFFFFF", "#FFFFFF"),
    "WIPWarning": ("#AD5700", "#FF9F0A"),
    "Overdue": ("#D70015", "#FF7F78"),
}

# Priority:  ink (accessible text, L, D)   accent (vivid system colour, L, D)
PRIORITIES = {
    "High": (("#D70015", "#FF6961"), ("#FF3B30", "#FF453A")),
    "Medium": (("#AD5700", "#FFB340"), ("#FF9500", "#FF9F0A")),
    "Low": (("#1E7E34", "#30DB5B"), ("#34C759", "#30D158")),
    "None": (("#636367", "#A9A9B0"), ("#8E8E93", "#8E8E93")),
}
blend = mac.blend
# Cards wear a light wash of their priority's system colour; No priority stays white.
FILL_ALPHA = {"High": (0.11, 0.22), "Medium": (0.14, 0.20), "Low": (0.13, 0.20), "None": (0.0, 0.0)}
FILLS = {}
for name, (ink, accent) in PRIORITIES.items():
    fa_l, fa_d = FILL_ALPHA[name]
    fill = (blend(accent[0], WHITE, fa_l), blend(accent[1], CARD_DARK, fa_d))
    FILLS[name] = fill
    colors[f"{name}Fill"] = fill
    if name == "None":
        colors[f"{name}Border"] = ("#000000", "#FFFFFF", 0.05, 0.07)
        colors[f"{name}Separator"] = ("#3C3C43", "#545458", 0.14, 0.55)
    else:
        colors[f"{name}Border"] = (accent[0], accent[1], 0.30, 0.35)
        colors[f"{name}Separator"] = (accent[0], accent[1], 0.22, 0.28)
    colors[f"{name}Ink"] = ink
    colors[f"{name}Accent"] = accent


def check_contrast():
    failures = []

    def need(fg, bg_light, bg_dark, label, minimum=4.5):
        fl, fd = colors[fg][:2]
        for mode, f, b in (("light", fl, bg_light), ("dark", fd, bg_dark)):
            r = contrast(f, b)
            if r < minimum:
                failures.append(f"{fg} on {label} ({mode}): {r:.2f}")

    bg_l, bg_d = colors["Background"]
    for text in ("TextPrimary", "TextSecondary", "TextTertiary", "WIPWarning", "Overdue"):
        need(text, bg_l, bg_d, "Background")
    for p in PRIORITIES:
        for text in ("TextPrimary", "TextSecondary", "TextTertiary", "Overdue", f"{p}Ink"):
            need(text, FILLS[p][0], FILLS[p][1], f"{p}Fill")
    need("ButtonPrimaryText", colors["ButtonPrimary"][0], colors["ButtonPrimary"][1], "ButtonPrimary", minimum=3)
    return failures


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
    print(f"Wrote {len(colors)} iPhone colours; all text passes WCAG AA.")
