#!/usr/bin/env sh
set -eu

if [ $(whoami) != "root" ] ; then
	echo "You must be root to run this script"
	exit 1
fi

clear
echo '
################################################################################
##        ______  ______  ____                   __                           ##
##       /\  _  \/\__  _\/\  _`\          __    /\ \                          ##
##       \ \ \L\ \/_/\ \/\ \ \L\ \  _ __ /\_\   \_\ \     __      __          ##
##        \ \  __ \ \ \ \ \ \  _ < /\` __\/\ \  / _` \  / _ `\  / __`\        ##
##         \ \ \/\ \ \ \ \ \ \ \L\ \ \ \/ \ \ \/\ \L\ \/\ \L\ \/\  __/        ##
##          \ \_\ \_\ \ \_\ \ \____/\ \_\  \ \_\ \___,_\ \____ \ \____\       ##
##           \/_/\/_/  \/_/  \/___/  \/_/   \/_/\/__,_ /\/___L\ \/____/       ##
##                                                        /\____/             ##
##                                                        \_/__/              ##
##                                                                            ##
################################################################################
'
ATBDIR="$( cd "$( dirname "$0" )" && pwd)"
SHAREDDIR="$( dirname ${ATBDIR} )"

ARCH=""
MODEL=0

cleanup() {
	set +e

	rm -f "${ATBDIR}/${ARCH}_stage_2_success"

	if [ -e "/alpine" ] ; then
		/alpine/destroy --remove
	fi

	if [ -e ${SHAREDDIR}/atbridge-${ARCH}.tar.gz ] ; then
		rm -rf "${ATBDIR}/aports"
		rm -f "${ATBDIR}/${ARCH}_stage_1_success"
	fi

	exit
	}

stage_0() {
################################################################################
##                                                                            ##
##                   What is being turned into an ATBridge?                   ##
##                                                                            ##
################################################################################

	echo "Supported architectures:"
	echo "1) ARMv6 (Raspberry Pi 1/Zero W)"
	echo "2) ARMv7 (Raspberry Pi 2 v1)"
	echo "3) ARMv8 (Raspberry Pi 2 v1.2 and later/Zero 2 W)"
	while true; do
		read -p "Build ATBridge for which architecture? " MODEL
		case ${MODEL} in
			1 )
				ARCH="armhf"
				break
				;;

			2 )
				ARCH="armv7"
				break
				;;

			3 )
				ARCH="aarch64"
				break
				;;

			* )
				echo "Please choose a supported architecture"
				;;
		esac
	done

	if [ ${ARCH} != "" ] ; then
		return 0
	else
		echo "There was an issue choosing an architecture"
		return 1
	fi
	}

stage_1() {
################################################################################
##                                                                            ##
##                Collect files and tools to run image builder                ##
##                                                                            ##
################################################################################

	if [ -e "${ATBDIR}/${ARCH}_stage_1_success" ] ; then return 0; fi

	echo "Installing image builder packages"
	apk -q add "qemu-${ARCH}" qemu-openrc git

	if [ $($(service qemu-binfmt status >/dev/null); echo $?) == 3 ] ; then
		echo "Starting qemu-binfmt"
		service qemu-binfmt start
	fi

	if [ -d "${ATBDIR}/aports" ] ; then
		echo "aports already downloaded; skipping"
	else
		echo "Downloading aports"
		git clone -q --depth 1 --single-branch -b master \
		https://gitlab.alpinelinux.org/alpine/aports.git "${ATBDIR}/aports"

		echo "Adding ATBridge scripts to aports"
		cp "${ATBDIR}/genapkovl-atbridge.sh" "${ATBDIR}/aports/scripts"
		cp "${ATBDIR}/mkimg.atbridge.sh" "${ATBDIR}/aports/scripts"
		chmod +x "${ATBDIR}"/aports/scripts/*atbridge.sh
	fi

	if [ -e "${SHAREDDIR}/wireless.conf" ] ; then
		echo "Copying wifi config"
		cp "${SHAREDDIR}/wireless.conf" "${ATBDIR}/configs"
	fi

	if [ -e "${SHAREDDIR}/smb.creds" ] ; then
		echo "Copying SMB share credentials"
		cp "${SHAREDDIR}/smb.creds" "${ATBDIR}/configs"
	fi

	if [ -e "${ATBDIR}/alpine-chroot-install" ] ; then
		echo "alpine-chroot-install already downloaded; skipping"

	else
		echo "Downloading alpine-chroot-install"
		wget -P ${ATBDIR} "https://raw.githubusercontent.com/alpinelinux/alpine-chroot-install/master/alpine-chroot-install"
		sed -i 's/arch-static/arch/' "${ATBDIR}/alpine-chroot-install"
		chmod +x "${ATBDIR}/alpine-chroot-install"
	fi

	if [ $? == 0 ] ; then
		touch "${ATBDIR}/${ARCH}_stage_1_success"
		return 0
	else
		echo "There was an issue downloading the necessary utilities"
		return 1
	fi
	}

stage_2() {
################################################################################
##                                                                            ##
##                      Create chroot for building image                      ##
##                                                                            ##
################################################################################

	if [ -e "${ATBDIR}/${ARCH}_stage_2_success" ] ; then return 0; fi

	if [ -e "/alpine" ] ; then
		echo "Chroot already exists; skipping"
	else
		echo "Creating ${ARCH} chroot"
		"${ATBDIR}/alpine-chroot-install" \
		-a ${ARCH} -b edge -i ${SHAREDDIR} -k "ATBDIR" \
		-p "alpine-sdk build-base apk-tools alpine-conf busybox mkinitfs xorriso squashfs-tools sudo"
	fi

	if [ $? == 0 ] ; then
		touch "${ATBDIR}/${ARCH}_stage_2_success"
		return 0
	else
		echo "There was an issue creating the chroot"
		return 1
	fi
	}

stage_3() {
################################################################################
##                                                                            ##
##                        Enter chroot and build image                        ##
##                                                                            ##
################################################################################

	if [ -e "${SHAREDDIR}/atbridge-${ARCH}.tar.gz" ] ; then return 0; fi

	echo "Building image"
	export ATBDIR="${ATBDIR}"
	/alpine/enter-chroot abuild-keygen -i -a -n
	/alpine/enter-chroot "${ATBDIR}/aports/scripts/mkimage.sh" \
	--tag edge --profile atbridge --outdir "${SHAREDDIR}" \
	--repository http://dl-cdn.alpinelinux.org/alpine/edge/main \
	--extra-repository http://dl-cdn.alpinelinux.org/alpine/edge/community

	if [ -e "${SHAREDDIR}/alpine-atbridge-edge-${ARCH}.tar.gz" ] ; then
		mv "${SHAREDDIR}/alpine-atbridge-edge-${ARCH}.tar.gz" "${SHAREDDIR}/atbridge-${ARCH}.tar.gz"
		echo "Done"
		return 0
	else
		echo "There was an issue building the ATBridge image"
		return 1
	fi
	}


# The script should clean up after itself
trap cleanup 1 SIGINT SIGTERM EXIT

# Get basic details
stage_0

# Download everything outside the image builder
if [ $? == 0 ] ; then
	stage_1
else
	exit
fi

# Prep the image builder chroot
if [ $? == 0 ] ; then
	stage_2
else
	exit
fi

# Enter the chroot and build the ATBridge image
if [ $? == 0 ] ; then
	stage_3
else
	exit
fi

# Confirm the ATBridge image built correctly
if [ $? == 0 ] ; then
	exit 0
else
	exit 1
fi
