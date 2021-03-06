#!/usr/bin/env bash
# Service de construction automatisé des paquets de 0Linux.

# Ce script automatise plusieurs tâches :
#
#   - il évalue les derniers commmits du dépôt git  et lance la ocnstruction
#     des paquets correspondants avec 'construction.sh'
#   - il lance ensuite 'trouver_binaires_casses.sh' pour vérifier l'intégrité
#     de l'ensemble du système
#   - il génère le catalogue en ligne des paquets fraîchement construits via
#     '../catalogue/catalogue.sh'
#   - il génère enfin la base de données des paquets 'paquets.db' et envoie le
#     tout sur le serveur spécifié avec le script '0mir'.
#
# On peut « nourrir » soi-même la file d'attente pour forcer des constructions
# de paquets en ajoutant du contenu à la file d'attente (1 paquet par ligne).

# Le fichier du processus :
PIDFILE="/var/lock/service_construction.pid"

# La file d'attente :
FILEDATTENTE="/tmp/en_attente.tmp"

# La file d'attente du catalogue pour le wiki :
FILEDATTENTECATALOGUE="/tmp/catalogue_en_attente.tmp"

# Emplacement du dépôt des paquets résultant de la construction. À définir en
# tant que variable d'environnement car utilisée aussi dans 'construction.sh'
# entre autres.
PKGREPO=${PKGREPO:-/usr/local/paquets}

# Emplacement où on compile et on empaquète. Utilisée dans 'fonctions_paquets.sh'
# également, à définir en variable d'environnement ou à laisser telle quelle :
MARMITE=${MARMITE:-/tmp/0-marmite}

# ...et où on stocke les journaux de compilation :
MARMITELOGS=${MARMITELOGS:-${MARMITE}/logs}

# On supprime un éventuel déchet '.pid' restant :
if [ "$(ps axc | grep 'service_construction')" = "" ]; then
	rm -f ${PIDFILE}
fi

# On vérifie si un '.pid' existe (le script tourne déjà) :
[ -r ${PIDFILE} ] && exit 0

# On vérifie si un 'construction.sh' n'est pas déjà en cours :
[ ! "$(ps axc | grep 'construction.sh')" = "" ] && exit 0

# On est toujours là ? OK, on crée donc le fichier du processus : 
echo "$$" > ${PIDFILE}

# On s'assure que l'environnement est correctement configuré :
source /etc/profile

# On identifie la version du système :
source /etc/os-release

# La fonction de traitement de la file d'attente :
# $f
traiter_filedattente() {
	
	# On s'assure que la file d'attente existe :
	touch ${FILEDATTENTE}
	
	# On traite la file d'attente (qu'on peut remplir aussi manuellement au besoin) :
	cat ${FILEDATTENTE} | while read recette_demandee; do
		if [ ! "${recette_demandee}" = "" ]; then
			
			# On compile/installe (nvidia et catalyst sont installés ailleurs pour ne pas polluer
			# le système avec leurs doublons) :
			./construction.sh ${recette_demandee}
			
			# On envoie le paquet en cours à la file d'attente du catalogue pour le régénérer
			# si le log est absent (l'empaquetage a réussi) :
			if [ ! -r ${MARMITELOGS}/${recette_demandee}.log ]; then
				echo "${recette_demandee}" >> ${FILEDATTENTECATALOGUE}
			fi
			
			# On nettoie le(s) paquet(s) demandé(s) (première ligne) de la file d'attente :
			sed -i '1d' ${FILEDATTENTE}
		fi
	done
}

# La fonction de traitement de la file d'attente du ctaalogue pour le wiki :
# $f
traiter_filedattente_catalogue() {
	
	# On s'assure que la file d'attente existe :
	touch ${FILEDATTENTECATALOGUE}
	
	# On traite la file d'attente (qu'on peut remplir aussi manuellement au besoin) :
	cat ${FILEDATTENTECATALOGUE} | while read catalogue_demande; do
		if [ ! "${catalogue_demande}" = "" ]; then
			
			# On génère le catalogue du paquet et son index :
			( cd ../catalogue ; FORCECATALOGUE=oui ../catalogue/catalogue.sh ${catalogue_demande} )
			
			# On nettoie le(s) catalogue(s) demandé(s) (première ligne) de la file d'attente :
			sed -i '1d' ${FILEDATTENTECATALOGUE}
		fi
	done
}

### Étape 1 : on vérifie si un commit a eu lieu dans les recettes :

# On note le hash du dernier commit :
OLD_HEAD="$(git rev-parse HEAD)"

# On rapatrie les éventuelles modifications :
git pull origin master

# On note l'éventuel nouveau hash :
NEW_HEAD="$(git rev-parse HEAD)"

# Si ça a changé, on ajoute les recettes changées à notre file d'attente :
if [ ! $OLD_HEAD = $NEW_HEAD ]; then
	
	# On extrait les recettes modifiées en supprimant les lignes vides et tout 
	# espace rencontré et on ajoute le résultat à la file d'attente :
	git --no-pager diff --name-only $OLD_HEAD $NEW_HEAD | \
		xargs basename -a | \
		grep -E '\.recette' | \
		sed -e 's@\.recette@@' -e '/^$/d' -e '/[[:space:]]/d' >> ${FILEDATTENTE}
fi

### Étape 2 : on compile/installe le contenu de la file d'attente :

# Doit-on vérifier les binaires du système ?
CHECKBINAIRES="non"

# ... Oui, si la file d'attente contient des paquets à construire :
if [ $(cat ${FILEDATTENTE} | wc -l) -gt 0 ]; then
	CHECKBINAIRES="oui"
fi

# On traite la file d'attente pour la vider :
traiter_filedattente

# On doit vérifier les binaires du système. Si des paquets sont retournés, on les ajoute
# à la file d'attente pour construction immédiate :
if [ "${CHECKBINAIRES}" = "oui" ]; then
	sudo ./trouver_binaires_casses.sh /usr/bin /usr/sbin /usr/lib* /usr/share >> ${FILEDATTENTE}
	
	# On traite à nouveau la file d'attente pour la vider :
	traiter_filedattente
fi

### Étape 3 : on vérifie le dépôt + génère les descriptions + synchronise le serveur distant :
./0mir

### Étape 4 : on régénère les catalogues maintenant que 'paquets.db' est à jour :
traiter_filedattente_catalogue

### Étape 5 : on '0mir' à nouveau, spécifiquement pour envoyer le catalogue à jour :
./0mir

# On peut supprimer le fichier du processus pour les prochaines fois :
rm -f ${PIDFILE}

# C'est fini.
