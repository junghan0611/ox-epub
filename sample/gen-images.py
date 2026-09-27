#!/usr/bin/env python
"""org2epub 검증용 샘플 이미지 생성.

- cover.png       : 표지 (1600x2560, 1:1.6 비율 — ox-epub 권장)
- figure-flow.png : 본문 그림 (간단한 파이프라인 도식)
- scale-{1..4}.png : 그림 묶음 (OCR 이 한 장씩 뽑아 준 하위 그림 흉내)
한글 렌더는 Noto Serif/Sans CJK KR 사용.
"""
from PIL import Image, ImageDraw, ImageFont
import subprocess

def font(path_query, size):
    out = subprocess.check_output(["fc-match", "-f", "%{file}", path_query]).decode()
    return ImageFont.truetype(out, size)

serif = lambda s: font("Noto Serif CJK KR", s)
sans = lambda s: font("Noto Sans CJK KR", s)

# ---- cover ----
W, H = 1600, 2560
cov = Image.new("RGB", (W, H), "#1a2b3c")
d = ImageDraw.Draw(cov)
d.rectangle([60, 60, W - 60, H - 60], outline="#c8a24a", width=6)
def center(draw, y, text, fnt, fill):
    w = draw.textlength(text, font=fnt)
    draw.text(((W - w) / 2, y), text, font=fnt, fill=fill)
center(d, 700, "조판 검증", serif(150), "#f4f0e6")
center(d, 920, "ox-epub 풀세트 샘플", serif(72), "#c8a24a")
center(d, 2200, "junghan0611/ox-epub", sans(56), "#9fb0c0")
cov.save("images/cover.png")

# ---- figure ----
fw, fh = 1310, 360  # 60 + 4*230 + 3*90 + 60
fig = Image.new("RGB", (fw, fh), "white")
d = ImageDraw.Draw(fig)
boxes = ["스캔 PDF", "vision 전사", "org", "EPUB"]
bw, bh, gap = 230, 120, 90
x = 60
cy = fh // 2
f = sans(34)
for i, label in enumerate(boxes):
    d.rounded_rectangle([x, cy - bh // 2, x + bw, cy + bh // 2], radius=16,
                        outline="#1a2b3c", width=4, fill="#eef2f6")
    tw = d.textlength(label, font=f)
    d.text((x + (bw - tw) / 2, cy - 22), label, font=f, fill="#1a2b3c")
    if i < len(boxes) - 1:
        ax = x + bw
        d.line([ax + 8, cy, ax + gap - 8, cy], fill="#c8a24a", width=5)
        d.polygon([(ax + gap - 8, cy - 10), (ax + gap - 8, cy + 10), (ax + gap + 6, cy)], fill="#c8a24a")
    x += bw + gap
fig.save("images/figure-flow.png")

# ---- figure group: one panel per scale ----
pw, ph = 600, 450
panels = [("1 m", "#1a2b3c", 1), ("10 cm", "#2e4a62", 2),
          ("1 cm", "#4a6f8a", 4), ("1 mm", "#7a9bb4", 8)]
for i, (label, bg, n) in enumerate(panels, 1):
    pan = Image.new("RGB", (pw, ph), bg)
    d = ImageDraw.Draw(pan)
    step = pw // (n * 2)
    for gx in range(0, pw, step):
        d.line([gx, 0, gx, ph], fill="#c8a24a", width=1)
    for gy in range(0, ph, step):
        d.line([0, gy, pw, gy], fill="#c8a24a", width=1)
    f = sans(72)
    tw = d.textlength(label, font=f)
    d.rectangle([(pw - tw) / 2 - 24, ph / 2 - 60, (pw + tw) / 2 + 24, ph / 2 + 60],
                fill="#f4f0e6")
    d.text(((pw - tw) / 2, ph / 2 - 48), label, font=f, fill="#1a2b3c")
    pan.save(f"images/scale-{i}.png")

print("wrote images/cover.png, images/figure-flow.png, images/scale-{1..4}.png")
