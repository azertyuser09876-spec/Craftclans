"""Génère tous les assets graphiques de Craftclans (pixel art) à partir de code.

Usage : python outils/generer_assets.py
Le résultat est déterministe : relancer le script redonne exactement les mêmes images.
Dépendance : Pillow (pip install pillow).
"""
import math
import os
import random

from PIL import Image, ImageDraw, ImageFilter

RACINE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
T = 32  # taille d'une tuile


def chemin(*morceaux):
    p = os.path.join(RACINE, "assets", *morceaux)
    os.makedirs(os.path.dirname(p), exist_ok=True)
    return p


def melange(c1, c2, t):
    return tuple(int(a + (b - a) * t) for a, b in zip(c1, c2))


def eclaircir(c, f):
    return tuple(max(0, min(255, int(v * f))) for v in c[:3]) + tuple(c[3:])


def bruit(rng, base, ecart):
    return tuple(max(0, min(255, v + rng.randint(-ecart, ecart))) for v in base)


# ---------------------------------------------------------------- Sols

def tuile_texturee(rng, base, ecart, taches=()):
    img = Image.new("RGBA", (T, T), base + (255,))
    px = img.load()
    for y in range(T):
        for x in range(T):
            px[x, y] = bruit(rng, base, ecart) + (255,)
    # petites taches (cailloux, brins...)
    for couleur, nombre, taille in taches:
        for _ in range(nombre):
            x, y = rng.randrange(T), rng.randrange(T)
            for dx in range(taille):
                for dy in range(taille):
                    px[(x + dx) % T, (y + dy) % T] = couleur + (255,)
    return img


def brins_herbe(rng, img, clair, fonce, nombre):
    d = ImageDraw.Draw(img)
    for _ in range(nombre):
        x, y = rng.randrange(1, T - 1), rng.randrange(2, T)
        d.point((x, y), fill=fonce)
        d.point((x, y - 1), fill=clair)
        if rng.random() < 0.5:
            d.point((x + 1, y - 2), fill=clair)


def fleurettes(rng, img, nombre):
    d = ImageDraw.Draw(img)
    couleurs = [(240, 240, 250), (250, 220, 70), (230, 90, 120), (150, 140, 240)]
    for _ in range(nombre):
        x, y = rng.randrange(2, T - 2), rng.randrange(2, T - 2)
        c = rng.choice(couleurs)
        for dx, dy in ((0, -1), (-1, 0), (1, 0), (0, 1)):
            d.point((x + dx, y + dy), fill=c)
        d.point((x, y), fill=(250, 200, 60))


def tuile_eau(rng_base, frame):
    img = Image.new("RGBA", (T, T))
    px = img.load()
    for y in range(T):
        for x in range(T):
            v = math.sin((x + frame * 2) * 0.4) * math.cos((y - frame) * 0.35)
            base = melange((40, 96, 176), (62, 130, 210), (v + 1) / 2)
            px[x, y] = base + (255,)
    d = ImageDraw.Draw(img)
    rng = random.Random(77)
    for _ in range(5):
        x, y = rng.randrange(T), rng.randrange(T)
        x = (x + frame * 3) % T
        d.line([(x, y), (x + 3, y)], fill=(170, 210, 245, 255))
    return img


def tuile_lave(frame):
    img = Image.new("RGBA", (T, T))
    px = img.load()
    for y in range(T):
        for x in range(T):
            v = math.sin((x + frame * 2) * 0.35 + math.sin(y * 0.3)) * math.cos((y + frame) * 0.3)
            px[x, y] = melange((190, 50, 20), (255, 170, 40), (v + 1) / 2) + (255,)
    d = ImageDraw.Draw(img)
    rng = random.Random(55)
    for _ in range(4):
        x, y = rng.randrange(T), rng.randrange(T)
        d.ellipse([x - 2, (y + frame * 2) % T - 1, x + 2, (y + frame * 2) % T + 1], fill=(255, 230, 120, 255))
    return img


# Ordre des sols : doit suivre l'énumération Monde.Sol.
SOLS = [
    # (nom, base, écart, taches)
    ("sable", (220, 198, 138), 10, [((196, 172, 112), 6, 1), ((240, 224, 170), 6, 1)]),
    ("herbe", (86, 158, 70), 9, []),
    ("herbe_foncee", (58, 124, 58), 8, []),
    ("terre", (128, 92, 60), 10, [((100, 72, 48), 8, 2), ((150, 116, 80), 6, 1)]),
    ("pierre", (128, 128, 134), 9, [((96, 96, 104), 6, 2), ((160, 160, 166), 6, 1)]),
    ("neige", (232, 238, 246), 6, [((206, 216, 232), 8, 2), ((250, 252, 255), 6, 1)]),
    ("boue", (92, 84, 52), 9, [((70, 64, 40), 8, 3), ((60, 90, 70), 4, 2)]),
    ("cendre", (70, 64, 66), 8, [((50, 46, 48), 8, 2), ((110, 60, 40), 3, 1)]),
    ("herbe_claire", (120, 186, 86), 9, []),
]


def generer_sols():
    """Atlas des sols : ligne 0 = eau animée (4 images), lignes 1..9 = sols (4 variantes),
    ligne 10 = lave animée (4 images)."""
    atlas = Image.new("RGBA", (T * 4, T * 11))
    for f in range(4):
        atlas.paste(tuile_eau(None, f), (f * T, 0))
        atlas.paste(tuile_lave(f), (f * T, T * 10))
    for ligne, (nom, base, ecart, taches) in enumerate(SOLS, start=1):
        for v in range(4):
            rng = random.Random(ligne * 100 + v)
            img = tuile_texturee(rng, base, ecart, taches)
            if nom == "herbe":
                brins_herbe(rng, img, (120, 196, 92), (64, 128, 56), 14)
                if v == 3:
                    fleurettes(rng, img, 3)
            elif nom == "herbe_claire":
                brins_herbe(rng, img, (160, 220, 120), (90, 150, 70), 12)
                fleurettes(rng, img, 2 if v < 3 else 5)
            elif nom == "herbe_foncee":
                brins_herbe(rng, img, (86, 160, 72), (40, 96, 44), 16)
            elif nom == "boue":
                brins_herbe(rng, img, (90, 130, 70), (50, 80, 46), 6)
            elif nom in ("pierre", "cendre"):
                d = ImageDraw.Draw(img)
                x = rng.randrange(4, T - 8)
                d.line([(x, 4), (x + 4, 12), (x + 2, 20)], fill=(90, 90, 98) if nom == "pierre" else (150, 60, 30))
            atlas.paste(img, (v * T, ligne * T))
    atlas.save(chemin("tuiles", "sols.png"))


def generer_decors_biomes():
    # cactus
    img = Image.new("RGBA", (28, 44)); d = ImageDraw.Draw(img)
    ombre(d, 14, 40, 9, 3)
    vert, clair = (60, 140, 70, 255), (100, 180, 100, 255)
    d.rounded_rectangle([10, 6, 18, 41], radius=4, fill=vert, outline=C)
    d.rounded_rectangle([2, 14, 8, 28], radius=3, fill=vert, outline=C)
    d.rectangle([6, 24, 11, 28], fill=vert)
    d.rounded_rectangle([20, 10, 26, 24], radius=3, fill=vert, outline=C)
    d.rectangle([17, 20, 22, 24], fill=vert)
    d.line([(13, 9), (13, 38)], fill=clair)
    for y in range(10, 40, 5):
        d.point((11, y), fill=(240, 240, 220, 255)); d.point((17, y + 2), fill=(240, 240, 220, 255))
    d.ellipse([11, 2, 17, 8], fill=(240, 100, 140, 255))
    img.save(chemin("decors", "cactus.png"))
    # sapin enneigé : le sapin avec de la neige
    sapin = Image.open(chemin("decors", "sapin.png")).convert("RGBA")
    px = sapin.load()
    for y in range(sapin.height):
        for x in range(sapin.width):
            r, g, b, a = px[x, y]
            if a > 0 and g > r + 20 and (y % 14 < 4 or (x + y) % 7 == 0):
                px[x, y] = (236, 242, 250, 255)
    sapin.save(chemin("decors", "sapin_neige.png"))
    # arbre mort
    img = Image.new("RGBA", (48, 72)); d = ImageDraw.Draw(img)
    ombre(d, 24, 67, 14, 4)
    bois, fonce = (90, 70, 60, 255), (60, 46, 40, 255)
    d.polygon([(20, 68), (28, 68), (27, 30), (21, 30)], fill=bois, outline=C)
    for (x1, y1, x2, y2) in [(24, 40, 10, 22), (24, 34, 38, 16), (12, 26, 6, 14), (34, 20, 42, 10), (24, 32, 24, 8)]:
        d.line([(x1, y1), (x2, y2)], fill=C, width=4)
        d.line([(x1, y1), (x2, y2)], fill=bois, width=2)
    d.line([(23, 66), (23, 36)], fill=fonce)
    img.save(chemin("decors", "arbre_mort.png"))
    # roseaux
    img = Image.new("RGBA", (24, 26)); d = ImageDraw.Draw(img)
    rng = random.Random(3)
    for _ in range(7):
        x = rng.randrange(3, 21); h = rng.randrange(12, 22)
        d.line([(x, 25), (x + rng.randrange(-2, 3), 25 - h)], fill=(80, 130, 60, 255), width=1)
        if rng.random() < 0.6:
            d.rectangle([x - 1, 25 - h - 1, x + 1, 25 - h + 4], fill=(110, 70, 40, 255))
    img.save(chemin("decors", "roseaux.png"))
    # rocher volcanique
    roc = Image.open(chemin("decors", "rocher.png")).convert("RGBA")
    px = roc.load()
    for y in range(roc.height):
        for x in range(roc.width):
            r, g, b, a = px[x, y]
            if a > 200 and r > 70:
                v = (r + g + b) // 3
                px[x, y] = (v // 2 + 10, v // 3, v // 3, a)
    d = ImageDraw.Draw(roc)
    d.line([(12, 12), (16, 20), (22, 22)], fill=(255, 120, 40, 255))
    roc.save(chemin("decors", "rocher_noir.png"))
    # os (désert)
    img = Image.new("RGBA", (24, 14)); d = ImageDraw.Draw(img)
    os_c = (236, 228, 206, 255)
    d.line([(4, 8), (20, 6)], fill=os_c, width=3)
    for x, y in ((3, 6), (3, 10), (21, 4), (21, 8)):
        d.ellipse([x - 2, y - 2, x + 2, y + 2], fill=os_c)
    img.save(chemin("decors", "os.png"))


# ---------------------------------------------------------------- Décors

def ombre(d, cx, cy, rx, ry, alpha=90):
    d.ellipse([cx - rx, cy - ry, cx + rx, cy + ry], fill=(0, 0, 0, alpha))


def boule(d, cx, cy, r, couleur, lumiere=True):
    fonce = eclaircir(couleur, 0.7)
    d.ellipse([cx - r - 1, cy - r - 1, cx + r + 1, cy + r + 1], fill=(30, 50, 30, 255))
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=fonce + (255,))
    d.ellipse([cx - r, cy - r, cx + r - 2, cy + r - 3], fill=couleur + (255,))
    if lumiere:
        rr = max(2, r // 3)
        d.ellipse([cx - r // 2 - rr, cy - r // 2 - rr, cx - r // 2 + rr, cy - r // 2 + rr],
                  fill=eclaircir(couleur, 1.25) + (255,))


def generer_arbre():
    img = Image.new("RGBA", (64, 88))
    d = ImageDraw.Draw(img)
    ombre(d, 32, 82, 20, 6)
    d.rectangle([27, 52, 37, 82], fill=(70, 46, 30, 255))
    d.rectangle([29, 52, 33, 82], fill=(104, 70, 44, 255))
    d.line([(27, 82), (24, 85)], fill=(70, 46, 30, 255), width=2)
    d.line([(37, 82), (40, 85)], fill=(70, 46, 30, 255), width=2)
    vert = (66, 140, 60)
    rng = random.Random(5)
    for cx, cy, r in [(20, 44, 15), (44, 44, 15), (32, 30, 18), (20, 26, 12), (44, 26, 12), (32, 48, 14)]:
        boule(d, cx, cy, r, vert)
    for _ in range(40):
        x, y = rng.randrange(10, 54), rng.randrange(12, 58)
        if img.getpixel((x, y))[3] > 0 and img.getpixel((x, y))[1] > 100:
            d.point((x, y), fill=(110, 186, 90, 255))
    img.save(chemin("decors", "arbre.png"))


def generer_sapin():
    img = Image.new("RGBA", (48, 88))
    d = ImageDraw.Draw(img)
    ombre(d, 24, 82, 14, 5)
    d.rectangle([21, 66, 27, 83], fill=(84, 56, 36, 255))
    etages = [(70, 22), (56, 18), (42, 14), (28, 10)]
    for base, demi in etages:
        haut = base - 22
        d.polygon([(24 - demi - 1, base + 1), (24 + demi + 1, base + 1), (24, haut - 1)], fill=(20, 50, 34, 255))
        d.polygon([(24 - demi, base), (24 + demi, base), (24, haut)], fill=(34, 92, 62, 255))
        d.polygon([(24 - demi, base), (24, base), (24, haut)], fill=(48, 118, 76, 255))
    d.point((24, 7), fill=(240, 250, 240, 255))
    img.save(chemin("decors", "sapin.png"))


def generer_rocher():
    img = Image.new("RGBA", (36, 30))
    d = ImageDraw.Draw(img)
    ombre(d, 18, 25, 15, 4)
    pts = [(4, 24), (2, 16), (8, 7), (18, 3), (28, 6), (34, 15), (32, 24)]
    d.polygon([(x, y + 1) for x, y in pts], fill=(50, 50, 58, 255))
    d.polygon(pts, fill=(120, 120, 130, 255))
    d.polygon([(8, 8), (18, 4), (26, 7), (20, 13), (10, 14)], fill=(160, 160, 170, 255))
    d.line([(20, 13), (24, 22)], fill=(80, 80, 90, 255))
    img.save(chemin("decors", "rocher.png"))


def generer_buisson():
    img = Image.new("RGBA", (32, 26))
    d = ImageDraw.Draw(img)
    ombre(d, 16, 22, 13, 3)
    for cx, cy, r in [(10, 15, 7), (22, 15, 7), (16, 10, 8)]:
        boule(d, cx, cy, r, (78, 150, 66))
    for x, y in [(9, 13), (20, 9), (23, 16), (14, 17)]:
        d.rectangle([x, y, x + 1, y + 1], fill=(210, 50, 60, 255))
    img.save(chemin("decors", "buisson.png"))


def generer_fleurs():
    img = Image.new("RGBA", (24, 16))
    d = ImageDraw.Draw(img)
    rng = random.Random(9)
    for _ in range(5):
        x, y = rng.randrange(3, 21), rng.randrange(5, 14)
        d.line([(x, y), (x, y + 3)], fill=(50, 120, 50, 255))
        c = rng.choice([(240, 90, 110), (250, 220, 70), (160, 150, 250), (250, 250, 250)])
        for dx, dy in ((0, -1), (-1, 0), (1, 0), (0, 1)):
            d.point((x + dx, y + dy), fill=c + (255,))
        d.point((x, y), fill=(250, 200, 60, 255))
    img.save(chemin("decors", "fleurs.png"))


def generer_feu():
    """Feu de camp : 4 images côte à côte (32x32)."""
    img = Image.new("RGBA", (32 * 4, 32))
    for f in range(4):
        cadre = Image.new("RGBA", (32, 32))
        d = ImageDraw.Draw(cadre)
        ombre(d, 16, 27, 12, 3)
        for i in range(8):
            a = i / 8 * math.tau
            x, y = 16 + math.cos(a) * 10, 25 + math.sin(a) * 4
            d.ellipse([x - 3, y - 2, x + 3, y + 2], fill=(110, 110, 118, 255))
        d.line([(9, 26), (23, 22)], fill=(92, 60, 36, 255), width=3)
        d.line([(9, 22), (23, 26)], fill=(110, 72, 44, 255), width=3)
        rng = random.Random(f)
        hauteur = 14 + rng.randrange(-2, 3)
        d.polygon([(10, 24), (22, 24), (16 + rng.randrange(-2, 3), 24 - hauteur)], fill=(236, 100, 30, 255))
        d.polygon([(12, 24), (20, 24), (16 + rng.randrange(-1, 2), 24 - hauteur + 5)], fill=(250, 180, 50, 255))
        d.polygon([(14, 24), (18, 24), (16, 24 - hauteur + 9)], fill=(255, 240, 160, 255))
        img.paste(cadre, (f * 32, 0))
    img.save(chemin("decors", "feu_de_camp.png"))


# ---------------------------------------------------------------- Personnages

TENUES = [
    ("rouge", (196, 56, 56)), ("bleu", (56, 96, 200)), ("vert", (56, 150, 72)),
    ("jaune", (220, 176, 48)), ("violet", (136, 72, 184)), ("orange", (224, 120, 40)),
    ("cyan", (48, 168, 184)), ("blanc", (220, 220, 228)),
]
CHEVEUX = [(60, 40, 28), (220, 190, 100), (30, 30, 34), (170, 80, 40), (120, 120, 130), (90, 60, 40), (40, 30, 30), (200, 150, 80)]
PEAU = [(240, 200, 160), (200, 150, 110), (150, 100, 70), (250, 214, 180)]


def dessiner_perso(d, ox, oy, direction, etape, tenue, cheveux, peau):
    """Personnage 32x32 vu de dessus, légèrement incliné. direction : 0 bas, 1 gauche, 2 droite, 3 haut."""
    contour = (28, 24, 30, 255)
    tenue_f = eclaircir(tenue, 0.72)
    pantalon = (70, 60, 80)
    # ombre
    d.ellipse([ox + 9, oy + 27, ox + 23, oy + 31], fill=(0, 0, 0, 80))
    pas = [0, 1, 0, -1][etape]
    rebond = 1 if etape in (1, 3) else 0
    y0 = oy - rebond
    # jambes
    if direction in (0, 3):
        d.rectangle([ox + 12, y0 + 22, ox + 15, y0 + 27 + max(0, pas)], fill=pantalon + (255,), outline=contour)
        d.rectangle([ox + 17, y0 + 22, ox + 20, y0 + 27 + max(0, -pas)], fill=pantalon + (255,), outline=contour)
    else:
        d.rectangle([ox + 13 + pas, y0 + 22, ox + 16 + pas, y0 + 28], fill=pantalon + (255,), outline=contour)
        d.rectangle([ox + 16 - pas, y0 + 22, ox + 19 - pas, y0 + 28], fill=eclaircir(pantalon, 0.8) + (255,), outline=contour)
    # corps
    d.rounded_rectangle([ox + 10, y0 + 13, ox + 22, y0 + 24], radius=3, fill=tenue + (255,), outline=contour)
    d.rectangle([ox + 11, y0 + 20, ox + 21, y0 + 21], fill=(90, 60, 40, 255))  # ceinture
    d.rectangle([ox + 15, y0 + 20, ox + 17, y0 + 21], fill=(220, 190, 80, 255))  # boucle
    # bras
    if direction == 0 or direction == 3:
        d.rectangle([ox + 7, y0 + 14 - pas, ox + 10, y0 + 21 - pas], fill=tenue_f + (255,), outline=contour)
        d.rectangle([ox + 22, y0 + 14 + pas, ox + 25, y0 + 21 + pas], fill=tenue_f + (255,), outline=contour)
    else:
        bx = ox + 14 + (pas * 2)
        d.rectangle([bx, y0 + 14, bx + 4, y0 + 21], fill=tenue_f + (255,), outline=contour)
        d.rectangle([bx + 1, y0 + 20, bx + 3, y0 + 22], fill=peau + (255,))
    # tête
    d.rounded_rectangle([ox + 9, y0 + 2, ox + 23, y0 + 14], radius=4, fill=peau + (255,), outline=contour)
    if direction == 0:
        d.rectangle([ox + 9, y0 + 2, ox + 23, y0 + 6], fill=cheveux + (255,))
        d.rectangle([ox + 9, y0 + 6, ox + 10, y0 + 9], fill=cheveux + (255,))
        d.rectangle([ox + 22, y0 + 6, ox + 23, y0 + 9], fill=cheveux + (255,))
        d.rectangle([ox + 12, y0 + 8, ox + 13, y0 + 10], fill=(30, 30, 40, 255))
        d.rectangle([ox + 19, y0 + 8, ox + 20, y0 + 10], fill=(30, 30, 40, 255))
        d.point((ox + 12, y0 + 8), fill=(255, 255, 255, 255))
        d.point((ox + 19, y0 + 8), fill=(255, 255, 255, 255))
    elif direction == 3:
        d.rounded_rectangle([ox + 9, y0 + 2, ox + 23, y0 + 13], radius=4, fill=cheveux + (255,), outline=contour)
    else:
        gauche = direction == 1
        d.rectangle([ox + 9, y0 + 2, ox + 23, y0 + 6], fill=cheveux + (255,))
        if gauche:
            d.rectangle([ox + 17, y0 + 6, ox + 23, y0 + 11], fill=cheveux + (255,))
            d.rectangle([ox + 11, y0 + 8, ox + 12, y0 + 10], fill=(30, 30, 40, 255))
        else:
            d.rectangle([ox + 9, y0 + 6, ox + 15, y0 + 11], fill=cheveux + (255,))
            d.rectangle([ox + 20, y0 + 8, ox + 21, y0 + 10], fill=(30, 30, 40, 255))


def generer_personnages():
    for i, (nom, tenue) in enumerate(TENUES):
        planche = Image.new("RGBA", (32 * 4, 32 * 4))
        d = ImageDraw.Draw(planche)
        for direction in range(4):
            for etape in range(4):
                dessiner_perso(d, etape * 32, direction * 32, direction, etape, tenue, CHEVEUX[i], PEAU[i % len(PEAU)])
        planche.save(chemin("personnages", f"perso_{i}.png"))


# ---------------------------------------------------------------- Interface et icônes

def degrade_radial(taille, couleur):
    img = Image.new("RGBA", (taille, taille))
    px = img.load()
    c = taille / 2
    for y in range(taille):
        for x in range(taille):
            dist = math.hypot(x - c + 0.5, y - c + 0.5) / c
            a = max(0.0, 1.0 - dist) ** 1.6
            px[x, y] = couleur + (int(255 * a),)
    return img


def generer_icone(taille):
    s = taille / 64
    img = Image.new("RGBA", (taille, taille))
    d = ImageDraw.Draw(img)
    # bouclier
    def P(points):
        return [(x * s, y * s) for x, y in points]
    d.rounded_rectangle([2 * s, 2 * s, 62 * s, 62 * s], radius=12 * s, fill=(34, 48, 66, 255))
    d.polygon(P([(32, 6), (54, 14), (52, 38), (32, 58), (12, 38), (10, 14)]), fill=(20, 26, 34, 255))
    d.polygon(P([(32, 9), (51, 16), (49, 37), (32, 54), (15, 37), (13, 16)]), fill=(70, 140, 76, 255))
    d.polygon(P([(32, 9), (51, 16), (49, 37), (32, 54)]), fill=(56, 118, 62, 255))
    # épée
    d.line(P([(20, 44), (44, 18)]), fill=(225, 228, 236, 255), width=int(4 * s))
    d.line(P([(17, 39), (25, 47)]), fill=(150, 100, 50, 255), width=int(4 * s))
    # pioche
    d.line(P([(44, 44), (24, 22)]), fill=(140, 92, 50, 255), width=int(4 * s))
    d.arc([16 * s, 12 * s, 40 * s, 32 * s], 200, 330, fill=(170, 176, 190, 255), width=int(4 * s))
    return img


def generer_interface():
    generer_icone(512).save(os.path.join(RACINE, "icon.png"))
    generer_icone(192).save(chemin("ui", "icone_192.png"))
    # icône adaptative Android : avant-plan (contenu dans le cercle central) et arrière-plan
    avant = Image.new("RGBA", (432, 432))
    avant.paste(generer_icone(260), (86, 86), generer_icone(260))
    avant.save(chemin("ui", "icone_avant_plan.png"))
    Image.new("RGBA", (432, 432), (34, 48, 66, 255)).save(chemin("ui", "icone_arriere_plan.png"))
    # écran de démarrage
    splash = Image.new("RGBA", (256, 256))
    ic = generer_icone(256)
    splash.paste(ic, (0, 0), ic)
    splash.save(chemin("ui", "demarrage.png"))
    # lumières
    degrade_radial(128, (255, 255, 255)).save(chemin("ui", "lumiere.png"))
    # joystick tactile
    j = Image.new("RGBA", (160, 160))
    d = ImageDraw.Draw(j)
    d.ellipse([2, 2, 157, 157], fill=(255, 255, 255, 40), outline=(255, 255, 255, 140), width=4)
    j.save(chemin("ui", "joystick_fond.png"))
    j = Image.new("RGBA", (72, 72))
    d = ImageDraw.Draw(j)
    d.ellipse([2, 2, 69, 69], fill=(255, 255, 255, 150), outline=(255, 255, 255, 230), width=3)
    j.save(chemin("ui", "joystick_bouton.png"))


# ---------------------------------------------------------------- Étape 1 : rôles et combat

ROLES = ["guerrier", "archer", "mage", "explorateur", "paladin", "assassin", "mineur", "ingenieur"]
C = (28, 24, 30, 255)  # contour


def dessiner_accessoire(d, ox, oy, direction, etape, role):
    """Accessoires d'un rôle, dans un cadre 32x40 (8 pixels de marge en haut pour les chapeaux)."""
    rebond = 1 if etape in (1, 3) else 0
    y0 = oy + 8 - rebond  # même repère que dessiner_perso
    face, dos = direction == 0, direction == 3
    if role == "guerrier":
        metal, ombre_m = (176, 180, 192, 255), (120, 124, 136, 255)
        d.rounded_rectangle([ox + 8, y0 + 0, ox + 24, y0 + 7], radius=4, fill=metal, outline=C)
        d.rectangle([ox + 9, y0 + 5, ox + 23, y0 + 6], fill=ombre_m)
        if face:
            d.rectangle([ox + 15, y0 + 5, ox + 17, y0 + 10], fill=metal, outline=C)
        d.rectangle([ox + 7, y0 + 13, ox + 11, y0 + 16], fill=metal, outline=C)
        d.rectangle([ox + 21, y0 + 13, ox + 25, y0 + 16], fill=metal, outline=C)
    elif role == "archer":
        vert, plume = (60, 120, 60, 255), (210, 50, 50, 255)
        d.polygon([(ox + 8, y0 + 5), (ox + 24, y0 + 5), (ox + 18, y0 - 3)], fill=vert, outline=C)
        d.line([(ox + 20, y0 - 1), (ox + 26, y0 - 6)], fill=plume, width=2)
        if not face:  # carquois dans le dos (de profil : du côté du dos)
            x = {1: ox + 21, 2: ox + 7, 3: ox + 19}[direction]
            d.rectangle([x, y0 + 11, x + 4, y0 + 22], fill=(120, 80, 40, 255), outline=C)
            for i in range(3):
                d.point((x + 1 + i, y0 + 10), fill=(240, 240, 240, 255))
    elif role == "mage":
        violet, etoile = (110, 60, 170, 255), (250, 220, 90, 255)
        d.polygon([(ox + 6, y0 + 5), (ox + 26, y0 + 5), (ox + 19, y0 - 8)], fill=violet, outline=C)
        d.rectangle([ox + 6, y0 + 4, ox + 26, y0 + 6], fill=(90, 46, 140, 255), outline=C)
        d.point((ox + 16, y0 + 0), fill=etoile)
        d.point((ox + 17, y0 - 1), fill=etoile)
        # écharpe
        d.rectangle([ox + 11, y0 + 13, ox + 21, y0 + 15], fill=(240, 200, 80, 255))
    elif role == "explorateur":
        bandeau = (200, 60, 50, 255)
        d.rectangle([ox + 9, y0 + 3, ox + 23, y0 + 5], fill=bandeau, outline=C)
        if direction != 2:
            d.line([(ox + 23, y0 + 4), (ox + 27, y0 + 7)], fill=bandeau, width=2)
        if dos:  # sac à dos, vu de derrière
            d.rounded_rectangle([ox + 10, y0 + 13, ox + 22, y0 + 22], radius=2, fill=(140, 100, 50, 255), outline=C)
            d.rectangle([ox + 12, y0 + 15, ox + 20, y0 + 16], fill=(110, 76, 36, 255))
        elif not face:  # de profil : le sac dépasse du côté du dos
            x = ox + 20 if direction == 1 else ox + 6
            d.rounded_rectangle([x, y0 + 13, x + 6, y0 + 22], radius=2, fill=(140, 100, 50, 255), outline=C)
            d.line([(x + 1, y0 + 15), (x + 5, y0 + 15)], fill=(110, 76, 36, 255))
    elif role == "paladin":
        or_, blanc = (230, 190, 70, 255), (245, 245, 250, 255)
        d.rounded_rectangle([ox + 8, y0 + 0, ox + 24, y0 + 7], radius=5, fill=or_, outline=C)
        d.polygon([(ox + 15, y0 + 0), (ox + 17, y0 + 0), (ox + 16, y0 - 7)], fill=blanc)
        d.line([(ox + 16, y0 - 7), (ox + 20, y0 - 4)], fill=blanc, width=2)
        if face:
            d.rectangle([ox + 12, y0 + 14, ox + 20, y0 + 20], fill=blanc, outline=C)
            d.line([(ox + 16, y0 + 15), (ox + 16, y0 + 19)], fill=or_)
            d.line([(ox + 14, y0 + 16), (ox + 18, y0 + 16)], fill=or_)
    elif role == "assassin":
        capuche, masque = (46, 42, 56, 255), (30, 28, 36, 255)
        d.rounded_rectangle([ox + 8, y0 + 0, ox + 24, y0 + 9], radius=5, fill=capuche, outline=C)
        if face:
            d.rectangle([ox + 10, y0 + 10, ox + 22, y0 + 13], fill=masque)
            d.rectangle([ox + 12, y0 + 7, ox + 13, y0 + 9], fill=(230, 60, 60, 255))
            d.rectangle([ox + 19, y0 + 7, ox + 20, y0 + 9], fill=(230, 60, 60, 255))
        elif dos:
            d.rounded_rectangle([ox + 8, y0 + 0, ox + 24, y0 + 13], radius=5, fill=capuche, outline=C)
        else:
            d.rectangle([ox + 9, y0 + 5, ox + 23, y0 + 9], fill=capuche)
        d.polygon([(ox + 9, y0 + 13), (ox + 23, y0 + 13), (ox + 25, y0 + 24), (ox + 7, y0 + 24)], fill=(46, 42, 56, 160))
    elif role == "mineur":
        jaune, lampe = (230, 190, 50, 255), (255, 250, 200, 255)
        d.rounded_rectangle([ox + 8, y0 - 1, ox + 24, y0 + 7], radius=5, fill=jaune, outline=C)
        d.rectangle([ox + 7, y0 + 5, ox + 25, y0 + 7], fill=(200, 160, 40, 255), outline=C)
        if face:
            d.ellipse([ox + 13, y0 - 1, ox + 19, y0 + 4], fill=lampe, outline=C)
        elif direction in (1, 2):
            x = ox + 8 if direction == 1 else ox + 21
            d.ellipse([x, y0 + 0, x + 4, y0 + 4], fill=lampe, outline=C)
        # bretelles
        d.line([(ox + 12, y0 + 13), (ox + 12, y0 + 22)], fill=(90, 70, 50, 255), width=2)
        d.line([(ox + 20, y0 + 13), (ox + 20, y0 + 22)], fill=(90, 70, 50, 255), width=2)
    elif role == "ingenieur":
        orange, gilet = (240, 130, 40, 255), (250, 200, 40, 255)
        d.rounded_rectangle([ox + 8, y0 - 1, ox + 24, y0 + 6], radius=5, fill=orange, outline=C)
        d.rectangle([ox + 6, y0 + 5, ox + 26, y0 + 6], fill=(210, 100, 30, 255), outline=C)
        d.line([(ox + 16, y0 - 1), (ox + 16, y0 + 5)], fill=(255, 190, 110, 255))
        if face or dos:  # gilet de chantier avec bandes réfléchissantes
            d.line([(ox + 10, y0 + 17), (ox + 22, y0 + 17)], fill=(235, 235, 240, 255), width=2)
            d.line([(ox + 11, y0 + 13), (ox + 11, y0 + 21)], fill=gilet, width=2)
            d.line([(ox + 21, y0 + 13), (ox + 21, y0 + 21)], fill=gilet, width=2)
        else:
            x = ox + 13 if direction == 1 else ox + 15
            d.rectangle([x, y0 + 13, x + 4, y0 + 21], fill=gilet)
            d.line([(x, y0 + 17), (x + 4, y0 + 17)], fill=(235, 235, 240, 255), width=2)


def generer_roles():
    for role in ROLES:
        planche = Image.new("RGBA", (32 * 4, 40 * 4))
        d = ImageDraw.Draw(planche)
        for direction in range(4):
            for etape in range(4):
                dessiner_accessoire(d, etape * 32, direction * 40, direction, etape, role)
        planche.save(chemin("personnages", f"role_{role}.png"))


def generer_armes():
    """Armes tenues en main, pointées vers la droite ; le pivot est à gauche (la main)."""
    armes = {}
    # épée
    img = Image.new("RGBA", (32, 12)); d = ImageDraw.Draw(img)
    d.rectangle([0, 5, 6, 7], fill=(110, 70, 40, 255), outline=C)
    d.rectangle([6, 1, 8, 10], fill=(210, 180, 70, 255), outline=C)
    d.polygon([(9, 4), (27, 4), (31, 6), (27, 8), (9, 8)], fill=(220, 224, 236, 255), outline=C)
    d.line([(10, 6), (27, 6)], fill=(255, 255, 255, 255))
    armes["guerrier"] = img
    # arc
    img = Image.new("RGBA", (16, 32)); d = ImageDraw.Draw(img)
    d.arc([-10, 1, 12, 30], -70, 70, fill=(130, 84, 40, 255), width=3)
    d.line([(6, 3), (6, 28)], fill=(235, 235, 235, 255))
    armes["archer"] = img
    # bâton de mage
    img = Image.new("RGBA", (32, 12)); d = ImageDraw.Draw(img)
    d.line([(0, 6), (24, 6)], fill=(110, 70, 40, 255), width=3)
    d.ellipse([22, 1, 31, 10], fill=(120, 220, 255, 255), outline=C)
    d.point((25, 4), fill=(255, 255, 255, 255))
    armes["mage"] = img
    # dague
    img = Image.new("RGBA", (20, 8)); d = ImageDraw.Draw(img)
    d.rectangle([0, 3, 5, 5], fill=(90, 60, 36, 255), outline=C)
    d.rectangle([5, 1, 6, 7], fill=(160, 160, 170, 255))
    d.polygon([(7, 2), (16, 3), (19, 4), (16, 5), (7, 6)], fill=(220, 224, 236, 255), outline=C)
    armes["explorateur"] = img
    # marteau
    img = Image.new("RGBA", (30, 18)); d = ImageDraw.Draw(img)
    d.line([(0, 9), (20, 9)], fill=(110, 70, 40, 255), width=3)
    d.rectangle([19, 1, 29, 17], fill=(200, 170, 70, 255), outline=C)
    d.rectangle([21, 3, 27, 15], fill=(230, 200, 90, 255))
    armes["paladin"] = img
    # dagues d'assassin (lame sombre)
    img = Image.new("RGBA", (20, 8)); d = ImageDraw.Draw(img)
    d.rectangle([0, 3, 5, 5], fill=(40, 36, 46, 255), outline=C)
    d.polygon([(6, 2), (16, 3), (19, 4), (16, 5), (6, 6)], fill=(150, 60, 200, 255), outline=C)
    armes["assassin"] = img
    # pioche
    img = Image.new("RGBA", (28, 24)); d = ImageDraw.Draw(img)
    d.line([(0, 12), (22, 12)], fill=(110, 70, 40, 255), width=3)
    d.polygon([(18, 1), (23, 6), (27, 12), (23, 18), (18, 23), (21, 12)], fill=(150, 156, 170, 255), outline=C)
    d.line([(21, 4), (24, 12)], fill=(200, 205, 215, 255))
    armes["mineur"] = img
    # clé à molette
    img = Image.new("RGBA", (28, 16)); d = ImageDraw.Draw(img)
    d.line([(0, 8), (19, 8)], fill=(150, 156, 170, 255), width=4)
    d.line([(1, 7), (18, 7)], fill=(200, 205, 215, 255))
    d.ellipse([17, 1, 27, 15], fill=(150, 156, 170, 255), outline=C)
    d.rectangle([23, 5, 27, 10], fill=(0, 0, 0, 0))
    d.line([(23, 5), (23, 10)], fill=C)
    armes["ingenieur"] = img
    for role, img in armes.items():
        img.save(chemin("armes", f"{role}.png"))


def generer_combat():
    # flèche
    img = Image.new("RGBA", (20, 7)); d = ImageDraw.Draw(img)
    d.line([(2, 3), (16, 3)], fill=(130, 90, 50, 255), width=1)
    d.polygon([(15, 0), (20, 3), (15, 6)], fill=(200, 205, 215, 255), outline=C)
    d.polygon([(0, 0), (4, 3), (0, 6)], fill=(230, 60, 60, 255))
    img.save(chemin("combat", "fleche.png"))
    # potions
    for nom, couleur in (("potion_degats", (230, 80, 40)), ("potion_soin", (70, 220, 110))):
        img = Image.new("RGBA", (12, 14)); d = ImageDraw.Draw(img)
        d.ellipse([1, 4, 11, 13], fill=couleur + (255,), outline=C)
        d.rectangle([4, 0, 7, 5], fill=(200, 220, 230, 255), outline=C)
        d.rectangle([4, 0, 7, 1], fill=(140, 90, 50, 255))
        d.point((4, 7), fill=(255, 255, 255, 255))
        img.save(chemin("combat", f"{nom}.png"))
    # coup en arc (balayage)
    img = Image.new("RGBA", (64, 64)); d = ImageDraw.Draw(img)
    for i, a in enumerate((90, 160, 230)):
        d.arc([4 + i * 2, 4 + i * 2, 60 - i * 2, 60 - i * 2], -60, 60, fill=(255, 255, 255, a), width=3)
    img.save(chemin("combat", "balayage.png"))
    # explosions et soins : 4 images de 64x64
    for nom, c1, c2 in (("explosion", (255, 150, 40), (255, 230, 120)), ("soin", (60, 220, 110), (200, 255, 210)),
                        ("impact", (230, 230, 240), (255, 255, 255))):
        planche = Image.new("RGBA", (64 * 4, 64))
        for f in range(4):
            cadre = Image.new("RGBA", (64, 64)); d = ImageDraw.Draw(cadre)
            r = 10 + f * 7
            a = 230 - f * 55
            d.ellipse([32 - r, 32 - r, 32 + r, 32 + r], outline=c1 + (a,), width=4)
            rng = random.Random(f + len(nom))
            for _ in range(10):
                ang = rng.random() * math.tau
                dist = rng.random() * r
                x, y = 32 + math.cos(ang) * dist, 32 + math.sin(ang) * dist
                t = 3 - f // 2
                d.ellipse([x - t, y - t, x + t, y + t], fill=c2 + (a,))
            planche.paste(cadre, (f * 64, 0))
        planche.save(chemin("combat", f"{nom}.png"))
    # bouclier sacré
    img = degrade_radial(64, (255, 220, 120))
    d = ImageDraw.Draw(img)
    d.ellipse([2, 2, 61, 61], outline=(255, 230, 140, 200), width=2)
    img.save(chemin("combat", "bouclier.png"))
    # cercle de visée au sol
    img = Image.new("RGBA", (128, 128)); d = ImageDraw.Draw(img)
    d.ellipse([2, 2, 125, 125], fill=(255, 255, 255, 40), outline=(255, 255, 255, 200), width=3)
    img.save(chemin("combat", "zone.png"))
    # tombe
    img = Image.new("RGBA", (22, 26)); d = ImageDraw.Draw(img)
    ombre(d, 11, 23, 9, 2)
    d.rounded_rectangle([3, 2, 19, 23], radius=7, fill=(150, 150, 160, 255), outline=C)
    d.line([(11, 6), (11, 16)], fill=(90, 90, 100, 255), width=2)
    d.line([(7, 10), (15, 10)], fill=(90, 90, 100, 255), width=2)
    img.save(chemin("combat", "tombe.png"))
    # mannequin d'entraînement
    img = Image.new("RGBA", (28, 44)); d = ImageDraw.Draw(img)
    ombre(d, 14, 40, 10, 3)
    d.rectangle([12, 22, 15, 41], fill=(110, 76, 44, 255), outline=C)
    d.rectangle([3, 16, 24, 19], fill=(110, 76, 44, 255), outline=C)
    d.rounded_rectangle([7, 12, 20, 30], radius=4, fill=(214, 182, 96, 255), outline=C)
    for y in range(14, 30, 3):
        d.line([(8, y), (19, y)], fill=(188, 156, 74, 255))
    d.ellipse([7, 1, 20, 14], fill=(224, 196, 110, 255), outline=C)
    d.ellipse([10, 17, 17, 24], fill=(230, 60, 60, 255), outline=(250, 250, 250, 255))
    d.point((13, 20), fill=(250, 250, 250, 255))
    img.save(chemin("combat", "mannequin.png"))


def icone_role(role, taille=48):
    img = Image.new("RGBA", (taille, taille)); d = ImageDraw.Draw(img)
    fonds = {"guerrier": (160, 60, 50), "archer": (60, 120, 60), "mage": (100, 60, 160),
             "explorateur": (180, 120, 50), "paladin": (190, 160, 60), "assassin": (60, 56, 76),
             "mineur": (110, 96, 84), "ingenieur": (200, 110, 40)}
    d.rounded_rectangle([1, 1, taille - 2, taille - 2], radius=10, fill=fonds[role] + (255,), outline=(20, 20, 26, 255), width=2)
    arme = Image.open(chemin("armes", f"{role}.png"))
    arme = arme.resize((arme.width * 2 if arme.width < 24 else arme.width, arme.height * 2 if arme.width < 24 else arme.height), Image.NEAREST)
    arme = arme.rotate(45 if role != "archer" else 0, expand=True, resample=Image.NEAREST)
    img.paste(arme, ((taille - arme.width) // 2, (taille - arme.height) // 2), arme)
    return img


def generer_icones():
    for role in ROLES:
        icone_role(role).save(chemin("ui", f"role_{role}.png"))
    # esquive
    img = Image.new("RGBA", (48, 48)); d = ImageDraw.Draw(img)
    d.rounded_rectangle([1, 1, 46, 46], radius=10, fill=(50, 110, 170, 255), outline=(20, 20, 26, 255), width=2)
    for i in range(3):
        d.line([(10 + i * 8, 14), (20 + i * 8, 24), (10 + i * 8, 34)], fill=(240, 240, 255, 255), width=3)
    img.save(chemin("ui", "esquive.png"))
    # compétence (étoile)
    img = Image.new("RGBA", (48, 48)); d = ImageDraw.Draw(img)
    d.rounded_rectangle([1, 1, 46, 46], radius=10, fill=(170, 120, 40, 255), outline=(20, 20, 26, 255), width=2)
    pts = []
    for i in range(10):
        a = -math.pi / 2 + i * math.pi / 5
        r = 16 if i % 2 == 0 else 7
        pts.append((24 + math.cos(a) * r, 24 + math.sin(a) * r))
    d.polygon(pts, fill=(255, 230, 120, 255), outline=(90, 60, 10, 255))
    img.save(chemin("ui", "competence.png"))


# ---------------------------------------------------------------- Étape 3 : ressources et inventaire

MINERAIS = {  # id : (couleur, reflet)
    "cuivre": ((206, 118, 60), (250, 180, 120)),
    "fer": ((176, 150, 130), (230, 214, 200)),
    "or": ((236, 190, 50), (255, 240, 150)),
    "mithril": ((110, 200, 220), (210, 250, 255)),
}


def generer_filons():
    for nom, (coul, reflet) in MINERAIS.items():
        roc = Image.open(chemin("decors", "rocher.png")).convert("RGBA")
        d = ImageDraw.Draw(roc)
        rng = random.Random(len(nom) * 13)
        for (x, y) in ((10, 12), (19, 8), (24, 16), (14, 19), (27, 10)):
            x += rng.randrange(-1, 2); y += rng.randrange(-1, 2)
            d.polygon([(x, y - 2), (x + 2, y), (x, y + 2), (x - 2, y)], fill=coul + (255,), outline=(40, 36, 40, 255))
            d.point((x - 1, y - 1), fill=reflet + (255,))
        roc.save(chemin("decors", f"filon_{nom}.png"))
    # cristaux
    img = Image.new("RGBA", (32, 40)); d = ImageDraw.Draw(img)
    ombre(d, 16, 36, 13, 3)
    for (x, h, w, c) in ((9, 20, 5, (170, 90, 230)), (22, 18, 5, (150, 80, 220)), (16, 30, 6, (200, 130, 255))):
        pts = [(x - w, 37), (x - w, 37 - h + 6), (x, 37 - h), (x + w, 37 - h + 6), (x + w, 37)]
        d.polygon(pts, fill=c + (255,), outline=(50, 24, 70, 255))
        d.line([(x - 1, 37 - h + 4), (x - 1, 34)], fill=(240, 220, 255, 255))
    img.save(chemin("decors", "cristal.png"))


def icone_objet(nom):
    img = Image.new("RGBA", (24, 24)); d = ImageDraw.Draw(img)
    if nom == "bois":
        for i, y in enumerate((14, 8)):
            d.rounded_rectangle([3 + i * 2, y, 21 - i * 2, y + 6], radius=3, fill=(150, 100, 56, 255), outline=C)
            d.ellipse([16 - i * 2, y, 22 - i * 2, y + 6], fill=(214, 170, 110, 255), outline=C)
    elif nom == "fibre":
        for x in (8, 12, 16):
            d.line([(x, 21), (x + 2, 4)], fill=(120, 170, 70, 255), width=2)
        d.rectangle([7, 12, 19, 14], fill=(200, 170, 90, 255), outline=C)
    elif nom == "herbe":
        d.line([(12, 21), (12, 9)], fill=(70, 140, 60, 255), width=2)
        for (x, y) in ((7, 10), (17, 10), (12, 5)):
            d.ellipse([x - 4, y - 3, x + 4, y + 3], fill=(90, 190, 90, 255), outline=C)
        d.ellipse([10, 3, 14, 7], fill=(240, 120, 200, 255))
    elif nom == "os":
        d.line([(6, 18), (18, 6)], fill=(236, 228, 206, 255), width=4)
        for (x, y) in ((4, 17), (7, 20), (17, 4), (20, 7)):
            d.ellipse([x - 3, y - 3, x + 3, y + 3], fill=(236, 228, 206, 255), outline=C)
    elif nom == "pierre":
        d.polygon([(3, 18), (6, 8), (14, 4), (21, 9), (20, 19), (11, 21)], fill=(130, 130, 140, 255), outline=C)
        d.polygon([(7, 9), (14, 5), (18, 9), (12, 12)], fill=(170, 170, 180, 255))
    elif nom == "obsidienne":
        d.polygon([(4, 16), (9, 4), (19, 6), (21, 17), (12, 21)], fill=(40, 26, 50, 255), outline=(10, 6, 14, 255))
        d.line([(9, 7), (12, 16)], fill=(150, 110, 200, 255))
    elif nom == "cristal":
        d.polygon([(12, 2), (18, 9), (12, 22), (6, 9)], fill=(190, 120, 250, 255), outline=(50, 24, 70, 255))
        d.line([(10, 8), (12, 18)], fill=(240, 220, 255, 255))
    else:  # minerais : pépites
        coul, reflet = MINERAIS[nom]
        d.polygon([(4, 14), (8, 6), (16, 4), (21, 11), (18, 19), (8, 20)], fill=coul + (255,), outline=C)
        d.polygon([(8, 8), (14, 6), (13, 11)], fill=reflet + (255,))
    return img


def generer_objets():
    for nom in ("bois", "fibre", "herbe", "os", "pierre", "obsidienne", "cristal", *MINERAIS.keys()):
        icone_objet(nom).save(chemin("objets", f"{nom}.png"))
    # sac au sol
    img = Image.new("RGBA", (24, 24)); d = ImageDraw.Draw(img)
    ombre(d, 12, 21, 9, 2)
    d.rounded_rectangle([4, 8, 20, 21], radius=5, fill=(160, 120, 70, 255), outline=C)
    d.polygon([(8, 9), (12, 3), (16, 9)], fill=(140, 100, 56, 255), outline=C)
    d.line([(7, 9), (17, 9)], fill=(90, 60, 30, 255), width=2)
    img.save(chemin("objets", "sac.png"))
    # corps : sac et crâne
    img = Image.new("RGBA", (30, 26)); d = ImageDraw.Draw(img)
    ombre(d, 15, 23, 13, 3)
    d.rounded_rectangle([2, 10, 18, 23], radius=5, fill=(150, 110, 64, 255), outline=C)
    d.ellipse([15, 9, 27, 20], fill=(236, 230, 214, 255), outline=C)
    d.rectangle([18, 18, 24, 22], fill=(236, 230, 214, 255), outline=C)
    d.rectangle([17, 13, 19, 15], fill=C); d.rectangle([23, 13, 25, 15], fill=C)
    img.save(chemin("objets", "corps.png"))
    # boutons : inventaire (sac) et main (récolter / ramasser)
    img = Image.new("RGBA", (48, 48)); d = ImageDraw.Draw(img)
    d.rounded_rectangle([1, 1, 46, 46], radius=10, fill=(120, 90, 56, 255), outline=(20, 20, 26, 255), width=2)
    sac = Image.open(chemin("objets", "sac.png")).resize((36, 36), Image.NEAREST)
    img.paste(sac, (6, 4), sac)
    img.save(chemin("ui", "inventaire.png"))
    img = Image.new("RGBA", (48, 48)); d = ImageDraw.Draw(img)
    d.rounded_rectangle([1, 1, 46, 46], radius=10, fill=(70, 120, 80, 255), outline=(20, 20, 26, 255), width=2)
    pioche = Image.open(chemin("armes", "mineur.png")).resize((40, 34), Image.NEAREST).rotate(30, expand=True, resample=Image.NEAREST)
    img.paste(pioche, ((48 - pioche.width) // 2, (48 - pioche.height) // 2), pioche)
    img.save(chemin("ui", "recolter.png"))


# ---------------------------------------------------------------- Étape 4 : craft et équipement

MATERIAUX_EQUIP = {  # même liste que Equipement.MATERIAUX / ARMES / OUTILS
    "tissu": (200, 190, 150), "cuivre": (206, 118, 60), "fer": (176, 176, 186), "or": (236, 190, 50),
    "mithril": (110, 200, 220), "obsidienne": (80, 50, 110), "cristal": (200, 130, 255),
    "bois": (150, 100, 56), "pierre": (140, 140, 150),
}
ARMES_EQUIP = ["bois", "cuivre", "fer", "or", "mithril", "obsidienne", "cristal"]
OUTILS_EQUIP = ["pierre", "cuivre", "fer", "mithril"]


def teinte(c, f):
    return tuple(max(0, min(255, int(v * f))) for v in c) + (255,)


def icone_piece(piece, coul):
    img = Image.new("RGBA", (24, 24)); d = ImageDraw.Draw(img)
    clair, fonce = teinte(coul, 1.25), teinte(coul, 0.7)
    base = coul + (255,)
    if piece == "tete":
        d.chord([4, 4, 20, 22], 180, 360, fill=base, outline=C)
        d.rectangle([4, 13, 20, 15], fill=fonce, outline=C)
        d.line([(8, 7), (11, 5)], fill=clair)
    elif piece == "torse":
        d.polygon([(5, 4), (9, 3), (12, 6), (15, 3), (19, 4), (21, 10), (18, 11), (18, 21), (6, 21), (6, 11), (3, 10)], fill=base, outline=C)
        d.line([(12, 7), (12, 20)], fill=fonce)
        d.line([(8, 8), (9, 16)], fill=clair)
    elif piece == "jambes":
        d.polygon([(6, 3), (18, 3), (19, 21), (14, 21), (12, 10), (10, 21), (5, 21)], fill=base, outline=C)
        d.rectangle([6, 3, 18, 6], fill=fonce, outline=C)
    elif piece == "pieds":
        for x in (3, 13):
            d.polygon([(x, 6), (x + 6, 6), (x + 6, 16), (x + 9, 17), (x + 9, 21), (x, 21)], fill=base, outline=C)
            d.line([(x + 1, 8), (x + 1, 15)], fill=clair)
    elif piece == "arme":
        d.line([(4, 20), (8, 16)], fill=(110, 70, 40, 255), width=3)
        d.line([(6, 14), (10, 18)], fill=fonce, width=2)
        d.polygon([(8, 14), (19, 3), (21, 3), (21, 5), (10, 16)], fill=base, outline=C)
        d.line([(10, 14), (19, 5)], fill=clair)
    elif piece == "outil":
        d.line([(5, 21), (15, 7)], fill=(110, 70, 40, 255), width=3)
        d.polygon([(6, 6), (12, 3), (19, 4), (22, 9), (17, 7), (11, 6)], fill=base, outline=C)
        d.line([(9, 5), (17, 5)], fill=clair)
    return img


def generer_etape4():
    for mat, coul in MATERIAUX_EQUIP.items():
        if mat in ("bois", "pierre"):
            continue
        for piece in ("tete", "torse", "jambes", "pieds"):
            icone_piece(piece, coul).save(chemin("objets", f"{piece}_{mat}.png"))
    for mat in ARMES_EQUIP:
        icone_piece("arme", MATERIAUX_EQUIP[mat]).save(chemin("objets", f"arme_{mat}.png"))
    for mat in OUTILS_EQUIP:
        icone_piece("outil", MATERIAUX_EQUIP[mat]).save(chemin("objets", f"outil_{mat}.png"))
    # lingots
    for mat in ("cuivre", "fer", "or", "mithril"):
        coul = MATERIAUX_EQUIP[mat]
        img = Image.new("RGBA", (24, 24)); d = ImageDraw.Draw(img)
        for i, y in enumerate((13, 7)):
            d.polygon([(3 + i * 3, y + 7), (6 + i * 3, y), (18 + i * 3 - 3, y), (21 - i * 0, y + 7)], fill=coul + (255,), outline=C)
            d.line([(7 + i * 3, y + 2), (16 + i * 2, y + 2)], fill=teinte(coul, 1.3))
        img.save(chemin("objets", f"lingot_{mat}.png"))
    # plan (parchemin)
    img = Image.new("RGBA", (24, 24)); d = ImageDraw.Draw(img)
    d.rectangle([5, 4, 19, 20], fill=(236, 220, 180, 255), outline=C)
    d.ellipse([3, 2, 8, 7], fill=(210, 190, 140, 255), outline=C); d.ellipse([16, 17, 21, 22], fill=(210, 190, 140, 255), outline=C)
    for y in (8, 11, 14):
        d.line([(8, y), (16, y)], fill=(80, 90, 160, 255))
    d.rectangle([12, 15, 15, 18], fill=(200, 50, 50, 255))
    img.save(chemin("objets", "plan.png"))
    # établi
    img = Image.new("RGBA", (36, 30)); d = ImageDraw.Draw(img)
    ombre(d, 18, 26, 16, 3)
    bois, fonce = (160, 110, 60, 255), (110, 74, 40, 255)
    d.rectangle([4, 16, 7, 27], fill=fonce, outline=C); d.rectangle([28, 16, 31, 27], fill=fonce, outline=C)
    d.rectangle([2, 9, 33, 16], fill=bois, outline=C)
    d.line([(3, 12), (32, 12)], fill=fonce)
    d.line([(9, 8), (16, 3)], fill=(110, 70, 40, 255), width=2); d.rectangle([14, 1, 19, 4], fill=(170, 170, 180, 255), outline=C)
    d.rectangle([22, 6, 29, 9], fill=(200, 200, 210, 255), outline=C)
    img.save(chemin("decors", "etabli.png"))
    # fourneau
    img = Image.new("RGBA", (32, 40)); d = ImageDraw.Draw(img)
    ombre(d, 16, 36, 14, 3)
    d.rounded_rectangle([3, 8, 29, 37], radius=4, fill=(120, 116, 120, 255), outline=C)
    for y in range(12, 36, 6):
        d.line([(4, y), (28, y)], fill=(90, 86, 92, 255))
    d.rectangle([12, 1, 20, 9], fill=(100, 96, 100, 255), outline=C)
    d.rounded_rectangle([9, 22, 23, 33], radius=3, fill=(40, 20, 16, 255), outline=C)
    d.polygon([(11, 33), (14, 25), (16, 29), (18, 24), (21, 33)], fill=(255, 150, 40, 255))
    d.polygon([(14, 33), (16, 28), (18, 33)], fill=(255, 230, 120, 255))
    img.save(chemin("decors", "fourneau.png"))
    # enclume
    img = Image.new("RGBA", (36, 30)); d = ImageDraw.Draw(img)
    ombre(d, 18, 26, 15, 3)
    d.rectangle([10, 20, 26, 26], fill=(110, 76, 44, 255), outline=C)
    d.polygon([(13, 20), (15, 14), (22, 14), (24, 20)], fill=(60, 62, 70, 255), outline=C)
    d.polygon([(3, 8), (10, 8), (12, 6), (32, 6), (32, 13), (12, 14), (8, 11)], fill=(80, 82, 92, 255), outline=C)
    d.line([(13, 7), (31, 7)], fill=(150, 152, 162, 255))
    img.save(chemin("decors", "enclume.png"))
    # coffre ancien
    img = Image.new("RGBA", (30, 28)); d = ImageDraw.Draw(img)
    ombre(d, 15, 24, 13, 3)
    d.rectangle([3, 11, 27, 24], fill=(130, 84, 40, 255), outline=C)
    d.chord([3, 3, 27, 19], 180, 360, fill=(150, 98, 48, 255), outline=C)
    d.rectangle([3, 10, 27, 12], fill=(200, 160, 60, 255), outline=C)
    for x in (7, 22):
        d.rectangle([x, 4, x + 2, 24], fill=(200, 160, 60, 255))
    d.rectangle([13, 11, 17, 16], fill=(240, 210, 90, 255), outline=C)
    img.save(chemin("decors", "coffre.png"))
    # icônes des stations
    for nom in ("etabli", "fourneau", "enclume"):
        src = Image.open(chemin("decors", f"{nom}.png"))
        src.thumbnail((24, 24), Image.NEAREST)
        img = Image.new("RGBA", (24, 24)); img.paste(src, ((24 - src.width) // 2, (24 - src.height) // 2), src)
        img.save(chemin("objets", f"{nom}.png"))
    # bouton Fabriquer (marteau)
    img = Image.new("RGBA", (48, 48)); d = ImageDraw.Draw(img)
    d.rounded_rectangle([1, 1, 46, 46], radius=10, fill=(150, 90, 50, 255), outline=(20, 20, 26, 255), width=2)
    d.line([(14, 36), (30, 18)], fill=(110, 70, 40, 255), width=5)
    d.polygon([(22, 10), (34, 10), (40, 18), (34, 24), (26, 16)], fill=(170, 172, 182, 255), outline=C)
    img.save(chemin("ui", "fabriquer.png"))


def generer_etape5():
    # bouton Personnage (silhouette et étoile de niveau)
    img = Image.new("RGBA", (48, 48)); d = ImageDraw.Draw(img)
    d.rounded_rectangle([1, 1, 46, 46], radius=10, fill=(70, 100, 170, 255), outline=(20, 20, 26, 255), width=2)
    d.ellipse([15, 8, 29, 22], fill=(235, 215, 190, 255), outline=C)
    d.chord([9, 22, 35, 50], 180, 360, fill=(200, 210, 230, 255), outline=C)
    etoile = []
    for i in range(10):
        a = -math.pi / 2 + i * math.pi / 5
        r = 8 if i % 2 == 0 else 3.5
        etoile.append((35 + r * math.cos(a), 14 + r * math.sin(a)))
    d.polygon(etoile, fill=(255, 215, 70, 255), outline=C)
    img.save(chemin("ui", "personnage.png"))


# ---------------------------------------------------------------- Étape 6 : bases et construction

MATIERES_MUR = {  # face, dessus, joints
    "bois": ((150, 100, 56), (186, 134, 80), (100, 64, 34)),
    "pierre": ((140, 140, 148), (178, 178, 186), (96, 96, 104)),
    "metal": ((96, 104, 122), (150, 160, 180), (60, 66, 80)),
}


def mur(mat):
    face, dessus, joint = MATIERES_MUR[mat]
    img = Image.new("RGBA", (32, 48)); d = ImageDraw.Draw(img)
    d.rectangle([0, 0, 31, 15], fill=dessus + (255,), outline=C)  # dessus du mur
    d.rectangle([0, 16, 31, 47], fill=face + (255,), outline=C)  # face
    if mat == "bois":
        for x in (8, 16, 24):
            d.line([(x, 17), (x, 46)], fill=joint + (255,))
        for x in (4, 12, 20, 28):
            d.point((x, 20), fill=joint + (255,)); d.point((x, 42), fill=joint + (255,))
        for x in range(2, 31, 4):
            d.line([(x, 2), (x, 13)], fill=eclaircir(dessus, 0.9) + (255,))
    elif mat == "pierre":
        for i, y in enumerate((23, 31, 39)):
            d.line([(1, y), (30, y)], fill=joint + (255,))
        for y0, y1, decal in ((17, 22, 0), (24, 30, 8), (32, 38, 0), (40, 46, 8)):
            for x in range(decal, 32, 16):
                d.line([(x, y0), (x, y1)], fill=joint + (255,))
        d.line([(2, 4), (12, 4)], fill=eclaircir(dessus, 1.1) + (255,))
    else:
        for x in (1, 30):
            for y in (19, 31, 44):
                d.point((x + (2 if x == 1 else -2), y), fill=(220, 225, 235, 255))
        d.line([(1, 31), (30, 31)], fill=joint + (255,))
        d.line([(3, 3), (28, 3)], fill=(200, 210, 225, 255))
    return img


def porte(mat, ouverte):
    face, dessus, joint = MATIERES_MUR[mat]
    img = Image.new("RGBA", (32, 48)); d = ImageDraw.Draw(img)
    # cadre (montants et linteau)
    for x0 in (0, 26):
        d.rectangle([x0, 0, x0 + 5, 47], fill=face + (255,), outline=C)
    d.rectangle([0, 0, 31, 15], fill=dessus + (255,), outline=C)
    if ouverte:
        d.rectangle([6, 16, 25, 47], fill=(30, 26, 30, 120))
        d.rectangle([20, 16, 25, 47], fill=eclaircir(face, 1.15) + (255,), outline=C)  # battant de profil
    else:
        bat = eclaircir(face, 1.1)
        d.rectangle([6, 16, 25, 47], fill=bat + (255,), outline=C)
        for y in (24, 32, 40):
            d.line([(7, y), (24, y)], fill=joint + (255,))
        d.ellipse([20, 30, 23, 33], fill=(230, 200, 80, 255), outline=C)
    return img


def generer_etape6():
    for mat in MATIERES_MUR:
        mur(mat).save(chemin("decors", f"mur_{mat}.png"))
    for mat in ("bois", "metal"):
        porte(mat, False).save(chemin("decors", f"porte_{mat}.png"))
        porte(mat, True).save(chemin("decors", f"porte_{mat}_ouverte.png"))
    # sols
    img = Image.new("RGBA", (32, 32)); d = ImageDraw.Draw(img)
    for i, y in enumerate(range(0, 32, 8)):
        c = (176, 128, 80) if i % 2 == 0 else (164, 118, 72)
        d.rectangle([0, y, 31, y + 7], fill=c + (255,))
        d.line([(0, y + 7), (31, y + 7)], fill=(120, 82, 46, 255))
        x = 10 if i % 2 == 0 else 22
        d.line([(x, y), (x, y + 7)], fill=(120, 82, 46, 255))
    img.save(chemin("decors", "sol_bois.png"))
    img = Image.new("RGBA", (32, 32)); d = ImageDraw.Draw(img)
    for (x0, y0) in ((0, 0), (16, 0), (0, 16), (16, 16)):
        c = (166, 166, 172) if (x0 + y0) % 32 == 0 else (156, 156, 164)
        d.rectangle([x0, y0, x0 + 15, y0 + 15], fill=c + (255,), outline=(110, 110, 118, 255))
        d.point((x0 + 4, y0 + 4), fill=(190, 190, 198, 255))
    img.save(chemin("decors", "sol_pierre.png"))
    # piège à pointes
    img = Image.new("RGBA", (32, 32)); d = ImageDraw.Draw(img)
    d.rectangle([3, 3, 28, 28], fill=(110, 76, 44, 220), outline=C)
    for x in (8, 16, 24):
        for y in (8, 16, 24):
            d.polygon([(x - 3, y + 3), (x, y - 4), (x + 3, y + 3)], fill=(200, 205, 215, 255), outline=C)
    img.save(chemin("decors", "piege.png"))
    # constructions libres
    img = Image.new("RGBA", (28, 26)); d = ImageDraw.Draw(img)
    ombre(d, 14, 22, 12, 3)
    d.rectangle([2, 10, 25, 22], fill=(150, 100, 56, 255), outline=C)
    d.rectangle([2, 4, 25, 10], fill=(176, 122, 70, 255), outline=C)
    d.line([(3, 16), (24, 16)], fill=(110, 72, 40, 255))
    d.rectangle([12, 8, 15, 13], fill=(200, 200, 210, 255), outline=C)
    img.save(chemin("constructions", "coffre_bois.png"))
    img = Image.new("RGBA", (28, 28)); d = ImageDraw.Draw(img)
    ombre(d, 14, 24, 12, 3)
    d.rectangle([2, 10, 25, 24], fill=(90, 96, 112, 255), outline=C)
    d.rectangle([2, 3, 25, 10], fill=(120, 128, 148, 255), outline=C)
    for x in (5, 22):
        d.line([(x, 4), (x, 23)], fill=(60, 64, 76, 255), width=2)
    d.rectangle([10, 12, 17, 19], fill=(230, 190, 60, 255), outline=C)
    d.rectangle([13, 14, 14, 17], fill=C)
    img.save(chemin("constructions", "coffre_securise.png"))
    img = Image.new("RGBA", (24, 36)); d = ImageDraw.Draw(img)
    ombre(d, 12, 33, 11, 3)
    d.rectangle([2, 4, 21, 33], fill=(130, 86, 48, 255), outline=C)
    d.rectangle([4, 6, 19, 31], fill=(200, 60, 60, 255))
    d.rectangle([4, 6, 19, 12], fill=(240, 240, 235, 255), outline=C)
    d.line([(4, 20), (19, 20)], fill=(160, 40, 40, 255))
    img.save(chemin("constructions", "lit.png"))
    img = Image.new("RGBA", (30, 44)); d = ImageDraw.Draw(img)
    ombre(d, 15, 40, 13, 3)
    d.polygon([(4, 40), (8, 26), (22, 26), (26, 40)], fill=(140, 140, 150, 255), outline=C)
    d.rectangle([10, 10, 20, 27], fill=(150, 150, 160, 255), outline=C)
    d.polygon([(15, 2), (22, 12), (15, 20), (8, 12)], fill=(90, 200, 255, 255), outline=C)
    d.polygon([(15, 5), (19, 11), (15, 15)], fill=(200, 245, 255, 255))
    img.save(chemin("constructions", "coeur_base.png"))
    img = Image.new("RGBA", (30, 38)); d = ImageDraw.Draw(img)
    ombre(d, 15, 35, 12, 3)
    d.polygon([(5, 35), (10, 22), (20, 22), (25, 35)], fill=(110, 76, 44, 255), outline=C)
    d.rectangle([7, 12, 23, 23], fill=(176, 118, 64, 255), outline=C)
    d.line([(2, 14), (28, 14)], fill=(110, 70, 40, 255), width=3)
    d.arc([1, 6, 29, 22], 200, 340, fill=(150, 100, 50, 255), width=2)
    d.line([(15, 4), (15, 20)], fill=(200, 205, 215, 255), width=2)
    d.polygon([(13, 5), (15, 1), (17, 5)], fill=(220, 224, 236, 255), outline=C)
    img.save(chemin("constructions", "tourelle.png"))
    # icônes d'objets (24x24) : réduction des images ci-dessus
    sources = {"mur_bois": ("decors", "mur_bois"), "mur_pierre": ("decors", "mur_pierre"), "mur_metal": ("decors", "mur_metal"),
               "porte_bois": ("decors", "porte_bois"), "porte_metal": ("decors", "porte_metal"),
               "sol_bois": ("decors", "sol_bois"), "sol_pierre": ("decors", "sol_pierre"), "piege": ("decors", "piege"),
               "coffre_bois": ("constructions", "coffre_bois"), "coffre_securise": ("constructions", "coffre_securise"),
               "lit": ("constructions", "lit"), "coeur_base": ("constructions", "coeur_base"), "tourelle": ("constructions", "tourelle")}
    for nom, (dossier, fichier) in sources.items():
        src = Image.open(chemin(dossier, f"{fichier}.png"))
        src.thumbnail((24, 24), Image.NEAREST)
        img = Image.new("RGBA", (24, 24)); img.paste(src, ((24 - src.width) // 2, (24 - src.height) // 2), src)
        img.save(chemin("objets", f"{nom}.png"))


if __name__ == "__main__":
    generer_sols()
    generer_arbre()
    generer_sapin()
    generer_rocher()
    generer_buisson()
    generer_fleurs()
    generer_feu()
    generer_decors_biomes()
    generer_personnages()
    generer_interface()
    generer_roles()
    generer_armes()
    generer_combat()
    generer_icones()
    generer_filons()
    generer_objets()
    generer_etape4()
    generer_etape5()
    generer_etape6()
    print("Assets générés dans", os.path.abspath(os.path.join(RACINE, "assets")))
