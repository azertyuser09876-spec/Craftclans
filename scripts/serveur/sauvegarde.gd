class_name Sauvegarde
extends RefCounted
## Sauvegarde du monde du serveur, prévue pour survivre aux mises à jour.
##
## Chaque sauvegarde porte un numéro de format. Au chargement :
##  - même format : chargée telle quelle ;
##  - format plus ancien mais >= FORMAT_MIN_COMPATIBLE : convertie par les MIGRATIONS ;
##  - format plus ancien que FORMAT_MIN_COMPATIBLE (grosse mise à jour qui change tout) :
##    l'ancien monde est archivé dans « archives » (rien n'est effacé) et un nouveau monde est créé.
##
## Pour une mise à jour normale qui ajoute des données : augmenter FORMAT et ajouter
## une fonction de migration. Pour une grosse mise à jour qui remet à zéro : mettre
## FORMAT_MIN_COMPATIBLE égal au nouveau FORMAT.

const FORMAT := 1
const FORMAT_MIN_COMPATIBLE := 1
const NB_COPIES := 10

const DOSSIER := "user://serveur"
const FICHIER_MONDE := DOSSIER + "/monde/monde.json"
const FICHIER_CONFIG := DOSSIER + "/config.json"
const DOSSIER_COPIES := DOSSIER + "/copies"
const DOSSIER_ARCHIVES := DOSSIER + "/archives"

## Migrations : clé = format de départ, valeur = nom de la fonction qui passe au format suivant.
const MIGRATIONS := {
	# 1: "_migrer_1_vers_2",
}

var dernier_message := ""


static func monde_vierge() -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	return {
		"format": FORMAT,
		"version_jeu": Config.version,
		"cree_le": Time.get_datetime_string_from_system(false, true),
		"graine": rng.randi_range(1, 2_000_000_000),
		"heure": 9.0,
		"joueurs": {}, # par pseudo
		"bannis": {}, # pseudo -> raison
		"boss": {}, # id -> état
		"reglages": {"mode_dev": false, "cheats": true, "vitesse_temps": 1.0, "pvp": true},
	}


func charger() -> Dictionary:
	DirAccess.make_dir_recursive_absolute(DOSSIER + "/monde")
	if not FileAccess.file_exists(FICHIER_MONDE):
		dernier_message = "Aucune sauvegarde : création d'un nouveau monde."
		return monde_vierge()
	var donnees = JSON.parse_string(FileAccess.get_file_as_string(FICHIER_MONDE))
	if typeof(donnees) != TYPE_DICTIONARY:
		archiver("illisible")
		dernier_message = "Sauvegarde illisible : archivée, nouveau monde créé."
		return monde_vierge()
	var format := int(donnees.get("format", 0))
	if format > FORMAT:
		# Sauvegarde d'une version plus récente : on refuse de l'écraser.
		push_error("Sauvegarde au format %d, plus récent que ce serveur (%d)." % [format, FORMAT])
		dernier_message = "ATTENTION : la sauvegarde vient d'une version plus récente du serveur. Mets le serveur à jour."
		return {}
	if format < FORMAT_MIN_COMPATIBLE:
		archiver("format%d" % format)
		dernier_message = "Grosse mise à jour : l'ancien monde (format %d) est archivé, nouveau monde créé." % format
		return monde_vierge()
	while format < FORMAT:
		var fonction: String = MIGRATIONS.get(format, "")
		if fonction == "":
			archiver("format%d" % format)
			dernier_message = "Pas de conversion depuis le format %d : ancien monde archivé." % format
			return monde_vierge()
		donnees = call(fonction, donnees)
		format += 1
		donnees["format"] = format
	# Complète les champs ajoutés depuis (valeurs par défaut).
	var vierge := monde_vierge()
	for cle in vierge:
		if not donnees.has(cle):
			donnees[cle] = vierge[cle]
	for cle in vierge.reglages:
		if not donnees.reglages.has(cle):
			donnees.reglages[cle] = vierge.reglages[cle]
	dernier_message = "Monde chargé (créé le %s, graine %d)." % [donnees.get("cree_le", "?"), int(donnees.graine)]
	return donnees


## Écrit d'abord dans un fichier temporaire puis le renomme : une coupure de courant
## pendant l'écriture ne peut pas abîmer la sauvegarde existante.
func enregistrer(donnees: Dictionary) -> bool:
	DirAccess.make_dir_recursive_absolute(DOSSIER + "/monde")
	donnees["format"] = FORMAT
	donnees["version_jeu"] = Config.version
	donnees["enregistre_le"] = Time.get_datetime_string_from_system(false, true)
	var tmp := FICHIER_MONDE + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_error("Impossible d'écrire %s" % tmp)
		return false
	f.store_string(JSON.stringify(donnees, "\t"))
	f.close()
	var dossier := DirAccess.open(DOSSIER + "/monde")
	if FileAccess.file_exists(FICHIER_MONDE):
		dossier.remove("monde.json")
	return dossier.rename("monde.json.tmp", "monde.json") == OK


## Copie de secours horodatée ; garde les NB_COPIES plus récentes.
func copie_de_secours() -> void:
	if not FileAccess.file_exists(FICHIER_MONDE):
		return
	DirAccess.make_dir_recursive_absolute(DOSSIER_COPIES)
	var nom := "monde-%s.json" % _horodatage()
	DirAccess.copy_absolute(FICHIER_MONDE, DOSSIER_COPIES + "/" + nom)
	var fichiers := Array(DirAccess.get_files_at(DOSSIER_COPIES))
	fichiers.sort()
	while fichiers.size() > NB_COPIES:
		DirAccess.remove_absolute(DOSSIER_COPIES + "/" + fichiers.pop_front())


## Déplace le monde actuel dans les archives (il n'est jamais effacé).
func archiver(raison: String) -> void:
	if not DirAccess.dir_exists_absolute(DOSSIER + "/monde"):
		return
	DirAccess.make_dir_recursive_absolute(DOSSIER_ARCHIVES)
	var cible := DOSSIER_ARCHIVES + "/monde-%s-%s" % [_horodatage(), raison]
	DirAccess.rename_absolute(DOSSIER + "/monde", cible)
	DirAccess.make_dir_recursive_absolute(DOSSIER + "/monde")


static func _horodatage() -> String:
	return Time.get_datetime_string_from_system(false, false).replace(":", "-").replace("T", "_")


static func chemin_reel() -> String:
	return ProjectSettings.globalize_path(DOSSIER)


# ------------------------------------------------------------------ Configuration du serveur
# Séparée du monde : elle survit aux remises à zéro.

static func charger_config() -> Dictionary:
	var config := {
		"nom": "Serveur Craftclans",
		"port": Config.PORT_DEFAUT,
		"mot_de_passe_admin": _mot_de_passe(),
		"message_du_jour": "Bienvenue sur Craftclans !",
		"joueurs_max": 16,
		"sauvegarde_auto_secondes": 60,
	}
	if FileAccess.file_exists(FICHIER_CONFIG):
		var lu = JSON.parse_string(FileAccess.get_file_as_string(FICHIER_CONFIG))
		if typeof(lu) == TYPE_DICTIONARY:
			config.merge(lu, true)
	enregistrer_config(config)
	return config


static func enregistrer_config(config: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(DOSSIER)
	var f := FileAccess.open(FICHIER_CONFIG, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(config, "\t"))


static func _mot_de_passe() -> String:
	var lettres := "abcdefghjkmnpqrstuvwxyz23456789"
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var mdp := ""
	for i in 8:
		mdp += lettres[rng.randi_range(0, lettres.length() - 1)]
	return mdp
