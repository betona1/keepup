# 유튜브 썸네일 생성 — 1280x720 (가로) + 1080x1920 (쇼츠/릴스 커버)
import math
import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont, ImageChops

APP = r"E:\app\keepup"
OUT = APP + r"\store_assets\promo"
FONT_XB = APP + r"\assets\fonts\NanumGothic-ExtraBold.ttf"
FONT_BD = APP + r"\assets\fonts\NanumGothic-Bold.ttf"

NAVY_TOP = (21, 28, 47)
NAVY_BOT = (10, 14, 24)
VIOLET = (124, 92, 255)
BLUE = (79, 169, 255)
GOLD = (255, 200, 80)
WHITE = (255, 255, 255)

def bg_make(w, h, glows):
    top, bot = np.array(NAVY_TOP), np.array(NAVY_BOT)
    grad = np.linspace(0, 1, h)[:, None] * (bot - top) + top
    arr = np.repeat(grad[:, None, :], w, axis=1).astype(np.uint8)
    bg = Image.fromarray(arr, "RGB")
    glow = Image.new("RGB", (w, h), (0, 0, 0))
    d = ImageDraw.Draw(glow)
    for box, col in glows:
        d.ellipse(box, fill=col)
    glow = glow.filter(ImageFilter.GaussianBlur(int(min(w, h) * 0.16)))
    return ImageChops.add(bg, glow).convert("RGBA")

def circle_face(path, size):
    face = Image.open(path).convert("RGBA").resize((size, size), Image.LANCZOS)
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).ellipse([0, 0, size - 1, size - 1], fill=255)
    face.putalpha(mask)
    return face

def grad_text(text, font, c1, c2, stroke=8):
    """좌→우 그라데이션 + 어두운 외곽선 텍스트"""
    probe = ImageDraw.Draw(Image.new("RGBA", (1, 1)))
    w = int(probe.textlength(text, font=font)) + stroke * 4
    h = font.size + stroke * 4 + 24
    # 외곽선(그림자)
    im = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.text((stroke * 2, stroke), text, font=font, fill=(8, 10, 18, 255),
           stroke_width=stroke, stroke_fill=(8, 10, 18, 255))
    # 그라데이션 본문
    grad = np.linspace(0, 1, w)[None, :, None] * (np.array(c2) - np.array(c1)) + np.array(c1)
    garr = np.repeat(grad, h, axis=0).astype(np.uint8)
    gimg = Image.fromarray(garr, "RGB").convert("RGBA")
    mask = Image.new("L", (w, h), 0)
    ImageDraw.Draw(mask).text((stroke * 2, stroke), text, font=font, fill=255)
    im.paste(gimg, (0, 0), mask)
    return im

def white_text(text, font, stroke=8, fill=WHITE):
    probe = ImageDraw.Draw(Image.new("RGBA", (1, 1)))
    w = int(probe.textlength(text, font=font)) + stroke * 4
    h = font.size + stroke * 4 + 24
    im = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.text((stroke * 2, stroke), text, font=font, fill=fill,
           stroke_width=stroke, stroke_fill=(8, 10, 18, 255))
    return im

def ring_stamp(face_path, size, c1, c2, tilt=-8):
    pad = int(size * 0.17)
    total = size + pad * 2
    im = Image.new("RGBA", (total, total), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    steps = 60
    rw = max(6, int(size * 0.085))
    for i in range(steps):
        a0 = 360 * i / steps - 90
        c = tuple(int(c1[j] + (c2[j] - c1[j]) * (i / steps)) for j in range(3))
        d.arc([pad - rw, pad - rw, total - pad + rw, total - pad + rw],
              a0, a0 + 360 / steps + 2, fill=c, width=rw)
    im.alpha_composite(circle_face(face_path, size), (pad, pad))
    return im.rotate(tilt, expand=True, resample=Image.BICUBIC)

def star4(size, color):
    im = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    c, r, r2 = size / 2, size / 2, size / 9
    pts = []
    for k in range(8):
        rr = r if k % 2 == 0 else r2
        ang = math.pi / 4 * k - math.pi / 2
        pts.append((c + rr * math.cos(ang), c + rr * math.sin(ang)))
    d.polygon(pts, fill=color + (255,))
    return im.filter(ImageFilter.GaussianBlur(0.6))

def add_border(im, colors, width=8, radius=28):
    d = ImageDraw.Draw(im)
    w, h = im.size
    steps = 90
    for i in range(steps):
        t = i / steps
        c = tuple(int(colors[0][j] + (colors[1][j] - colors[0][j]) * t) for j in range(3))
        # 좌→우로 색이 변하는 테두리: 세로 구간별로 그리기엔 복잡하니 arc 방식 대신 단순 두 번 그림
    d.rounded_rectangle([width // 2, width // 2, w - width // 2 - 1, h - width // 2 - 1],
                        radius=radius, outline=colors[0] + (255,), width=width)
    return im

VAVE = Image.open(APP + r"\assets\character\vave_full.png").convert("RGBA")

# ══════════ 1) 가로 썸네일 1280x720 ══════════
W, H = 1280, 720
c = bg_make(W, H, [
    ([760, 40, 1400, 700], (54, 42, 116)),
    ([-200, 420, 400, 1000], (22, 46, 88)),
])

# 오른쪽: 캐릭터 (전신, 살짝 크게)
vave = VAVE.resize((int(VAVE.width * 620 / VAVE.height), 620), Image.LANCZOS)
c.alpha_composite(vave, (W - vave.width - 60, H - vave.height + 10))

# 캐릭터 옆 5단계 도장 (겹치게, 체크 배지)
stamp = ring_stamp(APP + r"\assets\character\vave_face5.png", 190, VIOLET, (128, 232, 255))
c.alpha_composite(stamp, (W - 330, H - 262))
badge = Image.new("RGBA", (86, 86), (0, 0, 0, 0))
bd = ImageDraw.Draw(badge)
bd.ellipse([0, 0, 85, 85], fill=VIOLET + (255,), outline=(255, 255, 255, 255), width=5)
bd.line([(24, 44), (38, 58)], fill=WHITE, width=9)
bd.line([(38, 58), (64, 30)], fill=WHITE, width=9)
c.alpha_composite(badge, (W - 190, H - 130))

# 반짝이
for s, (x, y) in [(star4(54, (191, 234, 255)), (W - 360, 130)),
                  (star4(38, (255, 224, 130)), (W - 120, 260)),
                  (star4(30, (191, 234, 255)), (W - 520, 460))]:
    c.alpha_composite(s, (x, y))

# 왼쪽 텍스트
t1 = white_text("작심삼일 끝!", ImageFont.truetype(FONT_XB, 108), stroke=10)
t2 = grad_text("도장 찍는", ImageFont.truetype(FONT_XB, 128), (255, 220, 110), (255, 150, 60), stroke=10)
t3 = grad_text("습관 앱", ImageFont.truetype(FONT_XB, 128), (150, 120, 255), (90, 190, 255), stroke=10)
c.alpha_composite(t1, (56, 96))
c.alpha_composite(t2, (48, 232))
c.alpha_composite(t3, (48, 400))

# 하단 브랜드
brand = white_text("LogChallenge · 로그챌린지", ImageFont.truetype(FONT_BD, 40), stroke=6, fill=(220, 226, 245))
c.alpha_composite(brand, (52, 596))

c = add_border(c, (VIOLET, BLUE), width=10, radius=0)
c.convert("RGB").save(OUT + r"\youtube_thumbnail.png", "PNG")
print("가로 썸네일 완료")

# ══════════ 2) 쇼츠/릴스 커버 1080x1920 ══════════
W, H = 1080, 1920
c = bg_make(W, H, [
    ([240, 900, 1240, 1900], (54, 42, 116)),
    ([-250, -150, 500, 550], (22, 46, 88)),
])
t1 = white_text("작심삼일 끝!", ImageFont.truetype(FONT_XB, 104), stroke=10)
t2 = grad_text("도장 찍는", ImageFont.truetype(FONT_XB, 140), (255, 220, 110), (255, 150, 60), stroke=11)
t3 = grad_text("습관 앱", ImageFont.truetype(FONT_XB, 140), (150, 120, 255), (90, 190, 255), stroke=11)
c.alpha_composite(t1, ((W - t1.width) // 2, 170))
c.alpha_composite(t2, ((W - t2.width) // 2, 300))
c.alpha_composite(t3, ((W - t3.width) // 2, 480))

vave2 = VAVE.resize((int(VAVE.width * 900 / VAVE.height), 900), Image.LANCZOS)
c.alpha_composite(vave2, ((W - vave2.width) // 2, 700))
stamp2 = ring_stamp(APP + r"\assets\character\vave_face5.png", 230, VIOLET, (128, 232, 255))
c.alpha_composite(stamp2, (W - 400, 1310))
badge2 = badge.resize((100, 100), Image.LANCZOS)
c.alpha_composite(badge2, (W - 240, 1470))
for s, (x, y) in [(star4(60, (191, 234, 255)), (150, 760)),
                  (star4(42, (255, 224, 130)), (880, 860)),
                  (star4(34, (191, 234, 255)), (200, 1500))]:
    c.alpha_composite(s, (x, y))
brand2 = white_text("LogChallenge · 로그챌린지", ImageFont.truetype(FONT_BD, 44), stroke=6, fill=(220, 226, 245))
c.alpha_composite(brand2, ((W - brand2.width) // 2, 1730))
c.convert("RGB").save(OUT + r"\youtube_thumbnail_shorts.png", "PNG")
print("쇼츠 커버 완료")
