extends Node
## Tous les messages réseau passent par ici (WebSocket, port 8000 par défaut).
## WebSocket est utilisé pour tous les clients (exe, apk, et plus tard le web).
## Préfixe c_ : envoyé par un client au serveur. Préfixe s_ : envoyé par le serveur.

signal connecte
signal echec(raison: String)
signal tentative(url: String)
signal deconnecte(raison: String)
signal accueil(infos: Dictionary)
signal etat_recu(etat: Dictionary)
signal joueur_arrive(id: int, infos: Dictionary)
signal joueur_parti(id: int)
signal message_recu(texte: String, genre: String)
signal reglages_recus(reglages: Dictionary)
signal teleporte(pos: Vector2)
signal evenement(genre: String, donnees: Dictionary)
signal pong(ms: int)
signal morceau_recu(cle: Vector2i, donnees: PackedByteArray)
signal case_changee(c: Vector2i, deco: int)
signal inventaire_recu(inv: Array)
signal recolte_recue(progres: float, c: Vector2i)
signal sacs_recus(liste: Array)
signal sac_recu(infos: Dictionary)
signal sac_retire(id: int)

var serveur: Node = null # renseigné côté serveur
var raison_refus := ""
var _limite_connexion := 0.0
var _essais: Array = [] # adresses qui restent à essayer
var _tentes: Array = [] # adresses déjà essayées (pour le message d'erreur)
const DELAI_ESSAI := 6000


# ------------------------------------------------------------------ Client

func connecter(adresse: String, infos: Dictionary) -> void:
	fermer()
	raison_refus = ""
	set_meta("infos", infos)
	var cible := decouper_adresse(adresse)
	if cible.url != "":
		_essais = [cible.url]
	elif cible.hote.is_valid_ip_address():
		_essais = [url_de(cible.hote, cible.port)]
	else:
		# Un nom (duckdns…) peut avoir une adresse IPv6 et une IPv4 : on essaie les deux.
		var ips := IP.resolve_hostname_addresses(cible.hote, IP.TYPE_ANY)
		if ips.is_empty():
			echec.emit("Adresse introuvable : %s.\nVérifie l'orthographe et la connexion Internet de l'appareil." % cible.hote)
			return
		var v6 := []
		var v4 := []
		for ip in ips:
			(v6 if ":" in ip else v4).append(url_de(ip, cible.port))
		_essais = v6 + v4
	_tentes = []
	_essayer_suivant()


## Essaie l'adresse suivante de la liste (IPv6 puis IPv4), ou abandonne.
func _essayer_suivant() -> void:
	_fermer_peer()
	if _essais.is_empty():
		_limite_connexion = 0.0
		echec.emit(_message_echec())
		return
	var url: String = _essais.pop_front()
	_tentes.append(url)
	var peer := WebSocketMultiplayerPeer.new()
	peer.inbound_buffer_size = 1 << 21 # les morceaux du monde arrivent par paquets
	if peer.create_client(url) != OK:
		_essayer_suivant.call_deferred()
		return
	multiplayer.multiplayer_peer = peer
	_limite_connexion = Time.get_ticks_msec() + DELAI_ESSAI
	tentative.emit(url)
	if not multiplayer.connected_to_server.is_connected(_sur_connecte):
		multiplayer.connected_to_server.connect(_sur_connecte)
		multiplayer.connection_failed.connect(_sur_echec)
		multiplayer.server_disconnected.connect(_sur_deconnexion)


func _message_echec() -> String:
	var essaye := ", ".join(PackedStringArray(_tentes)).replace("ws://", "")
	return ("Impossible de joindre le serveur (%s).\n" % essaye
		+ "Même Wi-Fi que le serveur : mets l'adresse locale du PC (192.168…).\n"
		+ "Depuis Internet : l'adresse IPv6 ou IPv4 publique affichée dans le panneau du serveur.")


## Découpe ce que le joueur a tapé : nom, IPv4, IPv6 (avec ou sans crochets), port facultatif.
## Renvoie {hote, port, url} ; url n'est rempli que si le joueur a tapé une adresse ws:// complète.
static func decouper_adresse(adresse: String) -> Dictionary:
	adresse = adresse.strip_edges()
	var r := {"hote": "", "port": Config.PORT_DEFAUT, "url": ""}
	if adresse.begins_with("ws://") or adresse.begins_with("wss://"):
		r.url = adresse
		return r
	if adresse == "":
		adresse = "localhost"
	if adresse.begins_with("["): # [2a01:…]:8000
		var fin := adresse.find("]")
		r.hote = adresse.substr(1, fin - 1) if fin > 0 else adresse.substr(1)
		var reste := adresse.substr(fin + 1) if fin > 0 else ""
		if reste.begins_with(":") and reste.substr(1).is_valid_int():
			r.port = int(reste.substr(1))
	elif adresse.count(":") > 1: # IPv6 sans crochets : pas de port possible
		r.hote = adresse
	elif ":" in adresse:
		r.hote = adresse.get_slice(":", 0)
		if adresse.get_slice(":", 1).is_valid_int():
			r.port = int(adresse.get_slice(":", 1))
	else:
		r.hote = adresse
	r.hote = r.hote.get_slice("%", 0) if not r.hote.begins_with("fe80") else r.hote
	return r


static func url_de(hote: String, port: int) -> String:
	return "ws://%s:%d" % ["[%s]" % hote if ":" in hote else hote, port]


## Adresse lisible, pour l'afficher.
static func adresse_vers_url(adresse: String) -> String:
	var c := decouper_adresse(adresse)
	return c.url if c.url != "" else url_de(c.hote, c.port)


func _fermer_peer() -> void:
	if multiplayer.multiplayer_peer and not multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()


func fermer() -> void:
	_limite_connexion = 0.0
	_essais = []
	_fermer_peer()


func est_connecte() -> bool:
	var p := multiplayer.multiplayer_peer
	return p != null and not p is OfflineMultiplayerPeer \
		and p.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


func _process(_delta: float) -> void:
	if _limite_connexion > 0.0 and Time.get_ticks_msec() > _limite_connexion:
		_limite_connexion = 0.0
		if not est_connecte():
			_essayer_suivant()


func _sur_connecte() -> void:
	_limite_connexion = 0.0
	_essais = []
	c_bonjour.rpc_id(1, get_meta("infos", {}))
	connecte.emit()


func _sur_echec() -> void:
	_essayer_suivant()


func _sur_deconnexion() -> void:
	fermer()
	deconnecte.emit(raison_refus if raison_refus != "" else "Connexion au serveur perdue.")


# ------------------------------------------------------------------ Client vers serveur

@rpc("any_peer", "call_remote", "reliable")
func c_bonjour(infos: Dictionary) -> void:
	if serveur: serveur.sur_bonjour(multiplayer.get_remote_sender_id(), infos)


@rpc("any_peer", "call_remote", "unreliable_ordered", 1)
func c_entree(seq: int, dir: Vector2, boutons: int) -> void:
	if serveur: serveur.sur_entree(multiplayer.get_remote_sender_id(), seq, dir, boutons)


@rpc("any_peer", "call_remote", "reliable")
func c_action(genre: String, cible: Vector2, charge: float) -> void:
	if serveur: serveur.sur_action(multiplayer.get_remote_sender_id(), genre, cible, charge)


@rpc("any_peer", "call_remote", "reliable")
func c_role(role: String) -> void:
	if serveur: serveur.sur_role(multiplayer.get_remote_sender_id(), role)


@rpc("any_peer", "call_remote", "reliable")
func c_chat(texte: String) -> void:
	if serveur: serveur.sur_chat(multiplayer.get_remote_sender_id(), texte)


@rpc("any_peer", "call_remote", "reliable")
func c_recolter(actif: bool, c: Vector2i) -> void:
	if serveur: serveur.sur_recolter(multiplayer.get_remote_sender_id(), actif, c)


@rpc("any_peer", "call_remote", "reliable")
func c_ramasser(id: int) -> void:
	if serveur: serveur.sur_ramasser(multiplayer.get_remote_sender_id(), id)


@rpc("any_peer", "call_remote", "reliable")
func c_jeter(case: int) -> void:
	if serveur: serveur.sur_jeter(multiplayer.get_remote_sender_id(), case)


@rpc("any_peer", "call_remote", "unreliable")
func c_ping(t: int) -> void:
	if serveur: s_pong.rpc_id(multiplayer.get_remote_sender_id(), t)


# ------------------------------------------------------------------ Serveur vers client

@rpc("authority", "call_remote", "reliable")
func s_accueil(infos: Dictionary) -> void:
	accueil.emit(infos)


@rpc("authority", "call_remote", "reliable")
func s_refus(raison: String) -> void:
	raison_refus = raison


@rpc("authority", "call_remote", "unreliable_ordered", 1)
func s_etat(etat: Dictionary) -> void:
	etat_recu.emit(etat)


@rpc("authority", "call_remote", "reliable")
func s_joueur(id: int, infos: Dictionary) -> void:
	joueur_arrive.emit(id, infos)


@rpc("authority", "call_remote", "reliable")
func s_depart(id: int) -> void:
	joueur_parti.emit(id)


@rpc("authority", "call_remote", "reliable")
func s_message(texte: String, genre: String) -> void:
	message_recu.emit(texte, genre)


@rpc("authority", "call_remote", "reliable")
func s_reglages(reglages: Dictionary) -> void:
	reglages_recus.emit(reglages)


@rpc("authority", "call_remote", "reliable", 2)
func s_morceau(cle: Vector2i, donnees: PackedByteArray) -> void:
	morceau_recu.emit(cle, donnees)


## Même canal que les morceaux : un changement n'arrive jamais avant le morceau qu'il modifie.
@rpc("authority", "call_remote", "reliable", 2)
func s_case(c: Vector2i, deco: int) -> void:
	case_changee.emit(c, deco)


@rpc("authority", "call_remote", "reliable")
func s_inventaire(inv: Array) -> void:
	inventaire_recu.emit(inv)


@rpc("authority", "call_remote", "unreliable_ordered", 1)
func s_recolte(progres: float, c: Vector2i) -> void:
	recolte_recue.emit(progres, c)


@rpc("authority", "call_remote", "reliable")
func s_sacs(liste: Array) -> void:
	sacs_recus.emit(liste)


@rpc("authority", "call_remote", "reliable")
func s_sac(infos: Dictionary) -> void:
	sac_recu.emit(infos)


@rpc("authority", "call_remote", "reliable")
func s_sac_retire(id: int) -> void:
	sac_retire.emit(id)


@rpc("authority", "call_remote", "reliable")
func s_teleport(pos: Vector2) -> void:
	teleporte.emit(pos)


@rpc("authority", "call_remote", "reliable")
func s_evenement(genre: String, donnees: Dictionary) -> void:
	evenement.emit(genre, donnees)


@rpc("authority", "call_remote", "unreliable")
func s_pong(t: int) -> void:
	pong.emit(Time.get_ticks_msec() - t)
