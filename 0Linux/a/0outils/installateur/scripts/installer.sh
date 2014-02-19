#!/usr/bin/env bash

# On nettoie :
unset BLURB DIR0

# Quelques vérif' avant l'installation des paquets :
MEDIACHOISI="$(cat $TMP/choix_media)"
if [ ! -d ${MEDIACHOISI} ]; then
	echo "Erreur fatale : le média choisi ${MEDIACHOISI} n'est pas un répertoire !"
	echo "Retour au menu principal..."
	sleep 3
elif [ "${SETUPROOT}" = "" ]; then
	echo "Erreur fatale : la racine système n'est pas positionnée !"
	echo "Retour au menu principal..."
	sleep 3
elif [ ! -d ${SETUPROOT} ]; then
	echo "Erreur fatale : le répertoire accueillant la future racine système,"
	echo "'${SETUPROOT}', est introuvable !"
	echo "Ce répertoire devrait normalement exister. Retour au menu principal..."
	sleep 3
else
	if [ "${INSTALLDEBUG}" = "" ]; then
		clear
	fi
	echo -e "\033[1;32mInstallation des paquets.\033[0;0m"
	echo ""
	echo "Les paquets du système 0Linux vont maintenant être installés sur votre"
	echo "partition '$(cat $TMP/partition_racine)'."
	echo ""
	echo -n "Appuyez sur ENTRÉE pour continuer ou CTRL+C pour quitter."
	read BLURB;
	
	# On installe d'abord manuellement (aucune dépendance) les paquets vitaux :
	spackadd --root=${SETUPROOT} ${MEDIACHOISI}/a/base-systeme/*.spack 2>/dev/null
	spackadd --root=${SETUPROOT} ${MEDIACHOISI}/b/glibc/*.spack 2>/dev/null
	spackadd --root=${SETUPROOT} ${MEDIACHOISI}/b/readline/*.spack 2>/dev/null
	spackadd --root=${SETUPROOT} ${MEDIACHOISI}/b/ncurses/*.spack 2>/dev/null
	spackadd --root=${SETUPROOT} ${MEDIACHOISI}/d/bash/*.spack 2>/dev/null
	spackadd --root=${SETUPROOT} ${MEDIACHOISI}/a/sgml-common/*.spack 2>/dev/null
	
	# On installe tout le reste de 'base/' sauf Linux qu'on installera en dernier :
	for paquet in $(find ${MEDIACHOISI}/base -type f \( \
		-name "*.spack" \
		\! -name "base-systeme-*" \
		\! -name "bash-*" \
		\! -name "busybox-*" \
		\! -name "glibc-*" \
		\! -name "linux-*" \
		\! -name "ncurses-*" \
		\! -name "readline-*" \
		\! -name "sgml-*" \) | sort) ; do
			spackadd --root=${SETUPROOT} ${paquet} 2>/dev/null
	done
	
	# On réinstalle 'base-systeme' par sécurité (utilisateurs/groupes possiblement manquants) :
	spackadd -f --root=${SETUPROOT} ${MEDIACHOISI}/base/base-systeme-*.spack 2>/dev/null 1>/dev/null
	
	# On installe tout 'opt/' :
	spackadd --root=${SETUPROOT} ${MEDIACHOISI}/opt/*.spack 2>/dev/null
	
	# On installe tout 'xorg/' :
	spackadd --root=${SETUPROOT} ${MEDIACHOISI}/xorg/*.spack 2>/dev/null
	
	# Linux (appel à 'make' en post-installation, donc de
	# nombreuses dépendances) :
	spackadd --root=${SETUPROOT} ${MEDIACHOISI}/base/linux-*.spack 2>/dev/null

	# On nettoie tous les fichiers '*.0nouveau' :
	for f in $(find ${SETUPROOT}/etc -type f -name "*.0nouveau"); do
		mv ${f} $(dirname ${f})/$(basename ${f} .0nouveau)
	done
fi

# C'est fini.