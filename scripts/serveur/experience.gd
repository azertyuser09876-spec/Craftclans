class_name Experience
extends RefCounted
## Étape 5 côté serveur : gain d'expérience, montée de niveau, points de caractéristiques,
## arbres de compétences et oubli. Les bonus sont appliqués par Combat.recalculer().

const ANTI_FARM := 300.0 # secondes : vaincre le même joueur ne rapporte rien pendant ce temps
const XP_MANNEQUIN := 5
const NIVEAU_MAX_MANNEQUIN := 5 # les mannequins n'apprennent plus rien au-delà

var serveur: Node
var _victoires := {} # "vainqueur>victime" -> temps


func _init(p_serveur: Node) -> void:
	serveur = p_serveur


func preparer_session(s: Dictionary, fiche: Dictionary) -> void:
	s.progression = Progression.nettoyer(fiche.get("progression", {}))
	s.regen_reste = 0.0


func memoriser(s: Dictionary, fiche: Dictionary) -> void:
	fiche["progression"] = s.progression.duplicate(true)


## Résumé envoyé au joueur avec ses réglages.
static func resume(s: Dictionary) -> Dictionary:
	var p: Dictionary = s.progression
	return {"niveau": p.niveau, "xp": p.xp, "xp_suivant": Progression.xp_pour(p.niveau) if p.niveau < Progression.NIVEAU_MAX else 0,
		"caracs": p.caracs, "arbres": p.arbres, "secondaire": p.secondaire,
		"points_caracs": Progression.points_caracs(p), "points_competence": Progression.points_competence(p, s.role)}


func gagner(s: Dictionary, n: int) -> void:
	var p: Dictionary = s.progression
	if n <= 0 or p.niveau >= Progression.NIVEAU_MAX:
		return
	p.xp += n
	var monte := false
	while p.niveau < Progression.NIVEAU_MAX and p.xp >= Progression.xp_pour(p.niveau):
		p.xp -= Progression.xp_pour(p.niveau)
		p.niveau += 1
		monte = true
	if p.niveau >= Progression.NIVEAU_MAX:
		p.xp = 0
	if monte:
		_monter(s)
	else:
		Reseau.s_progression.rpc_id(s.id, resume(s))


func _monter(s: Dictionary) -> void:
	serveur.combat.evenement("niveau", {"id": s.id, "niveau": s.progression.niveau, "pos": s.pos})
	serveur.diffuser("%s passe au niveau %d !" % [s.nom, s.progression.niveau], "systeme")
	serveur.journal("%s passe au niveau %d" % [s.nom, s.progression.niveau])
	serveur.annoncer_joueur(s)
	appliquer(s)


## Recalcule les bonus et prévient le joueur.
func appliquer(s: Dictionary) -> void:
	serveur.combat.recalculer(s)
	Reseau.s_progression.rpc_id(s.id, resume(s))


# ------------------------------------------------------------------ Sources d'expérience

func sur_recolte(s: Dictionary, objet: String, c: Vector2i) -> void:
	if objet.begins_with("plan_"):
		gagner(s, Progression.xp_coffre(serveur.monde.danger_en(c.x, c.y)))
	elif not Objets.DECOS_STATIONS.has(objet):
		gagner(s, Progression.xp_recolte(objet))


func sur_fabrication(s: Dictionary, objet: String) -> void:
	gagner(s, Progression.xp_fabrication(objet))


func sur_victoire(vainqueur: Dictionary, victime: Dictionary) -> void:
	var cle := "%s>%s" % [vainqueur.nom, victime.nom]
	var t: float = serveur.combat.temps
	if _victoires.has(cle) and t - _victoires[cle] < ANTI_FARM:
		return
	_victoires[cle] = t
	gagner(vainqueur, Progression.xp_victoire(vainqueur.progression.niveau, victime.progression.niveau))


func sur_mannequin(s: Dictionary) -> void:
	if s.progression.niveau < NIVEAU_MAX_MANNEQUIN:
		gagner(s, XP_MANNEQUIN)


# ------------------------------------------------------------------ Demandes du joueur

## genre : carac (valeur = carac), noeud (valeur = "arbre:noeud"), oublier.
func sur_demande(s: Dictionary, genre: String, valeur: String) -> void:
	var p: Dictionary = s.progression
	match genre:
		"carac":
			if not Progression.CARACS.has(valeur):
				return
			if Progression.points_caracs(p) <= 0:
				_dire(s, "Plus de points de caractéristiques : monte de niveau.")
				return
			if int(p.caracs[valeur]) >= Progression.CARAC_MAX:
				_dire(s, "Maximum atteint pour %s." % Progression.CARACS[valeur].nom)
				return
			p.caracs[valeur] += 1
			appliquer(s)
		"noeud":
			var morceaux := valeur.split(":")
			if morceaux.size() != 2:
				return
			var raison := Progression.empechement_noeud(p, s.role, morceaux[0], morceaux[1])
			if raison != "":
				_dire(s, raison)
				return
			Progression.prendre(p, s.role, morceaux[0], morceaux[1])
			appliquer(s)
		"oublier":
			var cout := Progression.cout_oubli(p)
			for id in cout:
				if Objets.compter(s.inventaire, id) < int(cout[id]):
					_dire(s, "Il faut %d %s pour tout oublier." % [cout[id], Objets.infos(id).nom])
					return
			for id in cout:
				Objets.retirer(s.inventaire, id, int(cout[id]))
			Progression.oublier_tout(p)
			serveur.recolte.envoyer_inventaire(s)
			appliquer(s)
			_dire(s, "Tu as tout oublié : tes points sont rendus.")


## Changement de rôle : l'arbre principal change, les points de compétence sont rendus.
func sur_changement_role(s: Dictionary) -> void:
	if not s.progression.arbres.is_empty():
		Progression.oublier_competences(s.progression)
		_dire(s, "Nouveau rôle : tes points de compétence te sont rendus.")
	Reseau.s_progression.rpc_id(s.id, resume(s))


## Administration : fixe le niveau (l'expérience du niveau en cours repart de 0).
func definir_niveau(s: Dictionary, niveau: int) -> void:
	var p: Dictionary = s.progression
	var ancien: int = p.niveau
	p.niveau = clampi(niveau, 1, Progression.NIVEAU_MAX)
	p.xp = 0
	if p.niveau < ancien:
		Progression.oublier_tout(p) # moins de points qu'avant : tout est rendu
	serveur.annoncer_joueur(s)
	appliquer(s)


func tick(delta: float) -> void:
	# Régénération hors combat (nœuds « Infusion »)
	for s in serveur.joueurs.values():
		var regen: float = s.stats.get("regen", 0.0)
		if regen <= 0.0 or s.mort or s.vie >= s.vie_max or serveur.combat.temps - s.dernier_combat < Combat.HORS_COMBAT:
			continue
		s.regen_reste += regen * delta
		if s.regen_reste >= 1.0:
			var n := int(s.regen_reste)
			s.regen_reste -= n
			s.vie = mini(s.vie_max, s.vie + n)


func _dire(s: Dictionary, texte: String) -> void:
	Reseau.s_message.rpc_id(s.id, texte, "systeme")
