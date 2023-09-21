#!/usr/bin/env sh

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

CONFIGS="${ATBDIR}/configs"
tmp="$(mktemp -d)"

HOSTNAME="$1"
if [ -z "$HOSTNAME" ]; then
	echo "usage: $0 hostname"
	exit 1
fi

cleanup() {
	rm -rf "$tmp"
	}

makefile() {
	OWNER="$1"
	PERMS="$2"
	FILENAME="$3"
	cat > "$FILENAME"
	chown "$OWNER" "$FILENAME"
	chmod "$PERMS" "$FILENAME"
	}

rc_add() {
	mkdir -p "$tmp"/etc/runlevels/"$2"
	ln -sf /etc/init.d/"$1" "$tmp"/etc/runlevels/"$2"/"$1"
	}

trap cleanup EXIT

mkdir -p "$tmp"/etc
makefile root:root 0644 "$tmp"/etc/hostname <<EOF
$HOSTNAME
EOF

cat "${CONFIGS}/udhcpd.conf" | makefile root:root 0644 "$tmp"/etc/udhcpd.conf

cat "${CONFIGS}/firewall.nft" | makefile root:root 0644 "$tmp"/etc/firewall.nft

mkdir -p "$tmp"/etc/conf.d
cat "${CONFIGS}/nftables.conf" | makefile root:root 0644 "$tmp"/etc/conf.d/nftables

mkdir -p "$tmp"/etc/apk
cat "${CONFIGS}/atbridge-world.conf" | makefile root:root 0644 "$tmp"/etc/apk/world

mkdir -p "$tmp"/etc/network
cat "${CONFIGS}/interfaces.conf" | makefile root:root 0644 "$tmp"/etc/network/interfaces

mkdir -p "$tmp"/etc/sysctl.d
cat "${CONFIGS}/sysctl.conf" | makefile root:root 0644 "$tmp"/etc/sysctl.d/01-atbridge.conf

mkdir -p "$tmp"/etc/coredns
cat "${CONFIGS}/coredns.conf" | makefile root:root 0644 "$tmp"/etc/coredns/Corefile

mkdir -p "$tmp"/etc/samba
cat "${CONFIGS}/smb.conf" | makefile root:root 0644 "$tmp"/etc/samba/smb.conf

if [ -e "${CONFIGS}/wireless.conf" ] ; then
	mkdir -p "$tmp"/etc/wpa_supplicant
	cat "${CONFIGS}/wireless.conf" | makefile root:root 0644 "$tmp"/etc/wpa_supplicant/wpa_supplicant.conf
	rc_add wpa_supplicant boot
fi

if [ -e "${CONFIGS}/smb.creds" ] ; then
	mkdir -p "$tmp"/root
	for CRED in $(cat "${CONFIGS}/smb.creds"); do
		IFS="\\" read -r SERVER SHARE USER PASS WORKGROUP <<- EOF
		${CRED}
		EOF
		unset CRED_FSTAB

		UP_MNT="mnt/${SHARE}"
		DOWN_MNT="mnt/downstream/${SHARE}"
		DOWN_LINK="/${DOWN_MNT}/Music"

		mkdir -p "$tmp"/${UP_MNT}
		mkdir -p "$tmp"/${DOWN_MNT}
		ln -s /${UP_MNT} "$tmp"${DOWN_LINK}
		chown -Rh nobody:nogroup "$tmp"/${DOWN_MNT}

		if [ -n "${USER}" ] ; then
			CRED_FILE="root/${SHARE}.smb-credentials"
			CRED_PATH="$tmp/${CRED_FILE}"
			CRED_FSTAB=",credentials=/${CRED_FILE}"


			cat <<- EOF | makefile root:root 0600 "$tmp"/${CRED_FILE}
				username=${USER}
				password=${PASS}
				domain=${WORKGROUP:-WORKGROUP}
				EOF
		fi

		cat <<- EOF >> "$tmp"/etc/samba/smb.conf
			[${SHARE}]
			    path = /${DOWN_MNT}
			    public = yes
			    guest only = yes
			    writable = no
			    browseable = yes

			EOF

		cat <<- EOF >> "$tmp"/etc/fstab
			//${SERVER}/${SHARE} /${UP_MNT} cifs uid=nobody,gid=nogroup,iocharset=utf8,noperm${CRED_FSTAB} 0 0
			EOF

		done
	rc_add netmount boot
fi

rc_add devfs sysinit
rc_add dmesg sysinit
rc_add mdev sysinit
rc_add hwdrivers sysinit
rc_add modloop sysinit

rc_add swclock boot
rc_add modules boot
rc_add sysctl boot
rc_add hostname boot
rc_add bootmisc boot
rc_add syslog boot
rc_add networking boot

rc_add nftables default
rc_add udhcpd default
rc_add coredns default
rc_add samba default

rc_add mount-ro shutdown
rc_add killprocs shutdown
rc_add savecache shutdown

tar c -C "$tmp" etc mnt root  | gzip -9n > $HOSTNAME.apkovl.tar.gz
