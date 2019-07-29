build:
	@echo "Install build dependencies"
	apt install -y vim curl make sudo mc pbuilder devscripts squashfs-tools autoconf automake dpkg-dev genisoimage lsb-release fakechroot libtool libapt-pkg-dev parted kpartx qemu-system-x86 qemu-utils quilt python3-lxml python3-setuptools python3-nose python3-coverage python3-sphinx python3-pystache pkg-config debhelper jq libc-ares-dev libkrb5-dev libssl-dev libxml2-dev systemd libcurl4-openssl-dev libgcrypt20-dev libgmp3-dev libldap2-dev libsqlite3-dev dh-apparmor gperf libsystemd-dev python3-stdeb python-setuptools bison flex iptables-dev libcap-dev libpam0g-dev

	@echo "Copy relevant files from vyatta-cfg-system repo"
	cp -R dmvpn-vyatta-cfg-system/templates/interfaces/tunnel/ edgeos-dmvpn-conf/opt/vyatta/share/vyatta-cfg/templates/interfaces/
	cp dmvpn-vyatta-cfg-system/scripts/vyatta-update-tunnel.pl edgeos-dmvpn-conf/opt/vyatta/sbin/

	@echo "Copy relevant files from vyatta-cfg-vpn repo"
	cp -R dmvpn-vyatta-cfg-vpn/templates/ edgeos-dmvpn-conf/opt/vyatta/share/vyatta-cfg/
	cp dmvpn-vyatta-cfg-vpn/scripts/dmvpn-config.pl edgeos-dmvpn-conf/opt/vyatta/sbin/
	chmod 755 edgeos-dmvpn-conf/opt/vyatta/sbin/*

	@echo "Build custom dmvpn-vyos-nhrp"
	dmvpn-vyos-build/scripts/build-packages -v -k -b dmvpn-vyos-nhrp

	@echo "Build normal vyos-opennhrp and vyos-strongswan"
	dmvpn-vyos-build/scripts/build-packages -v -b vyos-opennhrp vyos-strongswan

	@echo "Tar all relevant packages and files"
	tar czvf edgeos-dmvpn.tar.gz --exclude=*-dbgsym* *.deb deps/* edgeos-dmvpn-conf TARGET-INSTALL
