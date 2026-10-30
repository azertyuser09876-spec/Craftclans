extends Node
## Réglages communs au client et au serveur, et lecture de la ligne de commande.

## À augmenter à chaque changement des messages réseau : un client et un serveur
## de protocoles différents refusent de jouer ensemble.
const PROTOCOLE := 5

const PORT_DEFAUT := 8000
const TAILLE_TUILE := 32
const VITESSE_JOUEUR := 140.0
const RAYON_JOUEUR := 7.0
const FREQ_ETAT := 20.0 # envois de l'état du monde par seconde
const DUREE_JOURNEE := 1200.0 # secondes réelles pour 24 h de jeu
const NB_APPARENCES := 8

var version := "0.0.0"
var est_serveur := false
var sans_affichage := false
var port := PORT_DEFAUT
## Options de test : --auto-connexion=pseudo@adresse et --auto-deplacement
var auto_connexion := ""
var auto_deplacement := false
## Option de test : --capture=fichier.png:secondes enregistre une capture d'écran puis quitte.
var capture := ""
## Option de test : --auto-commande=texte envoie ce texte dans le chat après la connexion.
var auto_commande := ""
## Option de test : --auto-recolte garde la touche de récolte appuyée.
var auto_recolte := false
## Option de test : --tactile affiche l'interface du téléphone sur PC.
var forcer_tactile := false


func _enter_tree() -> void:
	version = str(ProjectSettings.get_setting("application/config/version", "0.0.0"))
	var args := OS.get_cmdline_args() + OS.get_cmdline_user_args()
	est_serveur = OS.has_feature("serveur") or OS.has_feature("dedicated_server") or "--serveur" in args
	sans_affichage = DisplayServer.get_name() == "headless"
	for a in args:
		if a.begins_with("--port="):
			port = int(a.get_slice("=", 1))
		elif a.begins_with("--auto-connexion="):
			auto_connexion = a.get_slice("=", 1)
		elif a.begins_with("--capture="):
			capture = a.get_slice("=", 1)
		elif a.begins_with("--auto-commande="):
			auto_commande = a.substr(a.find("=") + 1)
		elif a == "--tactile":
			forcer_tactile = true
		elif a == "--auto-deplacement":
			auto_deplacement = true
		elif a == "--auto-recolte":
			auto_recolte = true
	_creer_touches()


func est_mobile() -> bool:
	return forcer_tactile or OS.has_feature("mobile") or DisplayServer.is_touchscreen_available()


func _creer_touches() -> void:
	# Touches physiques : W A S D correspondent à Z Q S D sur un clavier AZERTY.
	_action("haut", [KEY_W, KEY_UP])
	_action("bas", [KEY_S, KEY_DOWN])
	_action("gauche", [KEY_A, KEY_LEFT])
	_action("droite", [KEY_D, KEY_RIGHT])
	_action("chat", [KEY_ENTER, KEY_KP_ENTER])
	_action("debug", [KEY_F3])
	_action("menu", [KEY_ESCAPE])
	_action("esquive", [KEY_SPACE, KEY_SHIFT])
	_action("competence", [KEY_E])
	_action("role", [KEY_R])
	_action("carte", [KEY_M, KEY_SEMICOLON])
	_action("interagir", [KEY_F])
	_action("inventaire", [KEY_I, KEY_TAB])
	_action("fabriquer", [KEY_C])


func _action(nom: String, touches: Array) -> void:
	if InputMap.has_action(nom):
		return
	InputMap.add_action(nom)
	for t in touches:
		var ev := InputEventKey.new()
		ev.physical_keycode = t
		InputMap.action_add_event(nom, ev)
