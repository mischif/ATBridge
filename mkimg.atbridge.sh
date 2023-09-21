################################################################################
##        ______  ______  ____                   __                           ##
##       /\  _  \/\__  _\/\  _`\          __    /\ \                          ##
##       \ \ \L\ \/_/\ \/\ \ \L\ \  _ __ /\_\   \_\ \     __      __          ##
##        \ \  __ \ \ \ \ \ \  _ <'/\`'__\/\ \  /'_` \  /'_ `\  /'__`\        ##
##         \ \ \/\ \ \ \ \ \ \ \L\ \ \ \/ \ \ \/\ \L\ \/\ \L\ \/\  __/        ##
##          \ \_\ \_\ \ \_\ \ \____/\ \_\  \ \_\ \___,_\ \____ \ \____\       ##
##           \/_/\/_/  \/_/  \/___/  \/_/   \/_/\/__,_ /\/___L\ \/____/       ##
##                                                        /\____/             ##
##                                                        \_/__/              ##
##                                                                            ##
##          Proxy SMB shares from modern servers to decrepit clients          ##
##                              (C) 2023 Mischif                              ##
##                           Published under AGPLv3                           ##
################################################################################

atbridge_gen_cmdline() {
	echo "modules=loop,squashfs,sd-mod,usb-storage quiet ${kernel_cmdline}"
}

build_atbridge_blobs() {
	for i in raspberrypi-bootloader-common raspberrypi-bootloader; do
		apk fetch --quiet --stdout "$i" | tar -C "${DESTDIR}" -zx --strip=1 boot/ || return 1
	done
}

atbridge_gen_config() {
	case "${ARCH}" in
	armhf )
		cat <<-ARMHF
			initramfs boot/initramfs-rpi
			kernel=boot/vmlinuz-rpi
			include usercfg.txt
			ARMHF
		;;

	armv7 )
		cat <<-ARMV7
			initramfs boot/initramfs-rpi2
			kernel=boot/vmlinuz-rpi2
			include usercfg.txt
			ARMV7
		;;

	aarch64 )
		cat <<-AARCH64
			[pi4]
			enable_gic=1
			[all]
			arm_64bit=1
			initramfs boot/initramfs-rpi4
			kernel=boot/vmlinuz-rpi4
			include usercfg.txt
			AARCH64
		;;
	esac
	}

atbridge_gen_usercfg() {
	cat <<-USERCFG
		dtoverlay=disable-bt
		dtparam=audio=off
		gpu_mem=16
		USERCFG
	}

build_atbridge_config() {
	atbridge_gen_cmdline > "${DESTDIR}"/cmdline.txt
	atbridge_gen_config > "${DESTDIR}"/config.txt
	atbridge_gen_usercfg > "${DESTDIR}"/usercfg.txt
}

section_atbridge_config() {
	build_section atbridge_config $( (atbridge_gen_cmdline ; atbridge_gen_config ; atbridge_gen_usercfg) | checksum )
	build_section atbridge_blobs
}

profile_atbridge() {
	profile_base
	title="AudioTronBridge"
	desc="SMB proxy for ancient electronics"
	apkovl="genapkovl-atbridge.sh"
	apks="${apks} wpa_supplicant nftables coredns coredns-openrc busybox-extras busybox-extras-openrc samba cifs-utils"
	hostname="atbridge"
	image_ext="tar.gz"
	initfs_features="base squashfs mmc usb kms dhcp https"
	kernel_cmdline="console=tty1"
	case "${ARCH}" in
	armhf )
		arch="armhf"
		kernel_flavors="rpi"
		;;

	armv7 )
		arch="armv7"
		kernel_flavors="rpi2"
		;;

	aarch64 )
		arch="aarch64"
		kernel_flavors="rpi4"
		;;
	esac
	unset grub_mod
}
