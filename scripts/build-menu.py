# Generator for the poster-style per-flavor menu cards.
# Resizes/compresses each mapped photo into images/menu/ (no background
# removal) and emits the menu HTML snippet to _menu_snippet.html.
#   py scripts/build-menu.py "C:\Users\User\Desktop\Меню XOXO PASTRY"
# Photo numbers refer to photo_<N>_*.jpg in that folder (1-29 original,
# 30-33 = later flavor photos: red velvet / chocolate ice cream /
# classic vanilla / raspberry pistachio).
import sys, os, glob, html
from PIL import Image, ImageOps, ImageFilter, ImageEnhance

SRC = sys.argv[1]
OUTIMG = "images/menu"
os.makedirs(OUTIMG, exist_ok=True)

# Each category: (title, sub, items)
# item: (name, emoji, desc, price, photo_number_or_None)
MENU = [
 ("Signature Cheesecakes",
  "Standard 8″ (serves 8–10) · Baby 6″ (serves 2–4) · prices 6″ / 8″", [
   ("Coconut Strawberry", "\U0001F353", "Crispy sablé crust, layered coconut and strawberry cheesecake with whipped coconut cream made from coconut milk and white chocolate", "6″ $45 · 8″ $70", 3),
   ("Pistachio Raspberry", "\U0001F49A", "Buttery sablé crust with pistachio flour, creamy pistachio cheesecake, rich raspberry confit and silky white chocolate pistachio ganache", "6″ $50 · 8″ $85", 19),
   ("Honey", "\U0001F36F", "Crispy sablé crust, honey cheesecake layered with delicate honey sponge and honey crumble", "6″ $45 · 8″ $75", 12),
   ("Cherry Chocolate", "\U0001F352", "Black Forest — crispy sablé crust, rich chocolate cheesecake layered with vibrant cherry confit and finished with silky white chocolate ganache", "6″ $45 · 8″ $75", 2),
   ("Raspberry Mousse", "\U0001FAD0", "Crispy sablé crust, creamy raspberry cheesecake topped with delicate white chocolate mousse and pieces of fresh raspberry", "6″ $45 · 8″ $75", 4),
   ("Mint Blueberry", "\U0001FAD0", "Crispy sablé crust, a two-layer cheesecake infused with refreshing mint and juicy blueberries, crowned with smooth blueberry ganache", "6″ $45 · 8″ $70", 5),
   ("Baklava", "\U0001F36F", "Creamy honey cheesecake on a crisp base, layered with homemade honey syrup-soaked baklava and crushed pistachios", "8″ only $80", 17),
 ]),
 ("Basque Cheesecake",
  "Gluten-free · Spanish-style, caramelized crust and soft, melt-in-your-mouth center · 8″ · serves 8–10", [
   ("Classic Vanilla", "", "", "$65", 32),
   ("Matcha", "\U0001F375", "", "$65", 27),
   ("Chocolate Ice Cream", "\U0001F368", "", "$65", 31),
   ("Pistachio", "\U0001F49A", "", "$75", 24),
   ("Tiramisu", "☕", "", "$75", 22, "Not gluten free"),
   ("Lilikoi Mango", "\U0001F96D", "", "$80", 29),
   ("Triple Chocolate", "\U0001F36B", "", "$70", 13),
 ]),
 ("Baby Basque Cheesecake",
  "Gluten-free · 6.3″ · serves 2–4 · $45 each", [
   ("Brownie Biscoff", "", "", "$45", 26, "Not gluten free"),
   ("Brownie Vanilla", "", "", "$45", 14, "Not gluten free"),
   ("Raspberry Pistachio", "", "", "$45", 33),
   ("Lilikoi-Mango", "\U0001F96D", "", "$45", 23),
   ("Chocolate Cherry", "\U0001F352", "", "$45", 25),
 ]),
 ("NY Cookies",
  "Thick New York–style cookies, soft gooey centers and golden crispy edges · $7 each · min 4", [
   ("Pistachio", "\U0001F49A", "", "$7", 6),
   ("Nutella", "\U0001F36B", "", "$7", 8),
   ("Red Velvet", "❤️", "", "$7", 30),
   ("Lotus", "", "", "$7", 7),
 ]),
 ("Tartlets",
  "Crispy shell, creamy filling and that perfect not-too-sweet balance · $27 · box of 3", [
   ("Tiramisu", "☕", "", "$27", 10),
   ("Berry", "\U0001F353", "", "$27", 11),
   ("Pistachio Raspberry", "\U0001F49A", "", "$27", 1),
 ]),
 ("Fruit Desserts", "Box of 7 · $70 ($10 each)", [
   ("Assorted Box", "\U0001F36B", "Crispy chocolate shell, smooth creamy ganache and a surprise center you won’t expect — Coffee, Mango, Raspberry, Banana, Lilikoi, Pistachio, Blueberry", "$70", 9),
 ]),
 ("Meringue Roll", "", [
   ("Meringue Roll", "\U0001F353", "Light, airy meringue filled with cream cheese, pistachios and fresh raspberries", "$60", 16),
 ]),
 ("Tiramisu", "", [
   ("Tiramisu", "☕", "Classic Italian dessert made with layers of mascarpone cream and coffee-soaked savoiardi cookies", "Whole cake $70 · cup $8 / $9", 28),
 ]),
 ("Hawaiian Honey Cake", "", [
   ("Hawaiian Honey Cake", "\U0001F36F", "Delicate honey cake layers soaked in cream cheese frosting with rich house-made salted caramel", "$80", 18),
 ]),
]

def slugify(cat, name):
    base = (cat.split()[0] + "-" + name).lower()
    return "".join(c if c.isalnum() else "-" for c in base).strip("-").replace("--", "-")

def process_photo(num, slug):
    matches = glob.glob(os.path.join(SRC, "photo_%d_*.jpg" % num))
    if not matches:
        print("MISSING", num); return None
    im = ImageOps.exif_transpose(Image.open(matches[0])).convert("RGB")
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
        lines.append(ind + '    <p class="menu-cat__sub">%s</p>' % esc(sub))
    lines.append(ind + '  </header>')
    lines.append(ind + '  <ul class="fcard-list">')
    for item in items:
        name, emoji, desc, price, photo = item[:5]
        note = item[5] if len(item) > 5 else ""
        slug = slugify(cat, name)
        dims = None if photo is None else process_photo(photo, slug)
        cls = "fcard reveal" + ("" if dims else " fcard--nophoto")
        lines.append(ind + '    <li class="%s">' % cls)
        if dims:
            w, h = dims
            alt = esc("XOXO Pastry %s %s" % (name, cat.rstrip("s")))
            lines.append(ind + '      <div class="fcard__media"><img src="images/menu/%s.jpg" alt="%s" width="%d" height="%d" loading="lazy" decoding="async"></div>' % (slug, alt, w, h))
        lines.append(ind + '      <div class="fcard__body">')
        nm = esc(name) + (' <span class="fcard__emoji">%s</span>' % emoji if emoji else "")
        lines.append(ind + '        <h4 class="fcard__name">%s</h4>' % nm)
        if desc:
            lines.append(ind + '        <p class="fcard__desc">%s</p>' % esc(desc))
        if note:
            lines.append(ind + '        <p class="fcard__note fcard__note--warn">%s</p>' % esc(note))
        lines.append(ind + '        <p class="fcard__price">%s</p>' % esc(price))
        lines.append(ind + '      </div>')
        lines.append(ind + '    </li>')
    lines.append(ind + '  </ul>')
    lines.append(ind + '</div>')

snippet = "\n".join(lines) + "\n"
with open("_menu_snippet.html", "w", encoding="utf-8") as f:
    f.write(snippet)
print("wrote _menu_snippet.html | cards:", snippet.count('<li class="fcard'),
      "| nophoto:", snippet.count('fcard--nophoto'),
      "| images:", len(os.listdir(OUTIMG)))
