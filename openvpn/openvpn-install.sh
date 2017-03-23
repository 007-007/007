#!/bin/bash
# OpenVPN road warrior installer for Debian, Ubuntu and CentOS

# This script will work on Debian, Ubuntu, CentOS and probably other distros
# of the same families, although no support is offered for them. It isn't
# bulletproof but it will probably work if you simply want to setup a VPN on
# your Debian/Ubuntu/CentOS box. It has been designed to be as unobtrusive and
# universal as possible.


if [[ "$EUID" -ne 0 ]]; then
	echo "Maaf, Anda harus menjalankan ini sebagai root"
	exit 1
fi


if [[ ! -e /dev/net/tun ]]; then
	echo "TUN is not available"
	exit 2
fi


if grep -qs "CentOS release 5" "/etc/redhat-release"; then
	echo "CentOS 5 is too old and not supported"
	exit 3
fi

if [[ -e /etc/debian_version ]]; then
	OS="debian"
	#We get the version number, to verify we can get a recent version of OpenVPN
	VERSION_ID=$(cat /etc/*-release | grep "VERSION_ID")
	RCLOCAL='/etc/rc.local'
	if [[ "$VERSION_ID" != 'VERSION_ID="7"' ]] && [[ "$VERSION_ID" != 'VERSION_ID="8"' ]] && [[ "$VERSION_ID" != 'VERSION_ID="12.04"' ]] && [[ "$VERSION_ID" != 'VERSION_ID="14.04"' ]] && [[ "$VERSION_ID" != 'VERSION_ID="16.04"' ]] && [[ "$VERSION_ID" != 'VERSION_ID="16.10"' ]]; then
		echo "Your version of Debian/Ubuntu is not supported. Please look at the documentation."
		exit 4
	fi
elif [[ -e /etc/centos-release || -e /etc/redhat-release ]]; then
	OS=centos
	RCLOCAL='/etc/rc.d/rc.local'
	# Needed for CentOS 7
	chmod +x /etc/rc.d/rc.local
else
	echo "Sepertinya Anda tidak menjalankan installer ini pada sistem Debian, Ubuntu atau CentOS"
	exit 4
fi

newclient () {
	# Menghasilkan client.ovpn kustom
	cp /etc/openvpn/client-common.txt ~/$1.ovpn
	echo "<ca>" >> ~/$1.ovpn
	cat /etc/openvpn/easy-rsa/pki/ca.crt >> ~/$1.ovpn
	echo "</ca>" >> ~/$1.ovpn
	echo "<cert>" >> ~/$1.ovpn
	cat /etc/openvpn/easy-rsa/pki/issued/$1.crt >> ~/$1.ovpn
	echo "</cert>" >> ~/$1.ovpn
	echo "<key>" >> ~/$1.ovpn
	cat /etc/openvpn/easy-rsa/pki/private/$1.key >> ~/$1.ovpn
	echo "</key>" >> ~/$1.ovpn
	echo "key-direction 1" >> ~/$1.ovpn
	echo "<tls-auth>" >> ~/$1.ovpn
	cat /etc/openvpn/tls-auth.key >> ~/$1.ovpn
	echo "</tls-auth>" >> ~/$1.ovpn
}


# Try to get our IP from the system and fallback to the Internet.
# I do this to make the script compatible with NATed servers (LowEndSpirit/Scaleway)
# and to avoid getting an IPv6.
IP=$(ip addr | grep 'inet' | grep -v inet6 | grep -vE '127\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | grep -o -E '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | head -1)
if [[ "$IP" = "" ]]; then
	IP=$(wget -qO- ipv4.icanhazip.com)
fi


if [[ -e /etc/openvpn/server.conf ]]; then
	while :
	do
	clear
		echo "Sepertinya OpenVPN sudah diinstal?"
		echo ""
		echo "Apa yang ingin kamu lakukan? hahaha kasian dech lo! hapus dulu OpenVpn yg sdh terinstal"
		echo "   1) Hapus OpenVPN"
		echo "   2) Exit"
		read -p "Pilih option [1-2]: " option
		case $option in
			1)
			echo ""
			read -p "Apakah Anda benar-benar ingin menghapus OpenVPN? [y/n]: " -e -i y REMOVE
			if [[ "$REMOVE" = 'y' ]]; then
				PORT=$(grep '^port ' /etc/openvpn/server.conf | cut -d " " -f 2)
				if hash ufw 2>/dev/null && ufw status | grep -qw active; then
					ufw delete allow $PORT/udp
					sed -i '/^##OPENVPN_START/,/^##OPENVPN_END/d' /etc/ufw/before.rules
					sed -i '/^DEFAULT_FORWARD/{N;s/DEFAULT_FORWARD_POLICY="ACCEPT"\n#before openvpn: /DEFAULT_FORWARD_POLICY=/}' /etc/default/ufw
				elif pgrep firewalld; then
					# Using both permanent and not permanent rules to avoid a firewalld reload.
					firewall-cmd --zone=public --remove-port=$PORT/udp
					firewall-cmd --zone=trusted --remove-source=10.8.0.0/24
					firewall-cmd --permanent --zone=public --remove-port=$PORT/udp
					firewall-cmd --permanent --zone=trusted --remove-source=10.8.0.0/24
					firewall-cmd --zone=trusted --remove-masquerade
					firewall-cmd --permanent --zone=trusted --remove-masquerade
				fi
				if iptables -L -n | grep -qE 'REJECT|DROP'; then
					sed -i "/iptables -I INPUT -p udp --dport $PORT -j ACCEPT/d" $RCLOCAL
					sed -i "/iptables -I FORWARD -s 10.8.0.0\/24 -j ACCEPT/d" $RCLOCAL
					sed -i "/iptables -I FORWARD -m state --state RELATED,ESTABLISHED -j ACCEPT/d" $RCLOCAL
				fi
				sed -i '/iptables -t nat -A POSTROUTING -s 10.8.0.0\/24 /d' $RCLOCAL
				if hash sestatus 2>/dev/null; then
					if sestatus | grep "Current mode" | grep -qs "enforcing"; then
						if [[ "$PORT" != '1194' ]]; then
							semanage port -d -t openvpn_port_t -p udp $PORT
						fi
					fi
				fi
				if [[ "$OS" = 'debian' ]]; then
					apt-get remove --purge -y openvpn openvpn-blacklist
				else
					yum remove openvpn -y
				fi
				rm -rf /etc/openvpn
				rm -rf /usr/share/doc/openvpn*
				echo ""
				echo "OpenVPN terhapus!"
			else
				echo ""
				echo "Removal aborted!"
			fi
			exit
			;;
			2) exit;;
		esac
	done
else
	clear
	echo 'Selamat Datang di Elang Overdosis OpenVPN "road warrior" installer'
	echo ""
	# OpenVPN setup and first user creation
	echo "Saya perlu mengajukan beberapa pertanyaan sebelum memulai setup"
	echo "Anda dapat meninggalkan pilihan default dan hanya tekan enter jika Anda tidak ingin memilih"
	echo ""
	echo "Pertama, memilih varian dari script yang ingin Anda gunakan."
	echo "Fast(cepat) adalah aman, tetapi Slow(lambat) adalah enkripsi terbaik Anda bisa dapatkan, pada biaya kecepatan (meskipun tidak terlalu lambat) '
	echo "   1) Fast (2048 bits RSA and DH, 128 bits AES)"
	echo "   2) Slow (4096 bits RSA and DH, 256 bits AES)"
	while [[ $VARIANT !=  "1" && $VARIANT != "2" ]]; do
		read -p "Variant [1-2]: " -e -i 1 VARIANT
	done

	echo ""
	echo "Saya perlu tahu alamat IPv4 dari interface jaringan yang ingin listening OpenVPN."
	echo "Jika server Anda berjalan di belakang NAT, (mis LowEndSpirit, Scaleway) meninggalkan alamat IP sebagaimana adanya. (local/private IP"
	echo "Jika tidak, itu PERSEDIAAN menjadi alamat IPv4 publik Anda."
	read -p "IP address: " -e -i $IP IP
	echo ""
	echo "Port apa yang Anda inginkan untuk OpenVPN?"
	read -p "Port: " -e -i 1194 PORT
	echo ""
	echo "DNS apa yang Anda ingin gunakan dengan VPN?"
	echo "   1) Current system resolvers"
	echo "   2) OpenDNS"
	echo "   3) Google"
	read -p "DNS [1-3]: " -e -i 2 DNS
	echo ""
	echo "Beberapa setup (mis: Amazon Web Services),memerlukan penggunaan MASQUERADE daripada SNAT"
echo" Metode mana forwarding yang Anda ingin menggunakan [jika tidak yakin, meninggalkan sebagai default]?"
	echo "   1) SNAT (default)"
	echo "   2) MASQUERADE"
	while [[ $FORWARD_TYPE !=  "1" && $FORWARD_TYPE != "2" ]]; do
		read -p "Forwarding type: " -e -i 1 FORWARD_TYPE
	done
	echo ""
	echo "Akhirnya, saya kirim nama Anda untuk cert klien"
	while [[ $CLIENT = "" ]]; do
		echo "Silakan, gunakan satu kata saja, tidak ada karakter khusus"
		read -p "Nama client: " -e -i client CLIENT
	done
	echo ""
	echo "Oke, itu semua saya butuhkan. Kami siap untuk setup OpenVPN server Anda sekarang"
	read -n1 -r -p "Press any key to continue..."
	if [[ "$OS" = 'debian' ]]; then
		apt-get install ca-certificates -y
		# We add the OpenVPN repo to get the latest version.
		# Debian 7
		if [[ "$VERSION_ID" = 'VERSION_ID="7"' ]]; then
			echo "deb http://swupdate.openvpn.net/apt wheezy main" > /etc/apt/sources.list.d/swupdate-openvpn.list
			wget -O - https://swupdate.openvpn.net/repos/repo-public.gpg | apt-key add -
			apt-get update
		fi
		# Debian 8
		if [[ "$VERSION_ID" = 'VERSION_ID="8"' ]]; then
			echo "deb http://swupdate.openvpn.net/apt jessie main" > /etc/apt/sources.list.d/swupdate-openvpn.list
			wget -O - https://swupdate.openvpn.net/repos/repo-public.gpg | apt-key add -
			apt update
		fi
		# Ubuntu 12.04
		if [[ "$VERSION_ID" = 'VERSION_ID="12.04"' ]]; then
			echo "deb http://swupdate.openvpn.net/apt precise main" > /etc/apt/sources.list.d/swupdate-openvpn.list
			wget -O - https://swupdate.openvpn.net/repos/repo-public.gpg | apt-key add -
			apt-get update
		fi
		# Ubuntu 14.04
		if [[ "$VERSION_ID" = 'VERSION_ID="14.04"' ]]; then
			echo "deb http://swupdate.openvpn.net/apt trusty main" > /etc/apt/sources.list.d/swupdate-openvpn.list
			wget -O - https://swupdate.openvpn.net/repos/repo-public.gpg | apt-key add -
			apt-get update
		fi
		# The repo, is not available for Ubuntu 15.10 and 16.04, but it has OpenVPN > 2.3.3, so we do nothing.
		# The we install OpnVPN
		apt-get install openvpn iptables openssl wget ca-certificates curl -y
	else
		# Else, the distro is CentOS
		yum install epel-release -y
		yum install openvpn iptables openssl wget ca-certificates curl -y
	fi
	# find out if the machine uses nogroup or nobody for the permissionless group
	if grep -qs "^nogroup:" /etc/group; then
	        NOGROUP=nogroup
	else
        	NOGROUP=nobody
	fi

	# An old version of easy-rsa was available by default in some openvpn packages
	if [[ -d /etc/openvpn/easy-rsa/ ]]; then
		rm -rf /etc/openvpn/easy-rsa/
	fi
	# Get easy-rsa
	wget -O ~/EasyRSA-3.0.1.tgz https://github.com/OpenVPN/easy-rsa/releases/download/3.0.1/EasyRSA-3.0.1.tgz
	tar xzf ~/EasyRSA-3.0.1.tgz -C ~/
	mv ~/EasyRSA-3.0.1/ /etc/openvpn/
	mv /etc/openvpn/EasyRSA-3.0.1/ /etc/openvpn/easy-rsa/
	chown -R root:root /etc/openvpn/easy-rsa/
	rm -rf ~/EasyRSA-3.0.1.tgz
	cd /etc/openvpn/easy-rsa/
	# If the user selected the fast, less hardened version
	if [[ "$VARIANT" = '1' ]]; then
		echo "set_var EASYRSA_KEY_SIZE 2048
set_var EASYRSA_DIGEST "sha256"" > vars
	fi
	# If the user selected the relatively slow, ultra hardened version
	if [[ "$VARIANT" = '2' ]]; then
		echo "set_var EASYRSA_KEY_SIZE 4096
set_var EASYRSA_DIGEST "sha384"" > vars
	fi
	# Create the PKI, set up the CA, the DH params and the server + client certificates
	./easyrsa init-pki
	./easyrsa --batch build-ca nopass
	./easyrsa gen-dh
	./easyrsa build-server-full server nopass
	./easyrsa build-client-full $CLIENT nopass
	./easyrsa gen-crl
	# generate tls-auth key
	openvpn --genkey --secret /etc/openvpn/tls-auth.key
	# Move the stuff we need
	cp pki/ca.crt pki/private/ca.key pki/dh.pem pki/issued/server.crt pki/private/server.key /etc/openvpn/easy-rsa/pki/crl.pem /etc/openvpn
	# Make cert revocation list readable for non-root
	chmod 644 /etc/openvpn/crl.pem
	# Generate server.conf
	echo "port $PORT
proto udp
dev tun
ca ca.crt
cert server.crt
key server.key
dh dh.pem
user nobody
group $NOGROUP
topology subnet
server 10.8.0.0 255.255.255.0
ifconfig-pool-persist ipp.txt
cipher AES-256-CBC
auth SHA512
tls-version-min 1.2" > /etc/openvpn/server.conf
	if [[ "$VARIANT" = '1' ]]; then
		# If the user selected the fast, less hardened version
		echo "tls-cipher TLS-DHE-RSA-WITH-AES-128-GCM-SHA256" >> /etc/openvpn/server.conf
	elif [[ "$VARIANT" = '2' ]]; then
		# If the user selected the relatively slow, ultra hardened version
		echo "tls-cipher TLS-DHE-RSA-WITH-AES-256-GCM-SHA384" >> /etc/openvpn/server.conf
	fi
	echo 'push "redirect-gateway def1 bypass-dhcp"' >> /etc/openvpn/server.conf
	# DNS
	case $DNS in
		1)
		# Obtain the resolvers from resolv.conf and use them for OpenVPN
		grep -v '#' /etc/resolv.conf | grep 'nameserver' | grep -E -o '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | while read line; do
			echo "push \"dhcp-option DNS $line\"" >> /etc/openvpn/server.conf
		done
		;;
		2) #OpenDNS
		echo 'push "dhcp-option DNS 208.67.222.222"' >> /etc/openvpn/server.conf
		echo 'push "dhcp-option DNS 208.67.220.220"' >> /etc/openvpn/server.conf
		;;
		3) #Google
		echo 'push "dhcp-option DNS 8.8.8.8"' >> /etc/openvpn/server.conf
		echo 'push "dhcp-option DNS 8.8.4.4"' >> /etc/openvpn/server.conf
		;;
	esac
	echo "keepalive 10 120
persist-key
persist-tun
crl-verify crl.pem
tls-server
tls-auth tls-auth.key 0" >> /etc/openvpn/server.conf
	# Enable net.ipv4.ip_forward for the system
	sed -i '/\<net.ipv4.ip_forward\>/c\net.ipv4.ip_forward=1' /etc/sysctl.conf
	if ! grep -q "\<net.ipv4.ip_forward\>" /etc/sysctl.conf; then
		echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf
	fi
	# Avoid an unneeded reboot
	echo 1 > /proc/sys/net/ipv4/ip_forward
	# Set NAT for the VPN subnet
	if [[ "$FORWARD_TYPE" = '1' ]]; then
		iptables -t nat -A POSTROUTING -s 10.8.0.0/24 -j SNAT --to $IP
		sed -i "1 a\iptables -t nat -A POSTROUTING -s 10.8.0.0/24 -j SNAT --to $IP" $RCLOCAL
	else
		iptables -t nat -A POSTROUTING -s 10.8.0.0/24 -o eth0 -j MASQUERADE
		sed -i "1 a\iptables -t nat -A POSTROUTING -s 10.8.0.0/24 -o eth0 -j MASQUERADE" $RCLOCAL
	fi
	if pgrep firewalld; then
		# We don't use --add-service=openvpn because that would only work with
		# the default port. Using both permanent and not permanent rules to
		# avoid a firewalld reload.
		firewall-cmd --zone=public --add-port=$PORT/udp
		firewall-cmd --zone=trusted --add-source=10.8.0.0/24
		firewall-cmd --permanent --zone=public --add-port=$PORT/udp
		firewall-cmd --permanent --zone=trusted --add-source=10.8.0.0/24
		if [[ "$FORWARD_TYPE" = '1' ]]; then
			firewall-cmd --zone=trusted --add-masquerade
			firewall-cmd --permanent --zone=trusted --add-masquerade
		fi
	elif hash ufw 2>/dev/null && ufw status | grep -qw active; then
		ufw allow $PORT/udp
		if [[ "$FORWARD_TYPE" = '1' ]]; then
			sed -i '1s/^/##OPENVPN_START\n*nat\n:POSTROUTING ACCEPT [0:0]\n-A POSTROUTING -s 10.8.0.0\/24 -o eth0 -j MASQUERADE\nCOMMIT\n##OPENVPN_END\n\n/' /etc/ufw/before.rules
			sed -ie 's/^DEFAULT_FORWARD_POLICY\s*=\s*/DEFAULT_FORWARD_POLICY="ACCEPT"\n#before openvpn: /' /etc/default/ufw
		fi
	fi
	if iptables -L -n | grep -qE 'REJECT|DROP'; then
		# If iptables has at least one REJECT rule, we asume this is needed.
		# Not the best approach but I can't think of other and this shouldn't
		# cause problems.
		iptables -I INPUT -p udp --dport $PORT -j ACCEPT
		iptables -I FORWARD -s 10.8.0.0/24 -j ACCEPT
		iptables -I FORWARD -m state --state RELATED,ESTABLISHED -j ACCEPT
		sed -i "1 a\iptables -I INPUT -p udp --dport $PORT -j ACCEPT" $RCLOCAL
		sed -i "1 a\iptables -I FORWARD -s 10.8.0.0/24 -j ACCEPT" $RCLOCAL
		sed -i "1 a\iptables -I FORWARD -m state --state RELATED,ESTABLISHED -j ACCEPT" $RCLOCAL
	fi
	# If SELinux is enabled and a custom port was selected, we need this
	if hash sestatus 2>/dev/null; then
		if sestatus | grep "Current mode" | grep -qs "enforcing"; then
			if [[ "$PORT" != '1194' ]]; then
				# semanage isn't available in CentOS 6 by default
				if ! hash semanage 2>/dev/null; then
					yum install policycoreutils-python -y
				fi
				semanage port -a -t openvpn_port_t -p udp $PORT
			fi
		fi
	fi
	# And finally, restart OpenVPN
	if [[ "$OS" = 'debian' ]]; then
		# Little hack to check for systemd
		if pgrep systemd-journal; then
			systemctl restart openvpn@server.service
		else
			/etc/init.d/openvpn restart
		fi
	else
		if pgrep systemd-journal; then
			systemctl restart openvpn@server.service
			systemctl enable openvpn@server.service
		else
			service openvpn restart
			chkconfig openvpn on
		fi
	fi
	# Try to detect a NATed connection and ask about it to potential LowEndSpirit/Scaleway users
	EXTERNALIP=$(wget -qO- ipv4.icanhazip.com)
	if [[ "$IP" != "$EXTERNALIP" ]]; then
		echo ""
		echo "Sepertinya server Anda berada di belakang NAT!"
		echo ""
                echo "Jika server Anda terkontaminasi (mis LowEndSpirit, Scaleway, atau di belakang router),"
                echo "maka saya perlu tahu alamat yang dapat digunakan untuk mengakses dari luar."
                echo "Jika itu tidak terjadi, hanya mengabaikan ini dan meninggalkan kolom berikutnya kosong"
                read -p "Eksternal IP atau nama domain: " -e USEREXTERNALIP
		if [[ "$USEREXTERNALIP" != "" ]]; then
			IP=$USEREXTERNALIP
		fi
	fi
	# client-common.txt dibuat sehingga kita memiliki template untuk menambahkan pengguna lebih lanjut kemudian
echo "client
dev tun
proto udp
remote $IP $PORT
resolv-retry infinite
nobind
persist-key
persist-tun
remote-cert-tls server
cipher AES-256-CBC
auth SHA512
setenv opt block-outside-dns
tls-version-min 1.2
tls-client" > /etc/openvpn/client-common.txt
	if [[ "$VARIANT" = '1' ]]; then
		# If the user selected the fast, less hardened version
		echo "tls-cipher TLS-DHE-RSA-WITH-AES-128-GCM-SHA256" >> /etc/openvpn/client-common.txt
	elif [[ "$VARIANT" = '2' ]]; then
		# If the user selected the relatively slow, ultra hardened version
		echo "tls-cipher TLS-DHE-RSA-WITH-AES-256-GCM-SHA384" >> /etc/openvpn/client-common.txt
	fi
	# Menghasilkan custom client.ovpn
	newclient "$CLIENT"
	echo ""
	echo "Finished!"
	echo ""
	echo "Config client Anda tersedia di ~/$CLIENT.ovpn"
	echo "Jika Anda ingin menambahkan lebih banyak Client, Anda hanya perlu menjalankan script ini lain waktu! "
 echo ""
 echo "Thanks to Allah swt dan emak guwe!"
fi
exit 0;
