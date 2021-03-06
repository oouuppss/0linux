#!/usr/bin/env bash

# On nettoie :
rm -f $TMP/choix_media
unset REPONSEREZO REPONSEDEPOT

# Boucle d'affichage du menu :
while [ 0 ]; do
	if [ "${INSTALLDEBUG}" = "" ]; then
		clear
	fi
	echo -e "\033[1;32mInstallation via le réseau.\033[0;0m"
	echo ""
	echo "Une connexion filaire de type Ethernet avec une IP attribuée automatiquement"
	echo "par DHCP a déjà été tentée au démarrage du système."
	echo "Vous pouvez tenter de vous connecter manuellement via un autre"
	echo "terminal à l'aide des commandes 'ifconfig', 'dhcpcd', 'iwconfig', etc. si"
	echo "vous avez une connexion différente."
	echo ""
	echo "Appuyez sur ENTRÉE une fois votre réseau configuré (l'installateur ne testera"
	echo "pas la connexion)."
	read REPONSEREZO;
	
	# Choix du dépôt :
	if [ "${INSTALLDEBUG}" = "" ]; then
		clear
	fi
	echo -e "\033[1;32mChoix du dépôt.\033[0;0m"
	echo ""
	echo "Veuillez choisir un dépôt distant pour télécharger les paquets de 0Linux."
	echo "Les dépôts officiels sont listés ci-dessous."
	echo ""
	echo "Entrez le code du dépôt officiel de 0Linux désiré parmi la liste suivante."
	echo "Vous pouvez également saisir l'URL d'un dépôt personnel hébergé ailleurs."
	echo "Cette URL doit pointer sur le répertoire contenant la version de 0Linux"
	echo "désirée (« eta », « theta », etc.). Il est appelé traditionnellement"
	echo "« paquets » sur les dépôts officiels."
	echo "Appuyez sur ENTRÉE pour ignorer cette étape."
	echo ""
	echo "1 : IGH/CNRS  - http://ftp.igh.cnrs.fr/pub/os/linux/0linux/paquets (recommandé)"
	echo "2 : LIP6      - http://www-ftp.lip6.fr/pub/linux/distributions/0linux/paquets"
	echo "3 : LAYERJET  - http://mirror.layerjet.com/0linux/paquets"
	#echo "4 : REDATOMIK - http://0linux.redatomik.org/paquets"
	echo "5 : MOOO      - http://darknekros.mooo.com/0linux/paquets"
	echo "http://votre/url/paquets"
	echo ""
	echo -n "Votre choix : "
	read REPONSEDEPOT;
	case "$REPONSEDEPOT" in
	"1")
		echo "http://ftp.igh.cnrs.fr/pub/os/linux/0linux/paquets" > $TMP/choix_media
		break
	;;
	"2")
		echo "http://www-ftp.lip6.fr/pub/linux/distributions/0linux/paquets" > $TMP/choix_media
		break
	;;
	"3")
		echo "http://mirror.layerjet.com/0linux/paquets" > $TMP/choix_media
		break
	;;
	"4")
		echo "http://0linux.redatomik.org/paquets" > $TMP/choix_media
		break
	;;
	"5")
		echo "http://darknekros.mooo.com/0linux/paquets" > $TMP/choix_media
		break
	;;
	"")
		break
	;;
	*)
		if [ "$(echo ${REPONSEDEPOT} | grep -E '^ftp:|^http:')" = "" ]; then
			echo "Veuillez entrer une URL valide (« ftp://... » ou « http://... »)."
			sleep 2
			unset REPONSEDEPOT
			continue
		else
			echo "${REPONSEDEPOT}" > $TMP/choix_media
			break
		fi
	esac
done

# C'est fini !
