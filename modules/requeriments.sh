#!/bin/bash
#
# Unattended/SemiAutomatted OpenStack Installer
# Reynaldo R. Martinez P.
# E-Mail: TigerLinux@Gmail.com
# OpenStack PIKE for Ubuntu 16.04lts
#
#

PATH=$PATH:/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin

#
# First, we source our config file
#

if [ -f ./configs/main-config.rc ]
then
	source ./configs/main-config.rc
	mkdir -p /etc/openstack-control-script-config
else
	echo "Can't access my config file. Aborting !"
	echo ""
	exit 0
fi

#
# Some pre-cleanup first !. Just in order to avoid "Oppssess"
#

rm -rf /tmp/keystone-signing-*
rm -rf /tmp/cd_gen_*

# Let's make apt really unattended:

cat<<EOF >/etc/apt/apt.conf.d/99aptget-reallyunattended
Dpkg::Options {
   "--force-confdef";
   "--force-confold";
}
EOF

#
# Then we begin some verifications
#

export DEBIAN_FRONTEND=noninteractive

DEBIAN_FRONTEND=noninteractive apt-get -y install aptitude

osreposinstalled=`aptitude search python-openstackclient|grep python-openstackclient|head -n1|wc -l`
amiroot=` whoami|grep root|wc -l`
amiubuntu1604=`cat /etc/lsb-release|grep DISTRIB_DESCRIPTION|grep -i ubuntu.\*16.\*LTS|head -n1|wc -l`
internalbridgepresent=`ovs-vsctl show|grep -i -c bridge.\*$integration_bridge`
kernel64installed=`uname -p|grep x86_64|head -n1|wc -l`

echo ""
echo "Starting Verifications"
echo ""

if [ $amiubuntu1604 == "1" ]
then
	echo ""
	echo "UBUNTU 16.04 LTS O/S Verified OK"
	echo ""
else
	echo ""
	echo "We could not verify an UBUNTU 16.04 LTS O/S here. Aborting !"
	echo ""
	exit 0
fi

if [ $amiroot == "1" ]
then
	echo ""
	echo "We are root. That's OK"
	echo ""
else
	echo ""
	echo "Apparently, we are not running as root. Aborting !"
	echo ""
	exit 0
fi

if [ $kernel64installed == "1" ]
then
	echo ""
	echo "Kernel x86_64 (amd64) detected. Thats OK"
	echo ""
else
	echo ""
	echo "Apparently, we are not running inside a x86_64 Kernel. Thats NOT Ok. Aborting !"
	echo ""
	exit 0
fi


echo ""
echo "Let's continue"
echo ""

searchtestceilometer=`aptitude search ceilometer-api|grep -ci "ceilometer-api"`

if [ $osreposinstalled == "1" ]
then
	echo ""
	echo "OpenStack PIKE Available for install"
else
	echo ""
	echo "OpenStack PIKE Unavailable. Aborting !"
	echo ""
	exit 0
fi

if [ $searchtestceilometer == "1" ]
then
	echo ""
	echo "Second OpenStack REPO verification OK"
	echo ""
else
	echo ""
	echo "Second OpenStack REPO verification FAILED. Aborting !"
	echo ""
	exit 0
fi

if [ $internalbridgepresent == "1" ]
then
	echo ""
	echo "Integration Bridge Present"
	echo ""
else
	echo ""
	echo "Integration Bridge NOT Present. Aborting !"
	echo ""
	exit 0
fi

echo "Installing initial packages"
echo ""

#
# We proceed to install some initial packages, some of then non-interactivelly
#

apt-get -y update
apt-get -y install crudini python-iniparse debconf-utils

echo "libguestfs0 libguestfs/update-appliance boolean false" > /tmp/libguest-seed.txt
debconf-set-selections /tmp/libguest-seed.txt



DEBIAN_FRONTEND=noninteractive aptitude -y install pm-utils saidar sysstat iotop ethtool iputils-arping \
	libsysfs2 btrfs-tools cryptsetup cryptsetup-bin febootstrap jfsutils libconfig8-dev \
	libcryptsetup4 libguestfs0 libhivex0 libreadline5 reiserfsprogs scrub xfsprogs \
	zerofree zfs-fuse virt-top curl nmon fuseiso9660 libiso9660-8 genisoimage sudo sysfsutils \
	glusterfs-client glusterfs-common nfs-client nfs-common libguestfs-tools arptables

rm -r /tmp/libguest-seed.txt

DEBIAN_FRONTEND=noninteractive aptitude -y install coreutils grep debianutils base-files lsb-release curl \
	wget net-tools git iproute openssh-client sed openssl xz-utils bzip2 util-linux procps mount lvm2

#
# Then we proceed to configure Libvirt and iptables, and also to verify proper installation
# of libvirt. If that fails, we stop here !
#

if [ -f /etc/openstack-control-script-config/libvirt-installed ]
then
	echo ""
	echo "Pre-requirements already installed"
	echo ""
else
	#
	# Next seems to be overkill, but there is a package that breah everything
	# This secuence ensures proper installation of libvirtd packages
        trylist="try1 try2 try3"
        for mytry in $trylist
        do
	        echo "**************************************************************"
	        echo $mytry
	        echo "**************************************************************"
	        sleep 5
		apt-get -y purge dnsmasq-base
		apt-get -y purge libvirt-bin
		apt-get -y purge libvirt-daemon-system
		apt-get -y purge qemu
		apt-get -y purge ubuntu-server
		userdel -r -f libvirt-qemu
		userdel -r -f libvirt-dnsmasq
		rm -rf /etc/libvirt
		rm -f /etc/default/libvirt*	
		echo "iptables-persistent iptables-persistent/autosave_v6 boolean true" > /tmp/iptables-seed.txt
		echo "iptables-persistent iptables-persistent/autosave_v4 boolean true" >> /tmp/iptables-seed.txt
		debconf-set-selections /tmp/iptables-seed.txt
		DEBIAN_FRONTEND=noninteractive aptitude -y install iptables iptables-persistent
		/etc/init.d/netfilter-persistent flush
		/etc/init.d/netfilter-persistent save
		update-rc.d netfilter-persistent enable
		systemctl enable netfilter-persistent
		/etc/init.d/netfilter-persistent save
		rm -f /tmp/iptables-seed.txt
		killall -9 dnsmasq > /dev/null 2>&1
		killall -9 libvirtd > /dev/null 2>&1
		DEBIAN_FRONTEND=noninteractive aptitude -y install libvirt-daemon-system
		virsh net-destroy default
		systemctl enable libvirtd
		systemctl stop libvirtd
		rm -f /etc/libvirt/qemu/networks/default.xml
		rm -f /etc/libvirt/qemu/networks/autostart/default.xml
		killall -9 dnsmasq > /dev/null 2>&1
		killall -9 libvirtd > /dev/null 2>&1
		/etc/init.d/netfilter-persistent flush
		# iptables -A INPUT -p tcp -m multiport --dports 22 -j ACCEPT
		/etc/init.d/netfilter-persistent save
		sed -i 's/#listen_tls = 0/listen_tls = 0/g' /etc/libvirt/libvirtd.conf
		sed -i 's/#listen_tcp = 1/listen_tcp = 1/g' /etc/libvirt/libvirtd.conf
		sed -i 's/#auth_tcp = "sasl"/auth_tcp = "none"/g' /etc/libvirt/libvirtd.conf
		sed -i "s/^#listen_addr\ =.*/listen_addr\ =\ \"$nova_computehost\"/g" /etc/libvirt/libvirtd.conf
		cat /etc/default/libvirtd > /etc/default/libvirtd.BACKUP
		echo "start_libvirtd=\"yes\"" > /etc/default/libvirtd
		echo "libvirtd_opts=\"--listen\"" >> /etc/default/libvirtd
		systemctl start libvirtd
		systemctl status libvirtd
	done

	DEBIAN_FRONTEND=noninteractive aptitude -y install pm-utils saidar sysstat iotop ethtool iputils-arping \
        	libsysfs2 btrfs-tools cryptsetup cryptsetup-bin febootstrap jfsutils libconfig8-dev \
	        libcryptsetup4 libguestfs0 libhivex0 libreadline5 reiserfsprogs scrub xfsprogs \
        	zerofree zfs-fuse virt-top curl nmon fuseiso9660 libiso9660-8 genisoimage sudo sysfsutils \
	        glusterfs-client glusterfs-common nfs-client nfs-common libguestfs-tools arptables

	# iptables -A INPUT -p tcp -m multiport --dports 16509 -j ACCEPT
	# /etc/init.d/netfilter-persistent save
	./modules/firewall-master-reset.sh

	apt-get -y install apparmor-utils
	# aa-disable /etc/apparmor.d/usr.sbin.libvirtd
	# /etc/init.d/libvirt-bin restart
	chmod 644 /boot/vmlinuz-*
fi

#
# KSM Tuned:
#

aptitude -y install ksmtuned
systemctl enable ksmtuned
systemctl restart ksmtuned

if [ $vhostnet == "yes" ]
then
	echo "vhost_net" >> /etc/modules
	modprobe vhost_net
fi

# Final secuence:
echo "FINAL LIBVIRTD CHECK:"
aa-complain /etc/apparmor.d/usr.sbin.libvirtd
systemctl stop libvirtd
systemctl stop virtlogd.socket
systemctl start virtlogd.socket
systemctl start libvirtd
systemctl status libvirtd


testlibvirt=`dpkg -l libvirt-daemon-system 2>/dev/null|tail -n 1|grep -ci ^ii`

if [ $testlibvirt == "1" ]
then
	echo ""
	echo "Libvirt correctly installed"
	date > /etc/openstack-control-script-config/libvirt-installed
	echo ""
else
	echo ""
	echo "Libvirt installation FAILED. Aborting !"
	exit 0
fi

