#!/usr/bin/env python3
"""Makes the Chrome Web Store images in store/images: five 1280 by 800 screenshots and the 440 by 280 promo tile.

It renders the popup with made-up data (dev/render-previews.sh), places each render beside a headline, and screenshots
the result with a Chrome kept apart from your own, on a scratch data folder.
    python3 -I store/make-images.py "<Chrome or Chrome for Testing binary>" <scratch folder>
"""
import os
import shutil
import subprocess
import sys

STORE = os.path.dirname(os.path.abspath(__file__))
EXT = os.path.dirname(STORE)
LOGO = os.path.join(EXT, "..", "..", "docs", "images", "logo.png")

CSS = """
*{margin:0;box-sizing:border-box}
body{width:1280px;height:800px;overflow:hidden;font-family:-apple-system,system-ui,"Segoe UI",Roboto,sans-serif;background:#EEF3FA;color:#1A1A1A;display:flex;align-items:center;padding:0 96px;gap:72px}
.text{flex:1}
h1{font-size:46px;line-height:1.15;font-weight:700;letter-spacing:-0.5px;margin-bottom:22px}
p{font-size:24px;line-height:1.45;color:#3A3A3A}
.brand{display:flex;align-items:center;gap:12px;font-size:20px;font-weight:600;color:#0F52AD;margin-bottom:28px}
.brand img{width:40px;height:40px;border-radius:9px}
.shot{flex:none;border-radius:14px;overflow:hidden;box-shadow:0 18px 50px rgba(15,82,173,.22),0 0 0 1px rgba(0,0,0,.08);background:#fff}
.shot img{display:block;width:404px}
"""

# (file name, popup render, height shown in points, headline, line under it). Renders are 720 by 1200 pixels, shown
# 404 wide; Home ends at 1115 pixels, so it's cut there rather than showing empty space.
SHOTS = [
    ("1-tabs", "home-light.png", 673 * 1115 / 1200, "Tabs you aren't using go to sleep, so Chrome holds less memory.", "A sleeping tab stays in your tab bar and reloads when you click it. Nothing closes."),
    ("2-extensions", "safe-list-light.png", 674, "Extensions you don't need turn off for a while, then back on by themselves.", "Nothing is removed. During a session, or when memory is tight, they give back their memory. Password managers, blockers, VPNs, and security tools stay on."),
    ("3-held", "held-open-light.png", 674, "Calls, sound, and unsent typing stay awake.", "It shows each tab it keeps loaded and why, so you choose: keep it, sleep it, or close it."),
    ("4-session", "start-session-light.png", 674, "Start a session for the task in front of you.", "Tick the tabs a meeting or project needs. The rest sleep until you want them back."),
    ("5-alone", "alone-dark.png", 674, "Works on its own, or with Cool Head on a Mac.", "On its own, you choose how hard it works. With Cool Head, a free Mac app, tabs sleep only when memory is actually short."),
]

TILE = """<!doctype html><html><head><meta charset=utf-8><style>
*{margin:0;box-sizing:border-box}
body{width:440px;height:280px;overflow:hidden;background:#0F52AD;color:#fff;font-family:-apple-system,system-ui,"Segoe UI",Roboto,sans-serif;display:flex;align-items:center;gap:26px;padding:0 34px}
img{width:112px;height:112px;border-radius:24px}
h1{font-size:30px;line-height:1.1;font-weight:700;margin-bottom:12px}
p{font-size:17px;line-height:1.35}
</style></head><body><img src=logo.png alt=""><div><h1>Cool Head for Chrome</h1><p>Sleeps unused tabs and temporarily turns off extensions you don't need.</p></div></body></html>"""


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    chrome, scratch = sys.argv[1], os.path.abspath(sys.argv[2])
    page = os.path.join(scratch, "pages")
    os.makedirs(page, exist_ok=True)
    subprocess.run(["sh", os.path.join(EXT, "dev", "render-previews.sh"), page, scratch], check=True,
                   env={**os.environ, "CHROME": chrome}, stdout=subprocess.DEVNULL)
    shutil.copy(LOGO, os.path.join(page, "logo.png"))

    def shoot(name, html, size):
        path = os.path.join(page, name + ".html")
        with open(path, "w") as f:
            f.write(html)
        subprocess.run([chrome, "--headless=new", "--user-data-dir=" + os.path.join(scratch, "chrome-shots"),
                        "--no-first-run", "--hide-scrollbars", "--force-device-scale-factor=1", "--window-size=" + size,
                        "--virtual-time-budget=2000", "--screenshot=" + os.path.join(STORE, "images", name + ".png"),
                        "file://" + path], check=True, stderr=subprocess.DEVNULL)

    os.makedirs(os.path.join(STORE, "images"), exist_ok=True)
    for name, render, height, title, line in SHOTS:
        shoot(name, f"""<!doctype html><html><head><meta charset=utf-8><style>{CSS}</style></head><body>
<div class=text><div class=brand><img src=logo.png alt="">Cool Head for Chrome</div><h1>{title}</h1><p>{line}</p></div>
<div class=shot style="width:404px;height:{int(height)}px"><img src="{render}" alt=""></div></body></html>""", "1280,800")
    shoot("promo-tile", TILE, "440,280")
    print(os.path.join(STORE, "images"))


main()
