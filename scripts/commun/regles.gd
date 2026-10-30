class_name Regles
extends RefCounted
## Règles de jeu partagées. Le serveur les applique pour de vrai, le client les
## rejoue pour prédire son propre déplacement sans attendre le serveur.

const PAS := 1.0 / 60.0 # durée d'une entrée de déplacement


static func deplacer(monde: Monde, pos: Vector2, dir: Vector2, vitesse: float, vol: bool) -> Vector2:
	if dir.length_squared() > 1.0:
		dir = dir.normalized()
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
