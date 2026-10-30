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


def generer_sols():
    """Atlas des sols : ligne 0 = eau animée (4 images), lignes 1..5 = sols (4 variantes)."""
    atlas = Image.new("RGBA", (T * 4, T * 6))
    for f in range(4):
        atlas.paste(tuile_eau(None, f), (f * T, 0))
    sols = [
        # (nom, base, écart, taches)
        ("sable", (220, 198, 138), 10, [((196, 172, 112), 6, 1), ((240, 224, 170), 6, 1)]),
        ("herbe", (86, 158, 70), 9, []),
        ("herbe_foncee", (58, 124, 58), 8, []),
        ("terre", (128, 92, 60), 10, [((100, 72, 48), 8, 2), ((150, 116, 80), 6, 1)]),
        ("pierre", (128, 128, 134), 9, [((96, 96, 104), 6, 2), ((160, 160, 166), 6, 1)]),
    ]
    for ligne, (nom, base, ecart, taches) in enumerate(sols, start=1):
        for v in range(4):
            rng = random.Random(ligne * 100 + v)
            img = tuile_texturee(rng, base, ecart, taches)
            if nom == "herbe":
                brins_herbe(rng, img, (120, 196, 92), (64, 128, 56), 14)
                if v == 3:
                    fleurettes(rng, img, 3)
            elif nom == "herbe_foncee":
                brins_herbe(rng, img, (86, 160, 72), (40, 96, 44), 16)
            elif nom == "pierre":
                d = ImageDraw.Draw(img)
                x = rng.randrange(4, T - 8)
                d.line([(x, 4), (x + 4, 12), (x + 2, 20)], fill=(90, 90, 98))
            atlas.paste(img, (v * T, ligne * T))
    atlas.save(chemin("tuiles", "sols.png"))


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


if __name__ == "__main__":
    generer_sols()
    generer_arbre()
    generer_sapin()
    generer_rocher()
    generer_buisson()
    generer_fleurs()
    generer_feu()
    generer_personnages()
    generer_interface()
    print("Assets générés dans", os.path.abspath(os.path.join(RACINE, "assets")))
