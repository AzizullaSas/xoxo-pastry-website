# XOXO Pastry — product photo processor.
# Removes the background of a source photo (rembg / u2net), centers the
# subject on a uniform warm-cream radial gradient with a soft shadow, and
# writes a square JPG for images/menu-*.jpg.
#   pip install rembg pillow numpy onnxruntime scipy
#   py scripts/process-photos.py "<src photos dir>" <out dir> [photo numbers...]
# Env: REMBG_MODEL, REMBG_NO_MATTING=1, REMBG_KEEP_LARGEST=1

import sys, os, glob
import numpy as np
from PIL import Image, ImageFilter, ImageDraw, ImageEnhance
from rembg import remove, new_session

CANVAS = 1080
MARGIN = 0.14            # empty fraction around the subject
C_CENTER = (252, 246, 237)   # warm cream center
C_EDGE   = (235, 214, 190)   # deeper cream edge (matches --bg-cream-deep-ish)
SHADOW_RGBA = (74, 46, 31, 80)

SESSION = new_session(os.environ.get("REMBG_MODEL", "u2net"))

def radial_bg(size, c0, c1):
    yy, xx = np.ogrid[0:size, 0:size]
    c = (size - 1) / 2.0
    d = np.sqrt((xx - c) ** 2 + (yy - c) ** 2)
    d = np.clip(d / (size * 0.62), 0, 1) ** 1.35
    arr = np.zeros((size, size, 3), np.uint8)
    for i in range(3):
        arr[..., i] = (c0[i] * (1 - d) + c1[i] * d).astype(np.uint8)
    return Image.fromarray(arr, "RGB").convert("RGBA")

def cutout(src):
    with open(src, "rb") as f:
        data = f.read()
    if os.environ.get("REMBG_NO_MATTING"):
        out = remove(data, session=SESSION)
    else:
        out = remove(
            data, session=SESSION,
            alpha_matting=True,
            alpha_matting_foreground_threshold=240,
            alpha_matting_background_threshold=15,
            alpha_matting_erode_size=11,
        )
    from io import BytesIO
    im = Image.open(BytesIO(out)).convert("RGBA")
    if os.environ.get("REMBG_KEEP_LARGEST"):
        im = keep_largest_component(im)
    bbox = im.getbbox()
    if bbox:
        im = im.crop(bbox)
    return im

def keep_largest_component(im):
    from scipy import ndimage
    a = np.array(im)
    mask = a[..., 3] > 30
    lbl, n = ndimage.label(mask)
    if n <= 1:
        return im
    sizes = ndimage.sum(np.ones_like(lbl), lbl, range(1, n + 1))
    keep = int(np.argmax(sizes)) + 1
    a[..., 3] = np.where(lbl == keep, a[..., 3], 0).astype(np.uint8)
    return Image.fromarray(a, "RGBA")

def enhance(im):
    rgb = im.convert("RGB")
    rgb = ImageEnhance.Color(rgb).enhance(1.08)
    rgb = ImageEnhance.Contrast(rgb).enhance(1.05)
    rgb = ImageEnhance.Brightness(rgb).enhance(1.02)
    rgb = rgb.convert("RGBA")
    rgb.putalpha(im.split()[3])
    return rgb

def process(src, dst):
    sub = enhance(cutout(src))
    avail = int(CANVAS * (1 - 2 * MARGIN))
    w, h = sub.size
    s = min(avail / w, avail / h)
    nw, nh = max(1, int(w * s)), max(1, int(h * s))
    sub = sub.resize((nw, nh), Image.LANCZOS)

    canvas = radial_bg(CANVAS, C_CENTER, C_EDGE)
    px = (CANVAS - nw) // 2
    py = (CANVAS - nh) // 2 - int(CANVAS * 0.01)

    shadow = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    sd = ImageDraw.Draw(shadow)
    cx = CANVAS / 2.0
    base = py + nh
    sd.ellipse([cx - nw * 0.40, base - nh * 0.05, cx + nw * 0.40, base + nh * 0.10],
               fill=SHADOW_RGBA)
    shadow = shadow.filter(ImageFilter.GaussianBlur(30))
    canvas = Image.alpha_composite(canvas, shadow)

    canvas.alpha_composite(sub, (px, py))
    canvas.convert("RGB").save(dst, "JPEG", quality=88)
    print("ok ->", os.path.basename(dst))

MAP = {
    19: "menu-signature", 27: "menu-basque", 26: "menu-baby-basque",
    6: "menu-ny-cookies", 11: "menu-tartlets", 16: "menu-meringue-roll",
    28: "menu-tiramisu", 18: "menu-hawaiian-honey",
}

if __name__ == "__main__":
    srcdir = sys.argv[1]
    outdir = sys.argv[2]
    os.makedirs(outdir, exist_ok=True)
    only = set(int(x) for x in sys.argv[3:]) if len(sys.argv) > 3 else set(MAP)
    for n, name in MAP.items():
        if n not in only:
            continue
        matches = glob.glob(os.path.join(srcdir, "photo_%d_*.jpg" % n))
        if not matches:
            print("MISSING source", n); continue
        process(matches[0], os.path.join(outdir, name + ".jpg"))
