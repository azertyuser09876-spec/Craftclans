extends Node
## Serveur dédié : il fait autorité sur tout ce qui se passe dans le monde.
## Les clients n'envoient que leurs intentions (direction, chat) ; le serveur
## calcule les positions et les renvoie à tout le monde.

signal journal_ajoute(ligne: String)
signal etat_change # joueurs, boss ou réglages modifiés : le panneau se met à jour

const ATTENTE_BONJOUR_MS := 10000
const COPIE_SECOURS_MS := 30 * 60 * 1000

var config: Dictionary
var donnees: Dictionary
var sauvegarde := Sauvegarde.new()
var monde: Monde
var commandes: Commandes
var actif := false
var demarre_le := 0
var derniere_sauvegarde := ""

## Joueurs connectés : identifiant réseau -> session
var joueurs := {}
var _en_attente := {} # identifiant -> limite (ms) pour envoyer c_bonjour
var _accu_etat := 0.0
var _accu_sauvegarde := 0.0
var _derniere_copie := 0
var _derniere_minute := ""
var _fichier_journal: FileAccess


func _ready() -> void:
	demarre_le = Time.get_ticks_msec()
	_ouvrir_journal()
	journal("Craftclans serveur %s (protocole %d)" % [Config.version, Config.PROTOCOLE])
	config = Sauvegarde.charger_config()
	commandes = Commandes.new(self)
	donnees = sauvegarde.charger()
	journal(sauvegarde.dernier_message)
	if donnees.is_empty():
		journal("Le serveur ne démarre pas pour ne pas abîmer la sauvegarde.")
		return
	monde = Monde.new(int(donnees.graine))
	var port: int = Config.port if Config.port != Config.PORT_DEFAUT else int(config.port)
	var peer := WebSocketMultiplayerPeer.new()
	var err := peer.create_server(port)
	if err != OK:
		journal("ERREUR : impossible d'ouvrir le port %d (déjà utilisé ?). Code %d." % [port, err])
		return
	multiplayer.multiplayer_peer = peer
	multiplayer.peer_connected.connect(_sur_connexion)
	multiplayer.peer_disconnected.connect(_sur_deconnexion)
	Reseau.serveur = self
	actif = true
	_derniere_copie = Time.get_ticks_msec()
	sauvegarde.copie_de_secours()
	sauver()
	journal("En écoute sur le port %d. Sauvegardes : %s" % [port, Sauvegarde.chemin_reel()])
	etat_change.emit()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		if actif:
			sauver()
			actif = false


func arreter() -> void:
	journal("Arrêt du serveur…")
	for id in joueurs.keys():
		Reseau.s_refus.rpc_id(id, "Le serveur s'arrête.")
	sauver()
	actif = false
	await get_tree().create_timer(0.5).timeout
	get_tree().quit()


# ------------------------------------------------------------------ Journal

func _ouvrir_journal() -> void:
	DirAccess.make_dir_recursive_absolute(Sauvegarde.DOSSIER)
	var chemin := Sauvegarde.DOSSIER + "/journal.txt"
	if FileAccess.file_exists(chemin) and FileAccess.open(chemin, FileAccess.READ).get_length() > 5_000_000:
		DirAccess.rename_absolute(chemin, Sauvegarde.DOSSIER + "/journal.ancien.txt")
	_fichier_journal = FileAccess.open(chemin, FileAccess.READ_WRITE if FileAccess.file_exists(chemin) else FileAccess.WRITE)
	if _fichier_journal:
		_fichier_journal.seek_end()


func journal(texte: String) -> void:
	var ligne := "[%s] %s" % [Time.get_time_string_from_system(), texte]
	print(ligne)
	if _fichier_journal:
		_fichier_journal.store_line(ligne)
		_fichier_journal.flush()
	journal_ajoute.emit(ligne)


# ------------------------------------------------------------------ Boucle

func _physics_process(delta: float) -> void:
	if not actif:
		return
	var maintenant := Time.get_ticks_msec()
	for id in _en_attente.keys():
		if maintenant > _en_attente[id]:
			_en_attente.erase(id)
			multiplayer.multiplayer_peer.disconnect_peer(id)
	for s in joueurs.values():
		s.budget = minf(s.budget + 60.0 * delta, 30.0)
	var heure: float = donnees.heure + delta * 24.0 / Config.DUREE_JOURNEE * float(donnees.reglages.vitesse_temps)
	donnees.heure = fmod(heure, 24.0)
	_accu_etat += delta
	if _accu_etat >= 1.0 / Config.FREQ_ETAT:
		_accu_etat = 0.0
		_envoyer_etat()
	_accu_sauvegarde += delta
	if _accu_sauvegarde >= float(config.sauvegarde_auto_secondes):
		_accu_sauvegarde = 0.0
		sauver()
	if maintenant - _derniere_copie > COPIE_SECOURS_MS:
		_derniere_copie = maintenant
		sauvegarde.copie_de_secours()
	_verifier_programmes_boss()


func _envoyer_etat() -> void:
	if joueurs.is_empty():
		return
	var positions := {}
	for id in joueurs:
		var s: Dictionary = joueurs[id]
		positions[id] = [s.pos.x, s.pos.y, s.seq]
	var etat := {"h": donnees.heure, "j": positions}
	for id in joueurs:
		Reseau.s_etat.rpc_id(id, etat)


func sauver() -> void:
	if donnees.is_empty():
		return
	for s in joueurs.values():
		_memoriser(s)
	if sauvegarde.enregistrer(donnees):
		derniere_sauvegarde = Time.get_time_string_from_system()
	else:
		journal("ERREUR : la sauvegarde a échoué.")


func _memoriser(s: Dictionary) -> void:
	var fiche: Dictionary = donnees.joueurs.get(s.nom, {})
	fiche["pos"] = [s.pos.x, s.pos.y]
	fiche["apparence"] = s.apparence
	fiche["vu_le"] = Time.get_datetime_string_from_system(false, true)
	donnees.joueurs[s.nom] = fiche


# ------------------------------------------------------------------ Connexions

func _sur_connexion(id: int) -> void:
	_en_attente[id] = Time.get_ticks_msec() + ATTENTE_BONJOUR_MS


func _sur_deconnexion(id: int) -> void:
	_en_attente.erase(id)
	if not joueurs.has(id):
		return
	var s: Dictionary = joueurs[id]
	_memoriser(s)
	joueurs.erase(id)
	# Joueur hors ligne : il disparaît du monde et garde ce qu'il a sur lui.
	for autre in joueurs:
		Reseau.s_depart.rpc_id(autre, id)
	diffuser("%s a quitté le monde." % s.nom, "systeme")
	journal("Déconnexion : %s" % s.nom)
	sauver()
	etat_change.emit()


func refuser(id: int, raison: String) -> void:
	journal("Refus de %d : %s" % [id, raison])
	Reseau.s_refus.rpc_id(id, raison)
	await get_tree().create_timer(0.3).timeout
	if multiplayer.multiplayer_peer and multiplayer.multiplayer_peer.get_peer(id):
		multiplayer.multiplayer_peer.disconnect_peer(id)


static func pseudo_valide(nom: String) -> bool:
	var re := RegEx.create_from_string("^[\\p{L}0-9_\\-]{2,16}$")
	return re.search(nom) != null


func sur_bonjour(id: int, infos: Dictionary) -> void:
	if not _en_attente.has(id):
		return
	_en_attente.erase(id)
	var nom := str(infos.get("pseudo", "")).strip_edges()
	var jeton := str(infos.get("jeton", ""))
	if int(infos.get("protocole", -1)) != Config.PROTOCOLE:
		refuser(id, "Version incompatible : ton jeu est en %s, le serveur en %s. Mets à jour le jeu." % [infos.get("version", "?"), Config.version])
		return
	if not pseudo_valide(nom):
		refuser(id, "Pseudo invalide : 2 à 16 lettres, chiffres, - ou _.")
		return
	if donnees.bannis.has(nom):
		refuser(id, "Tu es banni de ce serveur. Raison : %s" % donnees.bannis[nom])
		return
	if joueurs.size() >= int(config.joueurs_max):
		refuser(id, "Le serveur est plein.")
		return
	for s in joueurs.values():
		if s.nom == nom:
			refuser(id, "Ce pseudo est déjà connecté.")
			return
	var fiche: Dictionary = donnees.joueurs.get(nom, {})
	if fiche.has("jeton") and fiche.jeton != jeton:
		refuser(id, "Ce pseudo appartient déjà à un autre appareil. Choisis-en un autre, ou demande à l'admin de l'oublier.")
		return
	var nouveau := fiche.is_empty()
	fiche["jeton"] = jeton
	if not fiche.has("admin"):
		# Le tout premier joueur du serveur devient admin.
		fiche["admin"] = donnees.joueurs.is_empty()
	donnees.joueurs[nom] = fiche
	var pos := monde.point_apparition(joueurs.size())
	if fiche.has("pos"):
		# Retour au même endroit, ou à l'endroit libre le plus proche.
		pos = monde.point_libre(Vector2(fiche.pos[0], fiche.pos[1]))
	var s := {
		"id": id, "nom": nom, "pos": pos, "seq": 0, "budget": 30.0,
		"apparence": clampi(int(infos.get("apparence", 0)), 0, Config.NB_APPARENCES - 1),
		"vitesse": 1.0, "vol": false, "dieu": false,
	}
	joueurs[id] = s
	var autres := {}
	for autre_id in joueurs:
		if autre_id != id:
			autres[autre_id] = _infos_publiques(joueurs[autre_id])
	Reseau.s_accueil.rpc_id(id, {
		"id": id, "nom": nom, "apparence": s.apparence, "graine": int(donnees.graine), "heure": donnees.heure, "pos": pos,
		"version": Config.version, "serveur": config.nom, "motd": config.message_du_jour,
		"joueurs": autres, "boss_actifs": boss_actifs(),
	})
	envoyer_reglages(id)
	for autre_id in joueurs:
		if autre_id != id:
			Reseau.s_joueur.rpc_id(autre_id, id, _infos_publiques(s))
	diffuser("%s %s le monde." % [nom, "découvre" if nouveau else "rejoint"], "systeme")
	journal("Connexion : %s (id %d, admin : %s)" % [nom, id, "oui" if fiche.admin else "non"])
	etat_change.emit()


func _infos_publiques(s: Dictionary) -> Dictionary:
	return {"nom": s.nom, "pos": s.pos, "apparence": s.apparence, "admin": est_admin(s.nom)}


func sur_entree(id: int, seq: int, dir: Vector2) -> void:
	var s: Dictionary = joueurs.get(id, {})
	if s.is_empty() or seq <= s.seq:
		return
	s.seq = seq
	if s.budget < 1.0:
		return # trop d'entrées : protection contre l'accélération par triche
	s.budget -= 1.0
	if not dir.is_finite():
		return
	s.pos = Regles.deplacer(monde, s.pos, dir.limit_length(1.0), vitesse_de(s), s.vol)


func vitesse_de(s: Dictionary) -> float:
	return Config.VITESSE_JOUEUR * float(s.vitesse)


func sur_chat(id: int, texte: String) -> void:
	var s: Dictionary = joueurs.get(id, {})
	if s.is_empty():
		return
	texte = texte.strip_edges().left(200)
	if texte == "":
		return
	if texte.begins_with("/"):
		var reponse := commandes.executer(texte.substr(1), s)
		if reponse != "":
			Reseau.s_message.rpc_id(id, reponse, "commande")
		return
	diffuser("%s : %s" % [s.nom, texte], "chat")
	for autre in joueurs:
		Reseau.s_evenement.rpc_id(autre, "bulle", {"id": id, "texte": texte})
	journal("[chat] %s : %s" % [s.nom, texte])


func diffuser(texte: String, genre: String) -> void:
	for id in joueurs:
		Reseau.s_message.rpc_id(id, texte, genre)


# ------------------------------------------------------------------ Administration
# Utilisé par le panneau de gestion et par les commandes (/aide en jeu).

func session_par_nom(nom: String) -> Dictionary:
	for s in joueurs.values():
		if s.nom.to_lower() == nom.to_lower():
			return s
	return {}


func est_admin(nom: String) -> bool:
	return bool(donnees.joueurs.get(nom, {}).get("admin", false))


func envoyer_reglages(id: int) -> void:
	var s: Dictionary = joueurs.get(id, {})
	if s.is_empty():
		return
	Reseau.s_reglages.rpc_id(id, {
		"mode_dev": donnees.reglages.mode_dev, "cheats": donnees.reglages.cheats,
		"admin": est_admin(s.nom), "vitesse": vitesse_de(s), "vol": s.vol, "dieu": s.dieu,
	})


func reglages_pour_tous() -> void:
	for id in joueurs:
		envoyer_reglages(id)
	etat_change.emit()


func definir_reglage(cle: String, valeur) -> void:
	donnees.reglages[cle] = valeur
	journal("Réglage %s = %s" % [cle, str(valeur)])
	reglages_pour_tous()


func definir_admin(nom: String, admin: bool) -> bool:
	if not donnees.joueurs.has(nom):
		return false
	donnees.joueurs[nom]["admin"] = admin
	journal("%s %s admin." % [nom, "devient" if admin else "n'est plus"])
	var s := session_par_nom(nom)
	if not s.is_empty():
		envoyer_reglages(s.id)
		Reseau.s_message.rpc_id(s.id, "Tu es maintenant admin. Tape /aide." if admin else "Tu n'es plus admin.", "systeme")
	etat_change.emit()
	return true


func definir_cheat(s: Dictionary, cle: String, valeur) -> void:
	s[cle] = valeur
	journal("Triche %s pour %s : %s" % [cle, s.nom, str(valeur)])
	envoyer_reglages(s.id)
	etat_change.emit()


func expulser(nom: String, raison: String) -> bool:
	var s := session_par_nom(nom)
	if s.is_empty():
		return false
	refuser(s.id, "Expulsé du serveur. %s" % raison)
	return true


func bannir(nom: String, raison: String) -> void:
	donnees.bannis[nom] = raison if raison != "" else "aucune"
	expulser(nom, raison)
	journal("Banni : %s (%s)" % [nom, raison])
	etat_change.emit()


func debannir(nom: String) -> bool:
	var ok: bool = donnees.bannis.erase(nom)
	if ok:
		journal("Débanni : %s" % nom)
		etat_change.emit()
	return ok


## Oublie un joueur hors ligne : son pseudo redevient libre (utile s'il a changé d'appareil).
func oublier_joueur(nom: String) -> bool:
	if not session_par_nom(nom).is_empty():
		return false
	var ok: bool = donnees.joueurs.erase(nom)
	etat_change.emit()
	return ok


func teleporter(s: Dictionary, pos: Vector2) -> void:
	s.pos = monde.point_libre(pos) if not s.vol else pos
	Reseau.s_teleport.rpc_id(s.id, s.pos)


func annonce(texte: String) -> void:
	diffuser("[Annonce] " + texte, "annonce")
	journal("Annonce : " + texte)


func definir_heure(h: float) -> void:
	donnees.heure = fposmod(h, 24.0)


func reinitialiser_monde() -> void:
	journal("REMISE À ZÉRO du monde demandée par l'admin.")
	for id in joueurs.keys():
		Reseau.s_refus.rpc_id(id, "Le monde vient d'être remis à zéro. Reconnecte-toi !")
		multiplayer.multiplayer_peer.disconnect_peer(id)
	joueurs.clear()
	sauver()
	sauvegarde.archiver("remise-a-zero")
	var anciens: Dictionary = donnees.joueurs
	var bannis: Dictionary = donnees.bannis
	donnees = Sauvegarde.monde_vierge()
	# Les identités (pseudo, appareil, admin) et les bannissements sont gardés.
	for nom in anciens:
		donnees.joueurs[nom] = {"jeton": anciens[nom].get("jeton", ""), "admin": anciens[nom].get("admin", false)}
	donnees.bannis = bannis
	monde = Monde.new(int(donnees.graine))
	sauver()
	journal("Nouveau monde créé (graine %d). L'ancien est dans les archives." % int(donnees.graine))
	etat_change.emit()


# ------------------------------------------------------------------ Boss mondiaux

func etat_boss(id: String) -> Dictionary:
	if not donnees.boss.has(id):
		donnees.boss[id] = {"etat": "dormant", "programmes": []}
	return donnees.boss[id]


func boss_actifs() -> Array:
	var liste := []
	for b in DonneesBoss.LISTE:
		if etat_boss(b.id).etat == "actif":
			liste.append(b.nom)
	return liste


func activer_boss(id: String) -> bool:
	var b := DonneesBoss.par_id(id)
	if b.is_empty():
		return false
	var e := etat_boss(id)
	e.etat = "actif"
	e["active_le"] = Time.get_datetime_string_from_system(false, true)
	journal("Boss mondial activé : %s" % b.nom)
	diffuser("%s s'est réveillé ! (%s)" % [b.nom, b.lieu], "boss")
	for pid in joueurs:
		Reseau.s_evenement.rpc_id(pid, "boss", {"nom": b.nom, "lieu": b.lieu, "etat": "actif"})
	etat_change.emit()
	return true


func endormir_boss(id: String) -> bool:
	var b := DonneesBoss.par_id(id)
	if b.is_empty():
		return false
	etat_boss(id).etat = "dormant"
	journal("Boss mondial endormi : %s" % b.nom)
	diffuser("%s s'est rendormi." % b.nom, "boss")
	etat_change.emit()
	return true


## quand : « AAAA-MM-JJ HH:MM » (une fois) ou « hebdo J HH:MM » (J = 0 dimanche … 6 samedi).
func programmer_boss(id: String, quand: String) -> bool:
	if DonneesBoss.par_id(id).is_empty():
		return false
	var une_fois := RegEx.create_from_string("^\\d{4}-\\d{2}-\\d{2} \\d{2}:\\d{2}$")
	var hebdo := RegEx.create_from_string("^hebdo [0-6] \\d{2}:\\d{2}$")
	if une_fois.search(quand) == null and hebdo.search(quand) == null:
		return false
	etat_boss(id).programmes.append(quand)
	journal("Boss %s programmé : %s" % [id, quand])
	etat_change.emit()
	return true


func deprogrammer_boss(id: String) -> void:
	etat_boss(id).programmes.clear()
	etat_change.emit()


func _verifier_programmes_boss() -> void:
	var d := Time.get_datetime_dict_from_system()
	var minute := "%04d-%02d-%02d %02d:%02d" % [d.year, d.month, d.day, d.hour, d.minute]
	if minute == _derniere_minute:
		return
	_derniere_minute = minute
	var hhmm := minute.right(5)
	for b in DonneesBoss.LISTE:
		var e := etat_boss(b.id)
		var restants := []
		var declencher := false
		for p in e.programmes:
			if p.begins_with("hebdo"):
				restants.append(p)
				if int(p.get_slice(" ", 1)) == d.weekday and p.get_slice(" ", 2) == hhmm:
					declencher = true
			elif p <= minute:
				declencher = true # date passée (même si le serveur était éteint)
			else:
				restants.append(p)
		if restants.size() != e.programmes.size():
			e.programmes = restants
			etat_change.emit()
		if declencher and e.etat != "actif":
			activer_boss(b.id)
