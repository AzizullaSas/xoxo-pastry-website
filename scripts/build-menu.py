# One-off generator that built the poster-style per-flavor menu cards from
# the original photos in "Меню XOXO PASTRY". Resizes/compresses into
# images/menu/ (no background removal) and emits the menu HTML snippet.

# Rebuild the menu as poster-style per-flavor cards using the original
# (un-cut) photos. Resizes/compresses each mapped photo into images/menu/
# and emits the menu HTML snippet. No background removal.
import sys, os, glob, html
from PIL import Image, ImageOps, ImageFilter, ImageEnhance

SRC = sys.argv[1]
OUTIMG = "images/menu"
os.makedirs(OUTIMG, exist_ok=True)

# category -> dict(title, sub, items)
# item: (name, emoji, desc, price, photo_number_or_None, slug)
MENU = [
 ("Signature Cheesecakes", "Two sizes · prices as 6″ / 8″", [
   ("Coconut Strawberry", "\U0001F353", "Coconut cheesecake with strawberry filling", "6″ $45 · 8″ $70", 3),
   ("Pistachio Raspberry", "\U0001F49A", "Pistachio cheesecake with raspberry confit and pistachio cream", "6″ $50 · 8″ $85", 19),
   ("Honey", "\U0001F36F", "Delicate vanilla honey cheesecake with honey layers", "6″ $45 · 8″ $75", 12),
   ("Cherry Chocolate", "\U0001F352", "Black Forest — chocolate cheesecake, cherry confit and white chocolate ganache", "6″ $45 · 8″ $75", 2),
   ("Raspberry Mousse", "\U0001FAD0", "Raspberry cheesecake with white chocolate mousse and fresh raspberries", "6″ $45 · 8″ $75", 4),
   ("Mint Blueberry", "\U0001FAD0", "Two-layer mint and blueberry cheesecake with blueberry ganache", "6″ $45 · 8″ $70", 5),
   ("Triple Chocolate", "\U0001F36B", "Rich triple-chocolate cheesecake", "6″ $45 · 8″ $70", None),
   ("Baklava", "\U0001F36F", "Creamy cheesecake layered with baklava and pistachios", "8″ only $80", 17),
 ]),
 ("Basque Cheesecake", "Gluten free · caramelized Spanish-style · 8″", [
   ("Classic Vanilla", "", "Caramelized crust, soft melt-in-mouth center", "$65", None),
   ("Matcha", "\U0001F375", "Stone-ground matcha with a caramelized top", "$65", 27),
   ("Chocolate Ice Cream", "\U0001F368", "Rich chocolate Basque", "$65", None),
   ("Triple Chocolate", "\U0001F36B", "Deep triple-chocolate Basque", "$70", 13),
   ("Pistachio", "\U0001F49A", "Pistachio Basque cheesecake", "$75", 24),
   ("Tiramisu", "☕", "Coffee-soaked tiramisu Basque", "$75", 22),
   ("Lilikoi Mango", "\U0001F96D", "Passion fruit and mango Basque", "$80", 29),
 ]),
 ("Baby Basque Cheesecake", "Gluten free · 6″ · serves 2–4 · $45 each", [
   ("Brownie Biscoff", "", "Brownie base with a Biscoff glaze", "$45", 26),
   ("Brownie Vanilla", "", "Brownie base with vanilla cheesecake", "$45", 14),
   ("Raspberry Pistachio", "", "Raspberry and pistachio", "$45", None),
   ("Lilikoi-Mango", "\U0001F96D", "Passion fruit and mango", "$45", 23),
   ("Chocolate Cherry", "\U0001F352", "Chocolate cheesecake with cherry", "$45", 25),
 ]),
 ("NY Cookies", "Thick &amp; gooey · $7 each · min 4", [
   ("Pistachio", "\U0001F49A", "Stuffed pistachio cookie", "$7", 6),
   ("Nutella", "\U0001F36B", "Stuffed chocolate-hazelnut cookie", "$7", 8),
   ("Red Velvet", "❤️", "Stuffed red velvet cookie", "$7", None),
   ("Lotus", "", "Stuffed Lotus Biscoff cookie", "$7", 7),
 ]),
 ("Tartlets", "Crispy shell, creamy filling · $27 · box of 3", [
   ("Tiramisu", "☕", "Cocoa-dusted mascarpone tartlet", "$27", 10),
   ("Berry", "\U0001F353", "Vanilla cream tartlet with fresh strawberries", "$27", 11),
   ("Pistachio Raspberry", "\U0001F49A", "Pistachio cream and raspberry confit", "$27", 1),
 ]),
 ("Fruit Desserts", "Box of 7", [
   ("Assorted Box", "\U0001F36B", "Glossy chocolate-shell bonbons with a surprise center — Coffee, Mango, Raspberry, Banana, Lilikoi, Pistachio, Blueberry", "$70", 9),
 ]),
 ("Meringue Roll", "", [
   ("Meringue Roll", "\U0001F353", "Light meringue with cream cheese, pistachios and fresh raspberries", "$60", 16),
 ]),
 ("Tiramisu", "", [
   ("Tiramisu", "☕", "Mascarpone cream and coffee-soaked savoiardi", "Whole cake $70 · cup $8–$9", 28),
 ]),
 ("Hawaiian Honey Cake", "", [
   ("Hawaiian Honey Cake", "\U0001F36F", "Honey layers with house-made salted caramel", "$80", 18),
 ]),
]

def slugify(cat, name):
    base = (cat.split()[0] + "-" + name).lower()
    return "".join(c if c.isalnum() else "-" for c in base).strip("-").replace("--", "-")

def process_photo(num, slug):
    matches = glob.glob(os.path.join(SRC, "photo_%d_*.jpg" % num))
    if not matches:
        print("MISSING", num); return None
    im = Image.open(matches[0])
    im = ImageOps.exif_transpose(im).convert("RGB")
    # web resize: cap long side at 1000
    w, h = im.size
    s = min(1.0, 1000.0 / max(w, h))
    if s < 1.0:
        im = im.resize((round(w * s), round(h * s)), Image.LANCZOS)
    im = ImageEnhance.Color(im).enhance(1.05)
    im = ImageEnhance.Contrast(im).enhance(1.03)
    im = im.filter(ImageFilter.UnsharpMask(radius=2, percent=60, threshold=2))
    out = os.path.join(OUTIMG, slug + ".jpg")
    im.save(out, "JPEG", quality=82, optimize=True)
    return im.size

def esc(s):
    return html.escape(s, quote=True)

lines = []
ind = "        "
for cat, sub, items in MENU:
    lines.append(ind + '<div class="menu-cat reveal">')
    lines.append(ind + '  <header class="menu-cat__head">')
    lines.append(ind + '    <h3 class="menu-cat__title">%s</h3>' % esc(cat))
    if sub:
        lines.append(ind + '    <p class="menu-cat__sub">%s</p>' % sub)
    lines.append(ind + '  </header>')
    lines.append(ind + '  <ul class="fcard-list">')
    for name, emoji, desc, price, photo in items:
        slug = slugify(cat, name)
        nophoto = photo is None
        dims = None if nophoto else process_photo(photo, slug)
        cls = "fcard reveal" + (" fcard--nophoto" if (nophoto or not dims) else "")
        lines.append(ind + '    <li class="%s">' % cls)
        if dims:
            w, h = dims
            alt = esc("XOXO Pastry %s %s" % (name, cat.rstrip("s")))
            lines.append(ind + '      <div class="fcard__media"><img src="images/menu/%s.jpg" alt="%s" width="%d" height="%d" loading="lazy" decoding="async"></div>' % (slug, alt, w, h))
        lines.append(ind + '      <div class="fcard__body">')
        nm = esc(name) + (' <span class="fcard__emoji">%s</span>' % emoji if emoji else "")
        lines.append(ind + '        <h4 class="fcard__name">%s</h4>' % nm)
        lines.append(ind + '        <p class="fcard__desc">%s</p>' % esc(desc))
        lines.append(ind + '        <p class="fcard__price">%s</p>' % esc(price))
        lines.append(ind + '      </div>')
        lines.append(ind + '    </li>')
    lines.append(ind + '  </ul>')
    lines.append(ind + '</div>')

snippet = "\n".join(lines) + "\n"
with open("_menu_snippet.html", "w", encoding="utf-8") as f:
    f.write(snippet)
print("\nwrote _menu_snippet.html  cards:", snippet.count('class="fcard'))
print("images in images/menu:", len(os.listdir(OUTIMG)))
