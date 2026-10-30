class_name Combat
extends RefCounted
## Combat côté serveur : vie, dégâts, projectiles, zones, effets, mort et réapparition.
## Le serveur décide de tout ; les clients reçoivent des événements pour l'affichage.

const RAYON_CIBLE := 12.0 # taille d'un personnage pour les coups et projectiles
const HORS_COMBAT := 5.0 # secondes sans dégâts avant de pouvoir changer de rôle
const VIE_MANNEQUIN := 400

var serveur: Node
var temps := 0.0
var projectiles := {} # id -> projectile
var zones_a_venir: Array = [] # effets de zone retardés
var mannequins := {} # id -> {id, pos, vie, max, dernier}
var _prochain_id := 1


func _init(p_serveur: Node) -> void:
	serveur = p_serveur


func _id() -> int:
	_prochain_id += 1
	return _prochain_id


# ------------------------------------------------------------------ Joueurs

func preparer_session(s: Dictionary, fiche: Dictionary) -> void:
	s.role = fiche.get("role", "guerrier") if Roles.valide(fiche.get("role", "")) else "guerrier"
	s.equipe = str(fiche.get("equipe", ""))
	s.vie_max = int(Roles.donnees(s.role).vie)
	s.vie = s.vie_max
	s.mort = false
	s.mort_jusqua = 0.0
	s.pret_attaque = 0.0
	s.pret_competence = 0.0
	s.effets = {}
	s.dernier_combat = -100.0
	s.dernier_vainqueur = ""
	s.stats = Equipement.stats({})
	s.caps = Progression.capacites(Progression.vierge(), s.role)


## Bonus de l'équipement et de la progression (caractéristiques, arbres) : vie, armure, dégâts,
## vitesse, récolte, recharges… et capacités du rôle modifiées par l'arbre principal.
func recalculer(s: Dictionary) -> void:
	var avant: int = s.vie_max
	var equipement: Dictionary = s.get("equipement", {})
	var progression: Dictionary = s.get("progression", Progression.vierge())
	s.stats = Progression.cumuler(Equipement.stats(equipement), Progression.stats(progression, s.role, equipement))
	s.caps = Progression.capacites(progression, s.role, float(s.stats.get("recharge", 0.0)))
	s.vie_max = int(Roles.donnees(s.role).vie) + int(round(s.stats.vie))
	if not s.mort:
		s.vie = clampi(s.vie + s.vie_max - avant, 1, s.vie_max)
	serveur.envoyer_reglages(s.id)


func vitesse(s: Dictionary) -> float:
	var v: float = Config.VITESSE_JOUEUR * float(Roles.donnees(s.role).vitesse) * float(s.vitesse) * (1.0 + s.stats.vitesse)
	if _effet(s, "sprint") or _effet(s, "ruee"):
		v *= 1.0 + float(s.caps.competence.get("bonus", 0.0))
	return v


func recharge_esquive(s: Dictionary) -> float:
	return float(Roles.donnees(s.role).esquive) * (1.0 - float(s.stats.get("esquive", 0.0)))


func a_effet(s: Dictionary, nom: String) -> bool:
	return _effet(s, nom)


func evenement(genre: String, donnees: Dictionary) -> void:
	_evenement(genre, donnees)


func _effet(s: Dictionary, nom: String) -> bool:
	return s.effets.get(nom, 0.0) > temps


func drapeaux(s: Dictionary) -> int:
	var f := 0
	if s.mort: f |= 1
	if _effet(s, "ombre"): f |= 2
	if _effet(s, "bouclier"): f |= 4
	if _effet(s, "sprint"): f |= 8
	if _effet(s, "ruee"): f |= 16
	return f


func meme_equipe(a: Dictionary, b: Dictionary) -> bool:
	return a.id == b.id or (a.equipe != "" and a.equipe == b.equipe)


func changer_role(s: Dictionary, role: String, force := false) -> String:
	if not Roles.valide(role):
		return "Rôle inconnu : %s" % role
	if not force and temps - s.dernier_combat < HORS_COMBAT:
		return "Impossible pendant un combat. Attends quelques secondes."
	var change: bool = role != s.role
	s.role = role
	if change:
		serveur.experience.sur_changement_role(s)
	recalculer(s)
	s.vie = s.vie_max
	s.effets = {}
	s.pret_attaque = 0.0
	s.pret_competence = 0.0
	serveur.donnees.joueurs[s.nom]["role"] = role
	serveur.annoncer_joueur(s)
	serveur.envoyer_reglages(s.id)
	return "Tu es maintenant %s." % Roles.donnees(role).nom


# ------------------------------------------------------------------ Actions

func action(s: Dictionary, genre: String, cible: Vector2, charge: float) -> void:
	if s.mort or not genre in ["attaque", "competence"] or not cible.is_finite():
		return
	var pret_cle := "pret_" + genre
	if temps < s[pret_cle]:
		return
	var cap: Dictionary = s.caps[genre]
	charge = clampf(charge, 0.0, 1.0)
	var pos: Vector2 = s.pos
	var portee := Roles.portee(cap, charge)
	var vers := cible
	if pos.distance_to(cible) > portee:
		vers = pos + (cible - pos).normalized() * portee
	var dir: Vector2 = (cible - pos).normalized() if cible != pos else s.mvt.regard
	s[pret_cle] = temps + float(cap.recharge)
	var forme: String = cap.genre
	match forme:
		"melee":
			_melee(s, cap, dir)
		"tir":
			_tirer(s, cap, dir, charge)
		"lancer":
			var duree := float(cap.vol)
			var genre_potion := "potion_soin" if cap.has("soin") else "potion_degats"
			_evenement("lancer", {"de": pos, "vers": vers, "duree": duree, "genre": genre_potion, "id": s.id})
			zones_a_venir.append({"t": temps + duree, "pos": vers, "cap": cap, "par": s.id, "genre": genre_potion})
		"zone_visee":
			var delai := float(cap.delai)
			_evenement("zone", {"pos": vers, "rayon": cap.rayon, "delai": delai, "vagues": cap.vagues, "genre": "pluie"})
			for i in int(cap.vagues):
				zones_a_venir.append({"t": temps + delai + i * 0.35, "pos": vers, "cap": cap, "par": s.id, "genre": "pluie"})
		"zone_soi":
			_zone(s, pos, cap, s.role)
		"tourelle":
			serveur.construction.tourelle_temporaire(s, vers, cap)
		"buff":
			s.effets[cap.effet] = temps + float(cap.duree)
			_evenement("buff", {"id": s.id, "effet": cap.effet})
			serveur.envoyer_reglages(s.id)
	_evenement("geste", {"id": s.id, "angle": dir.angle(), "genre": genre})


func _melee(s: Dictionary, cap: Dictionary, dir: Vector2) -> void:
	var demi_angle := deg_to_rad(float(cap.angle) * 0.5)
	for c in _cibles_dans_cercle(s.pos, float(cap.portee) + RAYON_CIBLE):
		var vers_cible: Vector2 = c.pos - s.pos
		if vers_cible.length() > 4.0 and absf(dir.angle_to(vers_cible)) > demi_angle:
			continue
		if c.genre == "c":
			# Construction : la clé de l'ingénieur répare celles de son équipe, les autres coups l'abîment.
			if cap.has("repare") and serveur.construction.allie(s, c.rec.proprio):
				serveur.construction.reparer_par(c.rec, float(cap.repare))
			else:
				infliger(s, c, float(cap.degats), cap.get("type", ""))
			continue
		if Regles.ligne_bloquee(serveur.monde, s.pos, c.pos):
			continue
		var degats := float(cap.degats)
		if cap.has("dos") and c.genre == "j" and c.s.mvt.regard.dot(vers_cible.normalized()) > 0.3:
			degats *= float(cap.dos) # attaque dans le dos
		infliger(s, c, degats)


func _tirer(s: Dictionary, cap: Dictionary, dir: Vector2, charge: float) -> void:
	var pid := _id()
	var p := {
		"id": pid, "par": s.id, "pos": s.pos + Vector2(0, -10), "dir": dir,
		"vitesse": lerpf(cap.vitesse_proj, cap.vitesse_proj_max, charge),
		"reste": Roles.portee(cap, charge),
		"degats": lerpf(cap.degats, cap.degats_max, charge), "type": cap.get("type", ""),
	}
	projectiles[pid] = p
	_evenement("projectile", {"pid": pid, "de": p.pos, "dir": dir, "vitesse": p.vitesse, "portee": p.reste})


func _zone(s: Dictionary, centre: Vector2, cap: Dictionary, genre: String) -> void:
	_evenement("zone", {"pos": centre, "rayon": cap.rayon, "delai": 0.0, "genre": genre, "id": s.id})
	for c in _cibles_dans_cercle(centre, float(cap.rayon) + RAYON_CIBLE):
		var allie: bool = c.genre == "j" and meme_equipe(s, c.s)
		if cap.has("degats") and not allie:
			infliger(s, c, float(cap.degats), cap.get("type", ""))
		if allie and cap.has("soin"):
			soigner(c.s, float(cap.soin))
		if allie and cap.has("effet"):
			c.s.effets[cap.effet] = temps + float(cap.duree)


# ------------------------------------------------------------------ Cibles et dégâts

func _cibles_dans_cercle(centre: Vector2, rayon: float) -> Array:
	var liste := []
	for s in serveur.joueurs.values():
		if not s.mort and s.pos.distance_to(centre) <= rayon:
			liste.append({"genre": "j", "s": s, "pos": s.pos})
	for m in mannequins.values():
		if m.pos.distance_to(centre) <= rayon:
			liste.append({"genre": "m", "m": m, "pos": m.pos})
	liste.append_array(serveur.construction.cibles_dans_cercle(centre, rayon))
	return liste


## type_degats : contre les constructions (tranchant, contondant, percant, explosif, pioche).
func infliger(source: Dictionary, c: Dictionary, montant: float, type_degats := "") -> void:
	if c.genre == "c":
		if type_degats == "" and source.has("caps"):
			type_degats = str(source.caps.get("attaque", {}).get("type", "contondant"))
		serveur.construction.subir(c.rec, source, montant * (1.0 + float(source.stats.get("degats", 0.0))), type_degats)
		_fin_ombre(source)
		return
	if c.genre == "m":
		var m: Dictionary = c.m
		montant *= 1.0 + source.stats.degats
		m.vie = maxi(0, m.vie - int(round(montant)))
		m.dernier = temps
		_voler_vie(source, montant)
		if m.vie == 0:
			m.vie = m.max # un mannequin ne meurt pas : il se remet debout
			if source.has("progression"):
				serveur.experience.sur_mannequin(source)
		_evenement("degats", {"cle": "m%d" % m.id, "montant": int(round(montant)), "pos": m.pos})
		_fin_ombre(source)
		return
	var s: Dictionary = c.s
	if s.mort or s.dieu or s.mvt.dash_f > 0 or meme_equipe(source, s):
		return
	if source.has("proprio") and serveur.construction.allie(s, source.proprio):
		return # tourelles et pièges : pas sur leur équipe
	if not serveur.donnees.reglages.get("pvp", true):
		return
	if _effet(s, "bouclier"):
		montant *= 1.0 - float(Roles.LISTE.paladin.competence.reduction)
	if _effet(source, "ombre"):
		montant *= 1.0 + float(source.caps.competence.get("bonus", Roles.LISTE.assassin.competence.bonus))
	montant *= (1.0 + source.stats.degats) * 100.0 / (100.0 + s.stats.armure)
	_fin_ombre(source)
	var n := maxi(1, int(round(montant)))
	s.vie = maxi(0, s.vie - n)
	s.dernier_combat = temps
	source.dernier_combat = temps
	_evenement("degats", {"cle": "j%d" % s.id, "montant": n, "pos": s.pos})
	_voler_vie(source, n)
	if s.vie == 0:
		if source.id != s.id and source.has("progression"):
			serveur.experience.sur_victoire(source, s)
		mourir(s, source.nom)


## Vol de vie (nœuds « Rage », « Saignée »…) : une part des dégâts soigne l'attaquant.
func _voler_vie(source: Dictionary, montant: float) -> void:
	var part := float(source.stats.get("vol_vie", 0.0))
	if part > 0.0 and montant * part >= 0.5:
		soigner(source, montant * part)


func _fin_ombre(s: Dictionary) -> void:
	if _effet(s, "ombre"):
		s.effets.erase("ombre")


func soigner(s: Dictionary, montant: float) -> void:
	if s.mort:
		return
	var avant: int = s.vie
	s.vie = mini(s.vie_max, s.vie + int(round(montant)))
	if s.vie > avant:
		_evenement("degats", {"cle": "j%d" % s.id, "montant": s.vie - avant, "pos": s.pos, "soin": true})


func mourir(s: Dictionary, par: String) -> void:
	s.mort = true
	s.vie = 0
	s.effets = {}
	s.mort_jusqua = temps + Roles.REAPPARITION
	s.dernier_vainqueur = par
	serveur.recolte.mourir(s)
	_evenement("mort", {"id": s.id, "par": par, "pos": s.pos})
	serveur.diffuser("%s a été vaincu par %s." % [s.nom, par] if par != s.nom else "%s est mort." % s.nom, "combat")
	serveur.journal("%s vaincu par %s" % [s.nom, par])


func reapparaitre(s: Dictionary) -> void:
	s.mort = false
	s.vie = s.vie_max
	s.pret_attaque = 0.0
	s.pret_competence = 0.0
	# Réapparition dans une base de son équipe (cœur de base + lit), sinon au départ.
	var base: Vector2 = serveur.construction.point_reapparition(s)
	serveur.teleporter(s, serveur.monde.point_libre(base) if base.is_finite() else serveur.monde.point_apparition(randi() % 8))
	_evenement("reapparition", {"id": s.id})


# ------------------------------------------------------------------ Boucle

func tick(delta: float) -> void:
	temps += delta
	for pid in projectiles.keys():
		_avancer_projectile(projectiles[pid], delta)
	var restantes := []
	for z in zones_a_venir:
		if temps >= z.t:
			_effet_zone_retardee(z)
		else:
			restantes.append(z)
	zones_a_venir = restantes
	for s in serveur.joueurs.values():
		if s.mort and temps >= s.mort_jusqua:
			reapparaitre(s)
		for effet in ["sprint", "ruee"]:
			if s.effets.has(effet) and not _effet(s, effet):
				s.effets.erase(effet)
				serveur.envoyer_reglages(s.id) # fin du sprint : vitesse normale
	for m in mannequins.values():
		if m.vie < m.max and temps - m.dernier > 3.0:
			m.vie = m.max


func _avancer_projectile(p: Dictionary, delta: float) -> void:
	var pas: float = minf(p.vitesse * delta, p.reste)
	var depart: Vector2 = p.pos
	var arrivee: Vector2 = depart + p.dir * pas
	p.reste -= pas
	var source: Dictionary = p.get("source", serveur.joueurs.get(p.par, {}))
	# Cible touchée sur le segment parcouru
	for c in _cibles_dans_cercle(depart.lerp(arrivee, 0.5), pas * 0.5 + RAYON_CIBLE + 4.0):
		if c.genre == "j" and c.s.id == p.par:
			continue
		if not source.is_empty() and c.genre == "j" and (meme_equipe(source, c.s) \
				or (source.has("proprio") and serveur.construction.allie(c.s, source.proprio))):
			continue
		if c.genre == "c" and (c.rec.case != null or source.is_empty() or serveur.construction.allie(source, c.rec.proprio)):
			continue # les murs arrêtent le projectile plus bas ; on traverse ses propres constructions
		var proche := Geometry2D.get_closest_point_to_segment(c.pos + Vector2(0, -10), depart, arrivee)
		if proche.distance_to(c.pos + Vector2(0, -10)) <= RAYON_CIBLE:
			if not source.is_empty():
				infliger(source, c, p.degats, p.get("type", ""))
			_fin_projectile(p, proche, true)
			return
	var obstacle := Regles.premier_obstacle(serveur.monde, depart, arrivee)
	if obstacle != Regles.AUCUN_OBSTACLE:
		var mur: Dictionary = serveur.construction.a_la_case(obstacle)
		if not mur.is_empty() and not source.is_empty():
			infliger(source, {"genre": "c", "rec": mur, "pos": mur.pos}, p.degats, p.get("type", ""))
		_fin_projectile(p, arrivee, false)
		return
	p.pos = arrivee
	if p.reste <= 0.0:
		_fin_projectile(p, arrivee, false)


## Tir d'une tourelle (source : voir Construction._source).
func tir_construction(source: Dictionary, depart: Vector2, dir: Vector2, degats: float, portee: float) -> void:
	var pid := _id()
	projectiles[pid] = {"id": pid, "par": source.id, "source": source, "pos": depart, "dir": dir, "vitesse": 640.0,
		"reste": portee, "degats": degats, "type": "percant"}
	_evenement("projectile", {"pid": pid, "de": depart, "dir": dir, "vitesse": 640.0, "portee": portee})


func _fin_projectile(p: Dictionary, pos: Vector2, touche: bool) -> void:
	projectiles.erase(p.id)
	_evenement("fin_projectile", {"pid": p.id, "pos": pos, "touche": touche})


func _effet_zone_retardee(z: Dictionary) -> void:
	var source: Dictionary = serveur.joueurs.get(z.par, {})
	var cap: Dictionary = z.cap
	_evenement("impact", {"pos": z.pos, "rayon": cap.rayon, "genre": z.genre})
	if source.is_empty():
		return
	for c in _cibles_dans_cercle(z.pos, float(cap.rayon) + RAYON_CIBLE):
		var allie: bool = c.genre == "j" and meme_equipe(source, c.s)
		if cap.has("soin"):
			if allie:
				soigner(c.s, float(cap.soin))
		elif not allie:
			infliger(source, c, float(cap.degats), cap.get("type", ""))


# ------------------------------------------------------------------ Mannequins

func ajouter_mannequin(pos: Vector2) -> int:
	var id := _id()
	mannequins[id] = {"id": id, "pos": pos, "vie": VIE_MANNEQUIN, "max": VIE_MANNEQUIN, "dernier": 0.0}
	_evenement("mannequin", {"id": id, "pos": pos, "vie": VIE_MANNEQUIN, "max": VIE_MANNEQUIN})
	return id


func retirer_mannequins() -> void:
	for id in mannequins.keys():
		_evenement("mannequin_retire", {"id": id})
	mannequins.clear()


func mannequins_par_defaut() -> void:
	var c: Vector2 = serveur.monde.centre()
	for i in 4:
		ajouter_mannequin(serveur.monde.point_libre(c + Vector2(-96 + i * 64, -110)))


func infos_mannequins() -> Dictionary:
	var d := {}
	for m in mannequins.values():
		d[m.id] = [m.pos.x, m.pos.y, m.vie, m.max]
	return d


func _evenement(genre: String, donnees: Dictionary) -> void:
	for id in serveur.joueurs:
		Reseau.s_evenement.rpc_id(id, genre, donnees)
