#!/usr/bin/env bash

# Configuration de base :
set -e
umask 022

# Le répertoire courant :
CWD=$(pwd)

# Emplacement où on compile et on empaquète :
MARMITE=${MARMITE:-/tmp/0-marmite}

# ...et où on stocke les journaux de compilation :
MARMITELOGS=${MARMITELOGS:-${MARMITE}/logs}

# Emplacement où on stocke les archives sources :
PKGSOURCES=${PKGSOURCES:-${CWD}}

# Emplacement du dépôt des paquets résultant de la construction :
PKGREPO=${PKGREPO:-/usr/local/paquets}

# On crée la marmite :
mkdir -p ${MARMITE}
mkdir -p ${MARMITELOGS}

# Si cette variable n'est pas vide, c'est qu'on appelle d'une recette :
if [ -n "${NAMETGZ}" ]; then
	
	# On crée un journal complet automatiquement en plus des messages à l'écran.
	# Voir http://stackoverflow.com/a/11886837 - c'est en fait loin d'être
	# évident à faire depuis un script.
	rm -f ${MARMITELOGS}/${NAMETGZ}-${VERSION}.log
	exec >  >(tee -a ${MARMITELOGS}/${NAMETGZ}-${VERSION}.log)
	exec 2> >(tee -a ${MARMITELOGS}/${NAMETGZ}-${VERSION}.log >&2)
	
	# On place également un marqueur d'échec, qu'on effacera une fois le script terminé avec succès :
	echo "" > ${MARMITELOGS}/${NAMETGZ}-${VERSION}.log.echec
	
	# On crée le répertoire des archives sources :
	mkdir -p ${PKGSOURCES}/${NAMETGZ}
	
	# Emplacement où on déballe les sources pour les compiler :
	TMP=${TMP:-${MARMITE}/${NAMETGZ}/sources}
	
	# Emplacement des fichiers finaux à empaqueter :
	PKG=${PKG:-${MARMITE}/${NAMETGZ}/paquet}
	
	# On nettoie tout ancien paquet ou sources qui traînent :
	rm -rf   ${PKG} ${TMP}
	mkdir -p ${PKG} ${TMP}
	
	# On définit le compteur de compilations $BUILD en se basant sur l'éventuel
	# paquet déjà installé dans le système. On laisse néanmoins la possibilité de
	# spécifier $BUILD sur la ligne de commande (qui reste prioritaire) :
	if [ -z "${BUILD}" ]; then
		
		# On le définit à 1 par défaut :
		BUILD=1
		
		# On scanne les paquets installés :
		for paquetinstalle in $(find /var/log/packages -type f -name "${NAMETGZ}-*" 2>/dev/null); do
		
			# Si on trouve le même paquet déjà installé avec le même $NAMETGZ :
			if [ "$(echo $(basename ${paquetinstalle}) | sed 's/\(^.*\)-\(.*\)-\(.*\)-\(.*\)$/\1/p' -n)" = "${NAMETGZ}" ]; then
				
				# Si on trouve un paquet avec la même $VERSION, on ajoute 1
				# à son compteur $BUILD pour permettre la mise à niveau :
				if [ "$(echo $(basename ${paquetinstalle}) | sed 's/\(^.*\)-\(.*\)-\(.*\)-\(.*\)$/\2/p' -n)" = "${VERSION}" ]; then
					OLDBUILD="$(echo $(basename ${paquetinstalle}) | sed 's/\(^.*\)-\(.*\)-\(.*\)-\(.*\)$/\4/p' -n)"
					BUILD=$(( ${OLDBUILD} +1 ))
					break
				fi
			fi
			
		done
	fi
	
	# On crée le répertoire de doc pour notre journal et nos dépendances :
	mkdir -p ${PKG}/usr/doc/${NAMETGZ}-${VERSION}/0linux
	
	# On crée un lien générique vers notre répertoire de doc (Xorg en a besoin, notamment) :
	if [ -n "${NAMESRC}" ]; then
		
		# Si $NAMESRC et $NAMETGZ sont différents, on crée un lien $NAMESRC -> $NAMETGZ -> $NAMETGZ-$VERSION :
		if [ ! "${NAMESRC}" = "${NAMETGZ}" ]; then
			ln -sf ${NAMETGZ} ${PKG}/usr/doc/${NAMESRC}
			ln -sf ${NAMETGZ}-${VERSION} ${PKG}/usr/doc/${NAMETGZ}
		
		# Sinon, on crée un simple lien $NAMETGZ -> $NAMETGZ-$VERSION :
		else
			ln -sf ${NAMETGZ}-${VERSION} ${PKG}/usr/doc/${NAMETGZ}
		fi
	fi
	
else
	# Pour tous les autres cas, on appelle les 'fonctions_paquets.sh' depuis un script autre qu'une recette :
	# Emplacement où on compile et on empaquète : :
	TMP=${TMP:-${MARMITE}}
	mkdir -p ${TMP}
fi

telecharger_sources() {
	# Pour tout ce qu'on trouve dans $WGET, que ce soit une variable unique ou un tableau contenant plusieurs URL :
	
	# On télécharge chaque archive source :
	for wgeturl in ${WGET[*]}; do
		
		# On télécharge l'archive source et on retombe sur le FTP de 0linux si le téléchargement se passe mal (fichier
		# inexistant, erreur du serveur, etc.) :
		if [ ! -r ${PKGSOURCES}/${NAMETGZ}/$(basename ${wgeturl}) ]; then
			wget -vc --no-check-certificate ${wgeturl} \
				-O ${PKGSOURCES}/${NAMETGZ}/$(basename ${wgeturl}).part || \
				wget -vc ftp://ftp.igh.cnrs.fr/pub/os/linux/0linux/archives_sources/${NAMETGZ}/$(basename ${wgeturl}) \
					-O ${PKGSOURCES}/${NAMETGZ}/$(basename ${wgeturl}).part
			
			mv ${PKGSOURCES}/${NAMETGZ}/$(basename ${wgeturl}){.part,}
		fi
		
		# On vérifie l'archive téléchargée :
		case $(basename ${wgeturl}) in
			*.tar.*|*.TAR.*|*.tgz|*.TGZ|*.tbz*|*.TBZ*)
				tar ft ${PKGSOURCES}/${NAMETGZ}/$(basename ${wgeturl}) 1>/dev/null 2>/dev/null
			;;
			*.zip|*.ZIP)
				unzip -tq ${PKGSOURCES}/${NAMETGZ}/$(basename ${wgeturl}) 1>/dev/null 2>/dev/null
			;;
			*)
				echo "Format d'archive source non pris en charge. Elle ne sera pas vérifiée."
			;;
		esac
	done
}

preparer_sources() {
	# On peut forcer l'archive à préparer en la spécifiant pour les recettes à versions
	# multiples (ex. : 'preparer_sources $NAMESRC-0.10.1.tar.gz').
	# Agit par défaut sur $WGET ou $WGET[0] (censé valoir <url>/$NAMESRC-$VERSION.$EXT).
	
	# on nettoie si plusieurs archives doivent etre compilées :
	if [ -n "${NAME}" ]; then
		if [ -d $TMP/${NAME} ]; then
			rm -rf $TMP/${NAME}
		fi
	fi
	
	if [ -n "$1" ]; then
		CURRENTARCHIVE="$1"
	else
		# Si $WGET est un tableau contenant plusieurs archives sources à télécharger :
		if [ ${#WGET[*]} -gt 1 ]; then
			
			# On tente de sauver les meubles si $NAMESRC-$VERSION.$EXT existe :
			for wgetline in ${WGET[*]}; do
				if [ "$(basename ${wgetline})" = "$NAMESRC-$VERSION.$EXT" ]; then
					CURRENTARCHIVE="$NAMESRC-$VERSION.$EXT"
					break
				fi
			done
			
			# Si l'on n'a rien trouvé :
			if [ -z ${CURRENTARCHIVE} ]; then
				echo "Erreur : plusieurs archives sources non-standards sont spécifiées dans"
				echo "cette recette. Appelez obligatoirement 'preparer_sources' avec un argument."
				exit 1
			fi
		else
			CURRENTARCHIVE="$(basename ${WGET})"
		fi
	fi
	
	# Cette fonction doit être améliorée pour prendre en charge les autres
	# formats de compressions ainsi que l'absence d'un répertoire principal
	# dans l'archive. Pour le moment, on doit extraire manuellement.
	case ${EXT} in
		tar*|TAR*|tbz*|TBZ*|tgz|TGZ|txz|TXZ)
			NAME=$(tar ft ${PKGSOURCES}/${NAMETGZ}/${CURRENTARCHIVE} | head -n 1 | awk -F/ '{ print $1 }')
		;;
		*)
			echo "Format d'archive source (.${EXT}) non géré pour l'instant, désolé !" && exit 1
		;;
	esac
	
	# On nettoie au maximum :
	if [ -n "${NAME}" -a  "${NAME}" != "." ]; then
		rm -rf ${TMP}/${NAME}
	fi
	
	if [ -n "${NAMESRC}" ]; then
		rm -rf ${TMP}/${NAMESRC}-build
	fi
	
	# On extrait et on se place dans les sources :
	echo "Extraction en cours..."
	case ${EXT} in
		tar*|TAR*|tgz|TGZ|tbz*|TBZ*)
			tar xf ${PKGSOURCES}/${NAMETGZ}/${CURRENTARCHIVE} -C $TMP
		;;
		zip|ZIP)
			unzip ${PKGSOURCES}/${NAMETGZ}/${CURRENTARCHIVE} -d $TMP
		;;
	esac
	
	if [ -n "${NAME}" ]; then
		
		# On définit des permissions correctes pour l'ensemble des sources :
		find ${TMP}/${NAME} \
		\( \
		-perm 777 -o \
		-perm 775 -o \
		-perm 711 -o \
		-perm 555 -o \
		-perm 511 \
		\) \
		-exec chmod 755 {} \; -o \
		\( \
		-perm 666 -o \
		-perm 664 -o \
		-perm 600 -o \
		-perm 444 -o \
		-perm 440 -o \
		-perm 400 \
		\) \
		-exec chmod 644 {} \;
		
		# On se place dans les sources :
		cd ${TMP}/${NAME}
	fi
}

cflags() {
	# On peut forcer l'architecture pour des cas spéciaux (compilation 
	# croisée, etc.) en spécifiant $PKGARCH sur la ligne de commande ou en
	# appelant la fonction dans le script, par exemple : 'cflags i686'.
	if [ "$1" = "i686" -o "$1" = "x86_64" -o "$1" = "arm" ]; then
		PKGARCH="$1"
	else
		PKGARCH="$(uname -m)"
	fi
	
	# Parallélisation : 
	# Avec Hyper Threading : (nombre_de_processeurs * 2) + 1
	# Sans Hyper Threading : nombre_de_processeurs + 1
	# 1 par défaut si un problème survient.
	
	# On compare "processor" et "siblings". S'ils sont égaux, HT n'est pas disponible.
	CPU_LOGIQUES="$(grep -E '^siblings' /proc/cpuinfo | wc -l)"
	CPU_PHYSIQUES="$(grep -E '^processor' /proc/cpuinfo | wc -l)"
	
	if [ ${CPU_LOGIQUES} -eq ${CPU_PHYSIQUES} ]; then
		JOBS=$(( $(nproc) + 1 )) || JOBS=1        # HT indisponible
	else
		JOBS=$(( ($(nproc) * 2) + 1 )) || JOBS=1  # HT disponible
	fi
	
	# Les drapeaux d'optimisation globaux pour chaque architecture. 
	# x86 32 bits :
	if [ ${PKGARCH} = "i686" ]; then
		export CC="gcc -m32"
		export CXX="g++ -m32"
		FLAGS="-m32 -O2 -march=i686 -pipe"
		LIBDIRSUFFIX=""
		USE_ARCH=32 # Utilisé uniquement en multilib
	
	# x86 64 bits :
	elif [ ${PKGARCH} = "x86_64" ]; then
		export CC="gcc -m64"
		export CXX="g++ -m64"
		FLAGS="-O2 -fPIC -pipe"
		LIBDIRSUFFIX="64"
		USE_ARCH=64 # Utilisé uniquement en multilib
	
	# ARM v7-a :
	elif [ ${PKGARCH} = "arm" ]; then
		export CC="gcc"
		export CXX="g++"
		FLAGS="-O2 -march=armv7-a -mfpu=vfpv3-d16 -pipe"
		LIBDIRSUFFIX=""
	
	# Tout le reste :
	else
		export CC="gcc"
		export CXX="g++"
		FLAGS="-O2 -pipe"
		LIBDIRSUFFIX=""
	fi
	
	# Utiles pour la compilation croisée et le multilib :
	export PKG_CONFIG_PATH=/usr/lib${LIBDIRSUFFIX}/pkgconfig
	export LDFLAGS="-L/usr/lib${LIBDIRSUFFIX}"
}

installer_doc() {
	# On peut forcer un répertoire de doc. non standard pour les recettes multiversion
	# Ex. : installer_doc ${NAMETGZ}-${VERSION}/$NAMETGZ-1.2.3
	if [ -n "$1" ]; then
		mkdir -p ${PKG}/usr/doc/${1}
		CURRENTDOC="$1"
	else
		CURRENTDOC="${NAMETGZ}-${VERSION}"
	fi
	cp -a AUTHORS BUGS ?hange?og* *CHANGES* CODING* Contents *COPYING* COPYRIGHT* Copyright* \
		compile EXPAT *FAQ* HACKING *INSTALL* KNOWNBUGS *LEGAL* *LICEN?E* MAINTAIN* *NEWS* \
		*README* THANK* TODO TRANSLATORS *license* *readme* \
		${PKG}/usr/doc/${CURRENTDOC} 2>/dev/null || true
}

creer_post_installation() {
	touch ${PKG}/post-install.sh
	
	# On crée la fonction pour traiter les fichiers '*.0nouveau' éventuels :
	cat >> ${PKG}/post-install.sh << "EOF"
traiter_nouvelle_config() {
	NEW="$1"
	OLD="$(dirname $NEW)/$(basename $NEW .0nouveau)"
	
	if [ ! -r $OLD ]; then
		mv $NEW $OLD
	elif [ "$(diff -abBEiw $OLD $NEW)" = "" ]; then
		mv $NEW $OLD
	fi
}

EOF

	# On ajoute en post-installation tous les fichiers '*.0nouveau' qu'on trouve pour les passer à traiter_nouvelle_config() :
	for fichier_post in $(find ${PKG} -type f -name "*.0nouveau"); do
		echo "traiter_nouvelle_config $(echo ${fichier_post} | sed "s@${PKG}/@@")" >> ${PKG}/post-install.sh
	done
	
	# Si on trouve des bibliothèques, on actualise l'éditeur de liens :
	if [ -d ${PKG}/usr/lib -o -d ${PKG}/usr/lib${LIBDIRSUFFIX} -o -d ${PKG}/lib -o -d ${PKG}/lib${LIBDIRSUFFIX} ]; then
		echo "usr/sbin/ldconfig -r . 2>/dev/null" >> ${PKG}/post-install.sh
	fi
	
	# On ajoute la mise à jour des dépendances des modules si on en trouve :
	if [ -d ${PKG}/lib/modules ]; then
		echo "chroot . depmod -a 2>/dev/null" >> ${PKG}/post-install.sh
	fi
	
	# On réindexe les polices si on en trouve dans le paquet :
	if [ -d ${PKG}/usr/share/fonts -o -d ${PKG}/etc/fonts ]; then
		
		# 'encodings' demande un traitement spécial :
		if [ -d ${PKG}/usr/share/fonts/encodings ]; then
			echo "chroot . mkfontdir -e /usr/share/fonts/encodings -e /usr/share/fonts/encodings/large 1>/dev/null 2>/dev/null" >> ${PKG}/post-install.sh
			echo "chroot . fc-cache -f 2>/dev/null" >> ${PKG}/post-install.sh
		fi
		
		# Pour chaque répertoire trouvé contenant des polices :
		for rep_polices in $(find ${PKG}/usr/share/fonts/* -type d \! -name "encodings" \! -name "util"); do
			echo "chroot . mkfontscale /usr/share/fonts/$(basename ${rep_polices}) 1>/dev/null 2>/dev/null" >> ${PKG}/post-install.sh
			echo "chroot . mkfontdir   /usr/share/fonts/$(basename ${rep_polices}) 1>/dev/null 2>/dev/null" >> ${PKG}/post-install.sh
			echo "chroot . fc-cache -f /usr/share/fonts/$(basename ${rep_polices}) 1>/dev/null 2>/dev/null" >> ${PKG}/post-install.sh
		done
		
		# On ajoute les dépendances :
		EXTRADEPS="${EXTRADEPS} fontconfig mkfontscale mkfontdir"
	fi
	
	# On s'assure que les fichiers dans '/etc/profile.d/' soient exécutés :
	if [ -d ${PKG}/etc/profile.d ]; then
		
		# Pour chaque script rencontré en '.*sh' :
		for fichierprofil in $(find ${PKG}/etc/profile.d -type f -name "*.*sh"); do
			echo "chroot . etc/profile.d/$(basename ${fichierprofil}) >/dev/null 2>&1" >> ${PKG}/post-install.sh
		done
	fi
	
	# On met à jour la base de données des raccourcis bureau et on ajoute la dépendance le cas échéant :
	if [ -d ${PKG}/usr/share/applications ]; then
		echo "chroot . /usr/bin/update-desktop-database &>/dev/null" >> ${PKG}/post-install.sh
		EXTRADEPS="${EXTRADEPS} desktop-file-utils"
	fi
	
	# On met à jour la base des pages 'info' le cas échéant :
	if [ -d ${PKG}/usr/info ]; then
		echo "if [ -x usr/bin/install-info ]; then" >> ${PKG}/post-install.sh
		
		# On installe chaque fichier 'info' rencontré :
		for fichierinfo in $(find ${PKG}/usr/info -type f -name "*.info*"); do
			echo "	chroot . /usr/bin/install-info /usr/info/$(basename ${fichierinfo}) /usr/info/dir 2>/dev/null" >> ${PKG}/post-install.sh
		done
		
		echo "fi" >> ${PKG}/post-install.sh
		echo "" >> ${PKG}/post-install.sh
	fi
	
	# On met à jour la base de données des types MIME et on ajoute la dépendance le cas échéant :
	if [ -d ${PKG}/usr/share/mime ]; then
		echo "chroot . /usr/bin/update-mime-database /usr/share/mime >/dev/null 2>&1" >> ${PKG}/post-install.sh
		EXTRADEPS="${EXTRADEPS} shared-mime-info"
	fi
	
	# On met à jour les modules GIO et on ajoute la dépendance le cas échéant :
	if [ -d ${PKG}/usr/lib${LIBDIRSUFFIX}/gio/modules ]; then
		echo "chroot . /usr/bin/gio-querymodules /usr/lib${LIBDIRSUFFIX}/gio/modules 2>/dev/null" >> ${PKG}/post-install.sh
		EXTRADEPS="${EXTRADEPS} glib"
	fi
	
	# On met à jour cette immonde base de registres GConf et on ajoute la dépendance le cas échéant :
	if [ ! "$(find ${PKG} -type d -name schemas)" = "" ]; then
		echo "chroot . /usr/bin/glib-compile-schemas /usr/share/glib-2.0/schemas/ 1>/dev/null 2>/dev/null" >> ${PKG}/post-install.sh
		EXTRADEPS="${EXTRADEPS} gconf"
	fi
	
	# On met à jour cette immonde base de données DConf et on ajoute la dépendance le cas échéant :
	if [ ! "$(find ${PKG} -type d -name dconf)" = "" ]; then
		echo "chroot . dconf update 1>/dev/null 2>/dev/null" >> ${PKG}/post-install.sh
		EXTRADEPS="${EXTRADEPS} dconf"
	fi
	
	# On met à jour le cache des icônes pour GTK+ et on ajoute la dépendance le cas échéant :
	if [ -d ${PKG}/usr/share/icons ]; then
		echo "chroot . /usr/bin/gtk-update-icon-cache -f -t /usr/share/icons/hicolor >/dev/null 2>&1" >> ${PKG}/post-install.sh
		EXTRADEPS="${EXTRADEPS} gtk+"
	fi
	
	# On met à jour les ressources des icônes pour le thème 'hicolor' parfois fourni par plusieurs paquets et on ajoute la dépendance le cas échéant :
	if [ -d ${PKG}/usr/share/icons ]; then
		echo "chroot . /usr/bin/xdg-icon-resource forceupdate --theme hicolor >/dev/null 2>&1" >> ${PKG}/post-install.sh
		EXTRADEPS="${EXTRADEPS} xdg-utils"
	fi
}

stripper() {
	# On "strippe" tout ce qu'on trouve :
	find ${PKG} -type f | xargs file 2>/dev/null | grep "LSB executable"     | cut -f 1 -d : | xargs strip --strip-unneeded 2>/dev/null || true
	find ${PKG} -type f | xargs file 2>/dev/null | grep "shared object"      | cut -f 1 -d : | xargs strip --strip-unneeded 2>/dev/null || true
	find ${PKG} -type f | xargs file 2>/dev/null | grep "current ar archive" | cut -f 1 -d : | xargs strip -g               2>/dev/null || true
}

empaqueter() {
	# On peut passer des options à 'spackpkg' via par exemple :
	# empaqueter -p -z
	
	# On déplace '/usr/share/pkgconfig' sous '/usr/lib${LIBDIRSUFFIX}' le
	# cas échéant... :
	if [ -d ${PKG}/usr/share/pkgconfig ]; then
		mkdir -p ${PKG}/usr/lib${LIBDIRSUFFIX}/pkgconfig
		cp -ar ${PKG}/usr/share/pkgconfig/* ${PKG}/usr/lib${LIBDIRSUFFIX}/pkgconfig/
		rm -rf ${PKG}/usr/share/pkgconfig
	fi
	
	# On corrige les chemins contenant '/lib' codés en dur dans les fichiers pour 'pkg-config' (et ils sont nombreux) :
	if [ ! "${LIBDIRSUFFIX}" = "" ]; then
		grep -E -r -l '/lib$' ${PKG}/usr/lib${LIBDIRSUFFIX}/pkgconfig/*.pc 2>/dev/null | while read fichier ; do
			sed -i "s@/lib@/lib${LIBDIRSUFFIX}@g" $fichier
		done
	fi
	
	# On affecte des permissions correctes aux bibliothèques partagées :
	find ${PKG}/lib* ${PKG}/usr/lib* -type f \! -perm 755 -iname "*.so*" 2>/dev/null | xargs file 2>/dev/null | grep "shared object" | cut -f 1 -d : | xargs chmod 755 2>/dev/null || true
	
	# On affecte des permissions correctes aux bibliothèques statiques :
	find ${PKG}/lib* ${PKG}/usr/lib* -type f \! -perm 644 -iname "*.a" -exec chmod 644 {} \; 2>/dev/null || true
	
	# On affecte des permissions aux raccourcis de type '*.desktop' :
	find ${PKG}/usr -type f \! -perm 644 -name "*.desktop" -exec chmod 644 {} \; 2>/dev/null || true
	
	# On affecte la permission à ce répertoire spécial pour 'polkit' :
	if [ -d ${PKG}/etc/polkit-1/localauthority ]; then
		chmod 700 ${PKG}/etc/polkit-1/localauthority
	fi
	
	# On déplace toute doc éventuellement mal placée :
	if [ -d ${PKG}/usr/share/doc ]; then
		cp -ar ${PKG}/usr/share/doc ${PKG}/usr/doc/${NAMETGZ}-${VERSION}/
		rm -rf ${PKG}/usr/share/doc
	fi
	
	# On vérifie les droits de la doc, souvent problématiques :
	find ${PKG}/usr/{doc,man,info} -type d -exec chmod 755 {} \; 2> /dev/null || true
	find ${PKG}/usr/{doc,man,info} -type f -exec chmod 644 {} \; 2> /dev/null || true
	
	# On rend les fichiers profils exécutables :
	find ${PKG}/etc/profile.d -type f -exec chmod 755 {} \; 2>/dev/null || true
	
	# On déplace les fichiers '*-gdb.py' sous une arborescence dédiée à 'gdb', 
	# sinon 'ldconfig' va se plaindre :
	for fichiergdb in $(find ${PKG}/usr/lib* -type f -name "*-gdb.py" 2>/dev/null); do
		mkdir -p ${PKG}/usr/share/gdb/auto-load/$($(echo dirname ${fichiergdb}) | sed "s@${PKG}@@")
		cp -a ${fichiergdb} ${PKG}/usr/share/gdb/auto-load/$($(echo dirname ${fichiergdb}) | sed "s@${PKG}@@")/
		rm -f ${fichiergdb}
	done
	
	# On nettoie ce fichier indésirables des modules Perl :
	if [ ! "${NAMETGZ}" = "perl" ]; then
		find ${PKG} -type f -name "perllocal.pod" -delete 2>/dev/null || true
	fi
	
	# On déduit l'emplacement du paquet selon l'emplacement de la recette elle-même :
	PKGBASEDIR="$(echo ${CWD} | sed 's/^.*0Linux\/\(.*$\)/\1/p' -n)"
	
	# On déduit le répertoire cible du paquet  :
	OUT="${PKGREPO}/${PKGARCH}/${PKGBASEDIR}"
	
	# On nettoie tout paquet/fichier .dep similaire présent dans le dépôt sur l'hôte :
	for paquetpresent in $(find ${PKGREPO}/${PKGARCH} -type f -name "${NAMETGZ}-*.spack" 2>/dev/null); do
		
		# On compare bien le nom du paquet qui doit strictement être "$NAMETGZ" et pas "$NAMETGZ-doc" par exemple :
		if [ "$(echo $(basename ${paquetpresent}) | sed 's/\(^.*\)-\(.*\)-\(.*\)-\(.*\)\.spack$/\1/p' -n)" = "${NAMETGZ}" ]; then
			
			# OK on nettoie le '.spack' et le '.dep' :
			rm -f ${paquetpresent}
			rm -f $(echo ${paquetpresent} | sed 's@\.spack@\.dep@')
			
			# Si le paquet est dans un répertoire dédié (cas normal dans 0Linux eta), 
			# alors on le supprime également pour nettoyer les renommages et autres 
			# déplacements de paquets :
			if [ "$(basename $(dirname ${paquetpresent}))" = "${NAMETGZ}" ]; then
				rm -rf $(dirname ${paquetpresent})
			fi
		fi
	done
	
	# On extrait les dépendances dynamiques (fichiers) grâce à '0ldd_clean', basé sur '0dep' :
	mkdir -p ${PKG}/usr/doc/${NAMETGZ}-${VERSION}/0linux
	0ldd_clean ${PKG}/* > ${PKG}/usr/doc/${NAMETGZ}-${VERSION}/0linux/ldd.log
	
	# On extrait les dépendances (paquets) grâce à '0dep' (merci Seb) :
	mkdir -p ${OUT}
	0dep ${PKG} > ${OUT}/${NAMETGZ}-${VERSION}-${PKGARCH}-${BUILD}.dep
	
	# On ajoute les dépendances spécifiées manuellement le cas échéant et on trie :
	if [ -n "${EXTRADEPS}" ]; then
		
		# On copie une version tampon des dépendances :
		cp -a ${OUT}/${NAMETGZ}-${VERSION}-${PKGARCH}-${BUILD}.dep{,.tmp}
		
		# On ajoute chaque dépendances manuelle à ce tampon :
		for extradep in ${EXTRADEPS}; do
			echo "${extradep}" >> ${OUT}/${NAMETGZ}-${VERSION}-${PKGARCH}-${BUILD}.dep.tmp
		done
		
		# On trie, on supprime les lignes vides, on copie dans le fichier original et on nettoie :
		cat ${OUT}/${NAMETGZ}-${VERSION}-${PKGARCH}-${BUILD}.dep.tmp | sed '/^$/d' | sort -u > ${OUT}/${NAMETGZ}-${VERSION}-${PKGARCH}-${BUILD}.dep
		rm -f cat ${OUT}/${NAMETGZ}-${VERSION}-${PKGARCH}-${BUILD}.dep.tmp
	fi
	
	# On stocke également les dépendances dans la doc 0linux :
	cp -a ${OUT}/${NAMETGZ}-${VERSION}-${PKGARCH}-${BUILD}.dep ${PKG}/usr/doc/${NAMETGZ}-${VERSION}/0linux/
	
	# On place le journal dans la doc sous forme compressée :
	if [ -r ${MARMITELOGS}/${NAMETGZ}-${VERSION}.log ]; then
		cp ${MARMITELOGS}/${NAMETGZ}-${VERSION}.log ${PKG}/usr/doc/${NAMETGZ}-${VERSION}/0linux/
		xz ${PKG}/usr/doc/${NAMETGZ}-${VERSION}/0linux/${NAMETGZ}-${VERSION}.log
		rm -f ${MARMITELOGS}/${NAMETGZ}-${VERSION}.log
	fi
	
	# On décompresse et on recompresse en 'xz' tous les manuels :
	if [ -d ${PKG}/usr/man ]; then
		find ${PKG}/usr/man -type f -name "*.gz"  -exec gzip  -d {} \;
		find ${PKG}/usr/man -type f -name "*.bz2" -exec bzip2 -d {} \;
		find ${PKG}/usr/man -type f -name "*.*"   -exec xz       {} \;
		for manpage in $(find ${PKG}/usr/man -type l) ; do
			ln -s $(readlink $manpage).xz ${manpage}.xz
			rm -f ${manpage}
		done
	fi
	
	# On compresse toutes les pages 'info' et on nettoie le fichier 'dir' forcément incorrect :
	if [ -d ${PKG}/usr/info ]; then
		rm -f ${PKG}/usr/info/dir
		find ${PKG}/usr/info -type f -name "*.info*" -exec xz {} \;
	fi
	
	# On décompresse et on recompresse en 'xz' tous les modules noyau (et on tire la
	# langue au mainteneur de 'kmod' qui voulait supprimer la prise en charge de 'xz') :
	if [ -d ${PKG}/lib/modules ]; then
		find ${PKG}/lib/modules -type f -name "*.ko.gz"  -exec gzip  -d {} \;
		find ${PKG}/lib/modules -type f -name "*.ko.bz2" -exec bzip2 -d {} \;
		find ${PKG}/lib/modules -type f -name "*.ko"     -exec xz       {} \;
	fi
	
	# On place la description en la créant via 'spackdesc -' :
	echo "${DESC}" | spackdesc --package="${NAMETGZ}" - > ${PKG}/about.txt
	
	# Paquet créé avec succès à ce stade, on supprime le marqueur d'échec :
	if [ -n "${NAMETGZ}" ]; then
		rm -f ${MARMITELOGS}/${NAMETGZ}-${VERSION}.log.echec
	fi
	
	# Empaquetage !
	cd ${PKG}
	fakeroot chown root:root . -R
	fakeroot /usr/sbin/spackpkg . ${OUT}/${NAMETGZ}-${VERSION}-${PKGARCH}-${BUILD} $@
	
	# On nettoie :
	rm -rf ${MARMITE}/${NAMETGZ}
	
	if [ -n "${NAME}" ]; then
		if [ -d $TMP/${NAME} ]; then
			rm -rf $TMP/${NAME}
		fi
	fi
}

# C'est fini.
