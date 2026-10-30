class_name Regles
extends RefCounted
## Règles de jeu partagées. Le serveur les applique pour de vrai, le client les
## rejoue pour prédire son propre déplacement (y compris l'esquive) sans attendre le serveur.

const PAS := 1.0 / 60.0 # durée d'une entrée de déplacement


## État de déplacement d'un personnage.
static func nouvel_etat(pos: Vector2) -> Dictionary:
	return {"pos": pos, "dash_f": 0, "dash_dir": Vector2.DOWN, "dash_cd": 0, "regard": Vector2.DOWN}


## Fait avancer l'état d'une entrée (1/60 s).
## esquive : vrai si le bouton d'esquive a été appuyé à cette entrée.
static func pas(monde: Monde, e: Dictionary, dir: Vector2, esquive: bool, vitesse: float, vol: bool, recharge_esquive: float) -> void:
	if dir.length_squared() > 1.0:
		dir = dir.normalized()
	if dir != Vector2.ZERO:
		e.regard = dir.normalized()
	if e.dash_cd > 0:
		e.dash_cd -= 1
	if esquive and e.dash_cd == 0 and e.dash_f == 0:
		e.dash_f = Roles.ESQUIVE_FRAMES
		e.dash_dir = e.regard
		e.dash_cd = int(recharge_esquive * 60.0)
	if e.dash_f > 0:
		e.dash_f -= 1
		e.pos = deplacer(monde, e.pos, e.dash_dir * (Roles.ESQUIVE_VITESSE / vitesse), vitesse, vol)
	else:
		e.pos = deplacer(monde, e.pos, dir, vitesse, vol)


static func deplacer(monde: Monde, pos: Vector2, dir: Vector2, vitesse: float, vol: bool) -> Vector2:
	var mouvement := dir * vitesse * PAS
	if vol:
		var t := Monde.TAILLE * Config.TAILLE_TUILE
		return (pos + mouvement).clamp(Vector2.ZERO, Vector2(t, t))
	# Axe par axe, pour glisser le long des obstacles.
	var essai := Vector2(pos.x + mouvement.x, pos.y)
	if not monde.collision(essai, Config.RAYON_JOUEUR):
		pos = essai
	essai = Vector2(pos.x, pos.y + mouvement.y)
	if not monde.collision(essai, Config.RAYON_JOUEUR):
		pos = essai
	return pos


## Vrai si le segment touche un obstacle qui arrête les projectiles (arbres, rochers ; pas l'eau).
static func ligne_bloquee(monde: Monde, de: Vector2, vers: Vector2) -> bool:
	var t := float(Config.TAILLE_TUILE)
	var etapes := int(de.distance_to(vers) / 8.0) + 1
	for i in etapes + 1:
		var p := de.lerp(vers, float(i) / etapes)
		var cx := int(floor(p.x / t))
		var cy := int(floor(p.y / t))
		if monde.deco_en(cx, cy) in Monde.DECOS_BLOQUANTES:
			var boite := Rect2(cx * t, cy * t, t, t).grow(-8.0)
			if boite.has_point(p):
				return true
	return false
