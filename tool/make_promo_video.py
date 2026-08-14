# 로그챌린지 홍보 영상 생성 — 1920x1080 30fps ≈35초
# 프레임을 PIL로 그려 ffmpeg(rawvideo 파이프)로 인코딩, BGM은 numpy로 합성
import math
import subprocess
import wave
import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont, ImageChops

APP = r"E:\app\keepup"
SRC = APP + r"\store_assets\screenshots"
OUT_DIR = APP + r"\store_assets\promo"
FONT_XB = APP + r"\assets\fonts\NanumGothic-ExtraBold.ttf"
FONT_BD = APP + r"\assets\fonts\NanumGothic-Bold.ttf"
FONT_RG = APP + r"\assets\fonts\NanumGothic-Regular.ttf"

W, H, FPS = 1920, 1080, 30
NAVY_TOP = (19, 26, 43)
NAVY_BOT = (11, 15, 26)
VIOLET = (124, 92, 255)
BLUE = (79, 169, 255)
GOLD = (255, 194, 77)
WHITE = (255, 255, 255)
MUTED = (176, 186, 210)

# ── 이징 ──
def ease_out_cubic(t): return 1 - (1 - t) ** 3
def ease_out_back(t):
    c1, c3 = 1.70158, 2.70158
    return 1 + c3 * (t - 1) ** 3 + c1 * (t - 1) ** 2
def clamp01(t): return max(0.0, min(1.0, t))

# ── 공용 레이어 ──
def background():
    bg = Image.new("RGB", (W, H))
    top, bot = np.array(NAVY_TOP), np.array(NAVY_BOT)
    grad = np.linspace(0, 1, H)[:, None] * (bot - top) + top
    arr = np.repeat(grad[:, None, :], W, axis=1).astype(np.uint8)
    bg = Image.fromarray(arr, "RGB")
    glow = Image.new("RGB", (W, H), (0, 0, 0))
    d = ImageDraw.Draw(glow)
    d.ellipse([1150, 100, 2050, 1000], fill=(52, 40, 112))
    d.ellipse([-350, 550, 450, 1250], fill=(20, 44, 84))
    glow = glow.filter(ImageFilter.GaussianBlur(200))
    return ImageChops.add(bg, glow)

BG = background().convert("RGBA")

def with_alpha(im, a):
    a = clamp01(a)
    if a >= 0.999: return im
    out = im.copy()
    out.putalpha(out.getchannel("A").point(lambda p: int(p * a)))
    return out

def paste_center(canvas, im, cx, cy, alpha=1.0, scale=1.0):
    if alpha <= 0.005 or scale <= 0.01: return
    if abs(scale - 1) > 0.005:
        im = im.resize((max(1, int(im.width * scale)), max(1, int(im.height * scale))), Image.LANCZOS)
    im = with_alpha(im, alpha)
    x, y = int(cx - im.width / 2), int(cy - im.height / 2)
    # 캔버스 밖(음수)도 안전하게
    canvas.alpha_composite(im, (max(x, -0) if x >= 0 else 0, max(y, 0)) if (x >= 0 and y >= 0) else (0, 0)) if False else None
    if x < 0 or y < 0:
        crop_x, crop_y = max(0, -x), max(0, -y)
        im = im.crop((crop_x, crop_y, im.width, im.height))
        x, y = max(0, x), max(0, y)
    canvas.alpha_composite(im, (x, y))

def text_img(segs_lines, font, line_h, align_left=True):
    """[[('텍스트',색),...], ...] → RGBA 이미지"""
    probe = Image.new("RGBA", (1, 1))
    pd = ImageDraw.Draw(probe)
    widths = [sum(pd.textlength(t, font=font) for t, _ in line) for line in segs_lines]
    w = int(max(widths)) + 8
    h = line_h * len(segs_lines) + 20
    im = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    for i, line in enumerate(segs_lines):
        x = 0 if align_left else (w - widths[i]) / 2
        for t, c in line:
            d.text((x, i * line_h), t, font=font, fill=c)
            x += d.textlength(t, font=font)
    return im

def rounded_phone(path, ph_h=880):
    phone = Image.open(path)
    ph_w = int(phone.width * ph_h / phone.height)
    phone = phone.resize((ph_w, ph_h), Image.LANCZOS)
    mask = Image.new("L", phone.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, ph_w - 1, ph_h - 1], radius=38, fill=255)
    phone = phone.convert("RGBA"); phone.putalpha(mask)
    bezel = Image.new("RGBA", (ph_w + 16, ph_h + 16), (0, 0, 0, 0))
    ImageDraw.Draw(bezel).rounded_rectangle([0, 0, ph_w + 15, ph_h + 15], radius=46, fill=(24, 30, 48, 255))
    bezel.alpha_composite(phone, (8, 8))
    return bezel

def circle_face(path, size):
    face = Image.open(path).convert("RGBA").resize((size, size), Image.LANCZOS)
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).ellipse([0, 0, size - 1, size - 1], fill=255)
    face.putalpha(mask)
    return face

def ring_stamp(face_path, size, ring_colors):
    """그라데이션 링 + 얼굴 도장 (정지 이미지)"""
    pad = int(size * 0.16)
    total = size + pad * 2
    im = Image.new("RGBA", (total, total), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    steps = 48
    rw = max(4, int(size * 0.075))
    for i in range(steps):
        a0 = 360 * i / steps - 90
        c = tuple(int(ring_colors[0][j] + (ring_colors[-1][j] - ring_colors[0][j]) * (i / steps)) for j in range(3))
        d.arc([pad - rw, pad - rw, total - pad + rw, total - pad + rw], a0, a0 + 360 / steps + 2, fill=c, width=rw)
    im.alpha_composite(circle_face(face_path, size), (pad, pad))
    return im

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

F_HEAD = ImageFont.truetype(FONT_XB, 96)
F_HEAD2 = ImageFont.truetype(FONT_XB, 76)
F_SUB = ImageFont.truetype(FONT_RG, 38)
F_BRAND = ImageFont.truetype(FONT_XB, 42)
F_LABEL = ImageFont.truetype(FONT_BD, 30)
F_CTA = ImageFont.truetype(FONT_XB, 46)

BRAND = text_img([[("Log", VIOLET), ("Challenge", BLUE)]], F_BRAND, 56)
LOGO_FACE = circle_face(APP + r"\assets\character\vave_face.png", 66)

def draw_brand(canvas, alpha=1.0):
    paste_center(canvas, LOGO_FACE, 150 + 33, 96, alpha)
    paste_center(canvas, BRAND, 150 + 90 + BRAND.width / 2, 96, alpha)

VAVE_FULL = Image.open(APP + r"\assets\character\vave_full.png").convert("RGBA")
VAVE_FULL = VAVE_FULL.resize((int(VAVE_FULL.width * 640 / VAVE_FULL.height), 640), Image.LANCZOS)

# ── 장면 정의 ──
PHONE_SCENES = [
    ("01_home.png",
     [[("습관을 ", WHITE), ("도장", VIOLET), ("으로", WHITE)], [("남기다", WHITE)]],
     "연속 도장 · 오늘의 목표 · 하루 한 번의 인증"),
    ("02_routines.png",
     [[("선언하고", WHITE)], [("인증하고 ", WHITE), ("쌓는다", BLUE)]],
     "적립형·결과형 루틴, 30일부터 2년까지"),
    ("03_verify.png",
     [[("다섯 가지", VIOLET)], [("인증 방법", WHITE)]],
     "사진 · 타이머 · 녹음 · 영상 · 링크 + 자동 워터마크"),
    ("04_calendar.png",
     [[("달력에 쌓이는", WHITE)], [("도장", BLUE), (" 기록", WHITE)]],
     "63일 뒤엔 도장으로 가득 찬 달력만 남습니다"),
    ("05_alarm.png",
     [[("미룰수록", WHITE)], [("세지는 알람", VIOLET)]],
     "마감 3·1·0.5시간 전 — 놓치면 하나 더"),
]
PHONES = {s[0]: rounded_phone(f"{SRC}\\{s[0]}") for s in PHONE_SCENES}

EVO = [
    ("vave_face.png", [VIOLET, VIOLET], "1단계"),
    ("vave_face2.png", [VIOLET, (55, 180, 255)], "2단계"),
    ("vave_face3.png", [GOLD, (255, 138, 61)], "3단계"),
    ("vave_face4.png", [(255, 243, 176), (255, 109, 0)], "4단계"),
    ("vave_face5.png", [VIOLET, (128, 232, 255)], "5단계"),
]
EVO_STAMPS = [ring_stamp(APP + "\\assets\\character\\" + f, 150 if i < 4 else 210, rc)
              for i, (f, rc, _) in enumerate(EVO)]
EVO_LABELS = [text_img([[(lb, WHITE if i < 4 else (198, 178, 255))]], F_LABEL, 40)
              for i, (_, _, lb) in enumerate(EVO)]
STAR_C = star4(56, (191, 234, 255))
STAR_G = star4(40, (255, 224, 130))

def scene_alpha(t, dur, fade_in=0.5, fade_out=0.45):
    a = 1.0
    if t < fade_in: a = t / fade_in
    if t > dur - fade_out: a = min(a, (dur - t) / fade_out)
    return clamp01(a)

# S1 인트로
def s1(t, dur):
    c = BG.copy()
    a = scene_alpha(t, dur)
    ka = clamp01(t / 0.9)
    paste_center(c, VAVE_FULL, W / 2, H / 2 - 90,
                 alpha=a * ease_out_cubic(ka), scale=1.06 - 0.06 * ease_out_cubic(ka))
    logo_big = text_img([[("Log", VIOLET), ("Challenge", BLUE)]], ImageFont.truetype(FONT_XB, 88), 110)
    ta = clamp01((t - 0.7) / 0.6)
    paste_center(c, logo_big, W / 2, H / 2 + 300 - 24 * (1 - ease_out_cubic(ta)), alpha=a * ta)
    tag = text_img([[("습관을 도장으로 남기다", WHITE)]], ImageFont.truetype(FONT_BD, 44), 60)
    ta2 = clamp01((t - 1.3) / 0.6)
    paste_center(c, tag, W / 2, H / 2 + 396 - 20 * (1 - ease_out_cubic(ta2)), alpha=a * ta2 * 0.92)
    return c

# 폰 장면
def make_phone_scene(shot, headline, sub):
    phone = PHONES[shot]
    head = text_img(headline, F_HEAD, 122)
    subi = text_img([[(sub, MUTED)]], F_SUB, 52)
    def draw(t, dur):
        c = BG.copy()
        a = scene_alpha(t, dur)
        draw_brand(c, a)
        pa = ease_out_cubic(clamp01(t / 0.8))
        px = W - 200 - phone.width / 2 + (1 - pa) * 340
        paste_center(c, phone, px, H / 2 + 8, alpha=a * pa)
        ha = ease_out_cubic(clamp01((t - 0.25) / 0.6))
        paste_center(c, head, 150 + head.width / 2, 420 + 26 * (1 - ha), alpha=a * ha)
        sa = ease_out_cubic(clamp01((t - 0.65) / 0.6))
        paste_center(c, subi, 150 + subi.width / 2, 620 + 18 * (1 - sa), alpha=a * sa)
        return c
    return draw

# S6 진화 하이라이트
def s6(t, dur):
    c = BG.copy()
    a = scene_alpha(t, dur, fade_out=0.5)
    draw_brand(c, a)
    head = text_img([[("도장을 이어가면 ", WHITE), ("진화", VIOLET), ("합니다", WHITE)]], F_HEAD2, 100)
    ha = ease_out_cubic(clamp01(t / 0.6))
    paste_center(c, head, W / 2, 230 - 22 * (1 - ha), alpha=a * ha)
    sub = text_img([[("1주 → 2주 → 3주 → 4주,  마지막은 코스믹 마스터", MUTED)]], F_SUB, 52)
    sa = clamp01((t - 0.4) / 0.5)
    paste_center(c, sub, W / 2, 330, alpha=a * sa)

    xs = [360, 660, 960, 1270, 1610]
    cy = 620
    arrow_f = ImageFont.truetype(FONT_XB, 44)
    for i, (stamp, label) in enumerate(zip(EVO_STAMPS, EVO_LABELS)):
        t0 = 0.9 + i * 0.38
        k = clamp01((t - t0) / 0.42)
        if k <= 0: continue
        sc = ease_out_back(k)
        # 5단계 글로우 펄스
        if i == 4 and k >= 1:
            pulse = 0.55 + 0.35 * math.sin((t - t0) * 3.4)
            glow = Image.new("RGBA", (420, 420), (0, 0, 0, 0))
            ImageDraw.Draw(glow).ellipse([60, 60, 360, 360], fill=(124, 92, 255, int(120 * pulse)))
            glow = glow.filter(ImageFilter.GaussianBlur(46))
            paste_center(c, glow, xs[i], cy, alpha=a)
        paste_center(c, stamp, xs[i], cy, alpha=a * min(1, k * 2), scale=sc)
        la = clamp01((t - t0 - 0.2) / 0.4)
        paste_center(c, label, xs[i], cy + (stamp.height / 2) + 46, alpha=a * la)
        if i < 4:
            ar = clamp01((t - t0 - 0.25) / 0.35)
            arr = text_img([[("→", (140, 150, 180))]], arrow_f, 60)
            paste_center(c, arr, (xs[i] + xs[i + 1]) / 2, cy, alpha=a * ar)
    # 5단계 반짝이
    t5 = 0.9 + 4 * 0.38
    if t > t5 + 0.4:
        tw = t - t5
        for star, (dx, dy, ph, spd) in [
            (STAR_C, (150, -130, 0.0, 2.6)), (STAR_C, (-140, 120, 1.4, 3.1)),
            (STAR_G, (170, 90, 2.3, 2.2)), (STAR_C, (-40, -170, 3.1, 2.9)),
        ]:
            al = clamp01(0.5 + 0.5 * math.sin(tw * spd + ph))
            paste_center(c, star, xs[4] + dx, cy + dy, alpha=a * al,
                         scale=0.7 + 0.3 * al)
    return c

# S7 아웃트로
def gradient_pill(w, h, c1, c2, radius):
    grad = np.linspace(0, 1, w)[None, :, None] * (np.array(c2) - np.array(c1)) + np.array(c1)
    arr = np.repeat(grad, h, axis=0).astype(np.uint8)
    im = Image.fromarray(arr, "RGB").convert("RGBA")
    mask = Image.new("L", (w, h), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, w - 1, h - 1], radius=radius, fill=255)
    im.putalpha(mask)
    return im

PILL = gradient_pill(640, 108, VIOLET, (55, 130, 255), 54)
pd = ImageDraw.Draw(PILL)
pd.polygon([(74, 34), (74, 74), (112, 54)], fill=(255, 255, 255, 255))
pt = "Google Play 무료 다운로드"
pf = ImageFont.truetype(FONT_XB, 36)
pd.text((140, 33), pt, font=pf, fill=WHITE)

def s7(t, dur):
    c = BG.copy()
    a = scene_alpha(t, dur, fade_out=0.9)
    face = circle_face(APP + r"\assets\character\vave_face5.png", 240)
    fa = ease_out_cubic(clamp01(t / 0.7))
    paste_center(c, face, W / 2, 300, alpha=a * fa, scale=0.9 + 0.1 * fa)
    logo_big = text_img([[("Log", VIOLET), ("Challenge", BLUE)]], ImageFont.truetype(FONT_XB, 80), 100)
    paste_center(c, logo_big, W / 2, 490, alpha=a * clamp01((t - 0.3) / 0.5))
    cta = text_img([[("오늘, 첫 도장을 찍어보세요", WHITE)]], F_CTA, 64)
    ca = ease_out_cubic(clamp01((t - 0.6) / 0.5))
    paste_center(c, cta, W / 2, 610 - 16 * (1 - ca), alpha=a * ca)
    ba = ease_out_back(clamp01((t - 1.0) / 0.5))
    paste_center(c, PILL, W / 2, 760, alpha=a * clamp01((t - 1.0) / 0.3), scale=max(0.2, ba))
    web = text_img([[("log.keywordream.com  ·  성과 게시판에서 서로 응원해요", MUTED)]],
                   ImageFont.truetype(FONT_RG, 30), 44)
    paste_center(c, web, W / 2, 880, alpha=a * clamp01((t - 1.4) / 0.5) * 0.9)
    return c

SCENES = [(4.0, s1)]
SCENES += [(4.2, make_phone_scene(*s)) for s in PHONE_SCENES]
SCENES += [(5.8, s6), (4.6, s7)]
TOTAL = sum(d for d, _ in SCENES)
print(f"총 길이 {TOTAL:.1f}s, {int(TOTAL * FPS)}프레임")

# ── BGM 합성 ──
def make_audio(path, seconds):
    sr = 44100
    n = int(sr * seconds)
    out = np.zeros(n)
    def add(sig, t0):
        i0 = int(t0 * sr)
        i1 = min(n, i0 + len(sig))
        if i0 < n: out[i0:i1] += sig[: i1 - i0]
    def pluck(freq, dur=0.55, amp=0.16):
        t = np.linspace(0, dur, int(sr * dur), False)
        env = np.exp(-6.5 * t)
        return amp * env * (np.sin(2 * np.pi * freq * t) + 0.35 * np.sin(4 * np.pi * freq * t))
    def pad(freqs, dur, amp=0.045):
        t = np.linspace(0, dur, int(sr * dur), False)
        env = np.minimum(t / 0.8, 1) * np.minimum((dur - t) / 0.8, 1)
        sig = sum(np.sin(2 * np.pi * f * t + i) for i, f in enumerate(freqs))
        return amp * env * sig
    def bass(freq, dur, amp=0.11):
        t = np.linspace(0, dur, int(sr * dur), False)
        env = np.exp(-1.6 * t)
        return amp * env * np.sin(2 * np.pi * freq * t)

    C4, E4, G4, B3, D4, A3, F4 = 261.63, 329.63, 392.0, 246.94, 293.66, 220.0, 349.23
    C5, E5 = 523.25, 659.26
    chords = [  # (아르페지오 음들, 패드, 베이스)
        ([C4, E4, G4, C5], [C4, E4, G4], 130.81),
        ([B3, D4, G4, D4 * 2], [B3, D4, G4], 98.0),
        ([A3, C4, E4, A3 * 2], [A3, C4, E4], 110.0),
        ([A3, C4, F4, C5], [A3, C4, F4], 87.31),
    ]
    bar = 2.4  # 100bpm 4/4
    t0 = 0.0
    bi = 0
    while t0 < seconds - 2.0:
        arp, pd_, bs = chords[bi % 4]
        add(pad(pd_, bar + 0.3), t0)
        add(bass(bs, bar), t0)
        seq = [arp[0], arp[1], arp[2], arp[1], arp[3], arp[2], arp[1], arp[2]]
        for k, f in enumerate(seq):
            add(pluck(f, amp=0.13 if k % 2 else 0.16), t0 + k * bar / 8)
        t0 += bar
        bi += 1
    add(pad([C4, E4, G4, C5], 3.2, amp=0.06), t0)  # 마무리 코드
    add(bass(130.81, 3.0), t0)
    # 페이드아웃 + 노멀라이즈
    fade = np.ones(n)
    nf = int(2.4 * sr)
    fade[-nf:] = np.linspace(1, 0, nf)
    out *= fade
    out = out / max(1e-9, np.abs(out).max()) * 0.72
    pcm = (out * 32767).astype(np.int16)
    with wave.open(path, "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(sr)
        w.writeframes(pcm.tobytes())

import os
os.makedirs(OUT_DIR, exist_ok=True)
AUDIO = OUT_DIR + r"\bgm.wav"
make_audio(AUDIO, TOTAL)
print("BGM 생성 완료")

# ── 인코딩 ──
out_mp4 = OUT_DIR + r"\promo_35s.mp4"
proc = subprocess.Popen(
    ["ffmpeg", "-y", "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", f"{W}x{H}",
     "-r", str(FPS), "-i", "-", "-i", AUDIO,
     "-c:v", "libx264", "-preset", "medium", "-crf", "18", "-pix_fmt", "yuv420p",
     "-c:a", "aac", "-b:a", "192k", "-shortest", "-movflags", "+faststart", out_mp4],
    stdin=subprocess.PIPE, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

frame_no = 0
for dur, fn in SCENES:
    for i in range(int(dur * FPS)):
        t = i / FPS
        frame = fn(t, dur).convert("RGB")
        proc.stdin.write(frame.tobytes())
        frame_no += 1
        if frame_no % 150 == 0:
            print(f"  {frame_no}프레임 …")
proc.stdin.close()
proc.wait()
print("완료:", out_mp4, f"({frame_no}프레임)")
