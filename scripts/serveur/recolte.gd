class_name Recolte
extends RefCounted
## Étape 3 côté serveur : récolte des ressources, inventaires, repousse des décors,
## sacs au sol (objets jetés) et corps des joueurs morts, que tout le monde peut piller.

const DUREE_CORPS := 30 * 60.0 # secondes de jeu (serveur allumé) avant que le corps disparaisse
const DUREE_SAC := 10 * 60.0
const FREQ_PROGRES := 0.1 # envoi de la barre de récolte au joueur

var serveur: Node
var sacs := {} # id -> {id, pos, objets, genre, nom, reste}
var _usure := {} # case -> récoltes restantes avant disparition du décor
var _prochain_sac := 1
var _accu_seconde := 0.0
var _accu_progres := 0.0


func _init(p_serveur: Node) -> void:
	serveur = p_serveur


# ------------------------------------------------------------------ Sauvegarde

func charger(donnees: Dictionary) -> void:
	sacs.clear()
	_usure.clear()
	for d in donnees.get("sacs", []):
		var objets := []
		for o in d.get("objets", []):
			var propre := Objets.nettoyer_objet(o)
			if not propre.is_empty():
				objets.append(propre)
		if objets.is_empty():
			continue
		var id := int(d.id)
		sacs[id] = {"id": id, "pos": Vector2(float(d.x), float(d.y)), "objets": objets,
			"genre": str(d.genre), "nom": str(d.nom), "reste": float(d.reste)}
		_prochain_sac = maxi(_prochain_sac, id + 1)
	if not donnees.has("repousses"):
		donnees["repousses"] = []


func enregistrer(donnees: Dictionary) -> void:
	var liste := []
	for s in sacs.values():
		liste.append({"id": s.id, "x": s.pos.x, "y": s.pos.y, "objets": s.objets, "genre": s.genre,
			"nom": s.nom, "reste": s.reste})
	donnees["sacs"] = liste


# ------------------------------------------------------------------ Joueurs

func preparer_session(s: Dictionary, fiche: Dictionary) -> void:
	s.inventaire = Objets.nettoyer(fiche.get("inventaire", []))
	s.equipement = Equipement.equipement_vide()
	var brut: Dictionary = fiche.get("equipement", {})
	for emplacement in Equipement.EMPLACEMENTS:
		var o := Objets.nettoyer_objet(brut.get(emplacement, {}))
		if not o.is_empty() and Objets.infos(o.id).get("emplacement", "") == emplacement:
			s.equipement[emplacement] = o
	s.recolte = {}


func memoriser(s: Dictionary, fiche: Dictionary) -> void:
	fiche["inventaire"] = s.inventaire.duplicate(true)
	fiche["equipement"] = s.equipement.duplicate(true)


## À la connexion : inventaire et sacs au sol.
func accueillir(s: Dictionary) -> void:
	envoyer_inventaire(s)
	var liste := []
	for sac in sacs.values():
		liste.append(_infos_sac(sac))
	Reseau.s_sacs.rpc_id(s.id, liste)


func envoyer_inventaire(s: Dictionary) -> void:
	Reseau.s_inventaire.rpc_id(s.id, s.inventaire, s.equipement)


# ------------------------------------------------------------------ Récolte

func sur_recolter(s: Dictionary, actif: bool, c: Vector2i) -> void:
	if not actif or s.mort:
		_arreter(s)
		return
	if not s.recolte.is_empty() and s.recolte.case == c:
		return
	if not _a_portee(s, c):
		_arreter(s)
		return
	s.recolte = {"case": c, "progres": 0.0}


func _a_portee(s: Dictionary, c: Vector2i) -> bool:
	if not Objets.recoltable(serveur.monde.deco_en(c.x, c.y)):
		return false
	return s.pos.distance_to(VueMonde.centre_case(c)) <= Objets.PORTEE_RECOLTE + 10.0


func _arreter(s: Dictionary) -> void:
	if not s.recolte.is_empty():
		s.recolte = {}
		Reseau.s_recolte.rpc_id(s.id, -1.0, Vector2i.ZERO)


func _avancer_recolte(s: Dictionary, delta: float) -> void:
	var c: Vector2i = s.recolte.case
	if s.mort or not _a_portee(s, c):
		_arreter(s)
		return
	var deco: int = serveur.monde.deco_en(c.x, c.y)
	var r: Dictionary = Objets.RECOLTE[deco]
	s.recolte.progres += delta / Objets.duree_recolte(deco, s.role, serveur.combat.a_effet(s, "ruee"), s.stats.recolte)
	if s.recolte.progres < 1.0:
		return
	s.recolte.progres = 0.0
	var objet: String = r.objet
	if objet == "plan":
		objet = Equipement.plan_pour_danger(serveur.monde.danger_en(c.x, c.y))
	if Objets.ajouter(s.inventaire, objet, 1) > 0:
		Reseau.s_message.rpc_id(s.id, "Inventaire plein : jette ou dépose des objets.", "systeme")
		_arreter(s)
		return
	envoyer_inventaire(s)
	var centre := VueMonde.centre_case(c)
	serveur.combat.evenement("recolte", {"id": s.id, "pos": centre, "angle": (centre - s.pos).angle(),
		"objet": objet, "minerai": r.minerai})
	serveur.experience.sur_recolte(s, objet, c)
	var reste: int = _usure.get(c, int(r.coups)) - 1
	if reste > 0:
		_usure[c] = reste
		return
	# Décor épuisé : il disparaît et repoussera plus tard.
	_usure.erase(c)
	_changer_case(c, Monde.Deco.AUCUN)
	if int(r.repousse) > 0:
		serveur.donnees.repousses.append([c.x, c.y, deco, float(r.repousse) * 60.0])
	_arreter(s)


func changer_case(c: Vector2i, deco: int) -> void:
	_changer_case(c, deco)


func _changer_case(c: Vector2i, deco: int) -> void:
	var monde: Monde = serveur.monde
	var cle := Monde.cle_de_case(c.x, c.y)
	var m := monde.morceau(cle)
	if m.is_empty() or not monde.changer_deco(c.x, c.y, deco):
		return
	serveur.sauvegarde.enregistrer_morceau(cle, m)
	serveur.cartes[cle] = Monde.image_carte(m)
	for id in serveur.joueurs:
		Reseau.s_case.rpc_id(id, c, deco)


func _repousser(secondes: float) -> void:
	var restantes := []
	for r in serveur.donnees.repousses:
		r[3] = float(r[3]) - secondes
		if r[3] > 0.0:
			restantes.append(r)
			continue
		var c := Vector2i(int(r[0]), int(r[1]))
		var libre: bool = serveur.monde.deco_en(c.x, c.y) == Monde.Deco.AUCUN
		for s in serveur.joueurs.values():
			if s.pos.distance_to(VueMonde.centre_case(c)) < 30.0:
				libre = false # quelqu'un est dessus : on réessaie plus tard
		if libre:
			_changer_case(c, int(r[2]))
		elif serveur.monde.deco_en(c.x, c.y) == Monde.Deco.AUCUN:
			r[3] = 30.0
			restantes.append(r)
	serveur.donnees.repousses = restantes


# ------------------------------------------------------------------ Sacs et corps

func _infos_sac(sac: Dictionary) -> Dictionary:
	var n := 0
	for o in sac.objets:
		n += int(o.n)
	return {"id": sac.id, "pos": sac.pos, "genre": sac.genre, "nom": sac.nom, "n": n}


func _nouveau_sac(pos: Vector2, objets: Array, genre: String, nom: String) -> Dictionary:
	var sac := {"id": _prochain_sac, "pos": pos, "objets": objets, "genre": genre, "nom": nom,
		"reste": DUREE_CORPS if genre == "corps" else DUREE_SAC}
	_prochain_sac += 1
	sacs[sac.id] = sac
	_annoncer_sac(sac)
	return sac


func _annoncer_sac(sac: Dictionary) -> void:
	var infos := _infos_sac(sac)
	for id in serveur.joueurs:
		Reseau.s_sac.rpc_id(id, infos)


func _retirer_sac(id: int) -> void:
	sacs.erase(id)
	for jid in serveur.joueurs:
		Reseau.s_sac_retire.rpc_id(jid, id)


func retirer_tous_les_sacs() -> int:
	var n := sacs.size()
	for id in sacs.keys():
		_retirer_sac(id)
	return n


## À la mort : tout ce que le joueur porte tombe sur son corps (sauf les objets liés).
func mourir(s: Dictionary) -> void:
	_arreter(s)
	var tombes := []
	for i in s.inventaire.size():
		var o: Dictionary = s.inventaire[i]
		if o.is_empty() or Objets.infos(o.id).get("lie", false):
			continue
		tombes.append(o)
		s.inventaire[i] = {}
	for emplacement in s.equipement:
		var o: Dictionary = s.equipement[emplacement]
		if not o.is_empty() and not Objets.infos(o.id).get("lie", false):
			tombes.append(o)
			s.equipement[emplacement] = {}
	serveur.combat.recalculer(s)
	if tombes.is_empty():
		return
	_nouveau_sac(s.pos, tombes, "corps", s.nom)
	envoyer_inventaire(s)
	Reseau.s_message.rpc_id(s.id, "Tes affaires sont restées sur ton corps (marqué sur la carte). "
		+ "Reviens les chercher avant qu'un autre ne les prenne !", "systeme")


func sur_ramasser(s: Dictionary, id: int) -> void:
	var sac: Dictionary = sacs.get(id, {})
	if sac.is_empty() or s.mort or s.pos.distance_to(sac.pos) > Objets.PORTEE_RAMASSER + 10.0:
		return
	var pris := {}
	var restes := []
	for o in sac.objets:
		var reste := Objets.ajouter_pile(s.inventaire, o)
		if reste < int(o.n):
			pris[o.id] = pris.get(o.id, 0) + int(o.n) - reste
		if reste > 0:
			var r: Dictionary = o.duplicate()
			r.n = reste
			restes.append(r)
	if pris.is_empty():
		Reseau.s_message.rpc_id(s.id, "Inventaire plein.", "systeme")
		return
	envoyer_inventaire(s)
	serveur.combat.evenement("ramasser", {"id": s.id, "pos": sac.pos, "objets": pris})
	if sac.genre == "corps" and sac.nom != s.nom:
		var proprio: Dictionary = serveur.session_par_nom(sac.nom)
		if not proprio.is_empty():
			Reseau.s_message.rpc_id(proprio.id, "%s a pillé ton corps !" % s.nom, "combat")
		serveur.journal("%s pille le corps de %s" % [s.nom, sac.nom])
	elif sac.genre == "corps":
		Reseau.s_message.rpc_id(s.id, "Tu as récupéré tes affaires.", "systeme")
	if restes.is_empty():
		_retirer_sac(id)
	else:
		sac.objets = restes
		_annoncer_sac(sac)
		Reseau.s_message.rpc_id(s.id, "Inventaire plein : il reste des objets au sol.", "systeme")


func sur_jeter(s: Dictionary, case: int) -> void:
	if s.mort or case < 0 or case >= s.inventaire.size() or s.inventaire[case].is_empty():
		return
	var o: Dictionary = s.inventaire[case]
	s.inventaire[case] = {}
	envoyer_inventaire(s)
	# Plusieurs objets jetés au même endroit vont dans le même sac.
	for sac in sacs.values():
		if sac.genre == "sac" and sac.pos.distance_to(s.pos) < 24.0 and sac.objets.size() < Objets.TAILLE_INVENTAIRE:
			sac.objets.append(o)
			sac.reste = DUREE_SAC
			_annoncer_sac(sac)
			return
	_nouveau_sac(s.pos, [o], "sac", s.nom)


## Commande admin : donner des objets.
func donner(s: Dictionary, id: String, n: int) -> int:
	var reste := Objets.ajouter(s.inventaire, id, n)
	envoyer_inventaire(s)
	return n - reste


func vider(s: Dictionary) -> void:
	s.inventaire = Objets.inventaire_vide()
	s.equipement = Equipement.equipement_vide()
	serveur.combat.recalculer(s)
	envoyer_inventaire(s)


# ------------------------------------------------------------------ Boucle

func tick(delta: float) -> void:
	_accu_progres += delta
	var envoyer := _accu_progres >= FREQ_PROGRES
	if envoyer:
		_accu_progres = 0.0
	for s in serveur.joueurs.values():
		if s.recolte.is_empty():
			continue
		_avancer_recolte(s, delta)
		if envoyer and not s.recolte.is_empty():
			Reseau.s_recolte.rpc_id(s.id, s.recolte.progres, s.recolte.case)
	_accu_seconde += delta
	if _accu_seconde < 1.0:
		return
	_repousser(_accu_seconde)
	for sac in sacs.values():
		sac.reste -= _accu_seconde
		if sac.reste <= 0.0:
			_retirer_sac(sac.id)
	_accu_seconde = 0.0
