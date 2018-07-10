#!/bin/bash -ex

export OPENQA_BASEDIR="/var/lib"
export OPENQA="$OPENQA_BASEDIR/openqa"
export OPENQA_CONFIG="/etc/openqa"
export WORKERS=${WORKERS-1}

# Methods whose names start with "start_" were created specially for docker containers and they
# serve as systemd startup equivalents. When configuring openQA on a server without docker,
# be sure to substitute:
# - start_dbus with systemctl [enable|start] dbus
# - start_openvswitch with systemctl [enable|start] openvswitch
# - start_openqa with systemctl [enable|start] openqa-gru, openqa-webui, openqa-websockets and openqa-scheduler
# - start_openqa_workers with systemctl [enable|start] openqa-worker@\*
# - start_os-autoinst-ovs with systemctl [enable|start] os-autoinst-openvswitch

setup_workers_config() {
	cp -f /root/workers.ini /etc/openqa;
	for ((i=1; i<=$WORKERS; i++)); do
		echo -e "[$i]\nWORKER_CLASS = tap,qemu_$(uname -m)\n" >> /etc/openqa/workers.ini;
	done;
}

start_dbus() {
	id srvGeoClue 2>/dev/null ||
	useradd -m -s /sbin/nologin -u 486 -g 65534 -d /var/lib/srvGeoClue -c "User for GeoClue D-Bus service" srvGeoClue;
	mkdir -p /run/dbus;
	rm -f /run/dbus/pid;
	dbus-cleanup-sockets;
	export DBUS_STARTER_BUS_TYPE=system;
	dbus-daemon --system --fork --nopidfile;
}

start_openqa() {
        TYPE=${1-production};
	start_daemon -u geekotest "$OPENQA/script/openqa-scheduler" & sleep 1;
	start_daemon -u geekotest "$OPENQA/script/openqa-websockets" & sleep 1;
	start_daemon -u geekotest "$OPENQA/script/openqa" gru -m production run & sleep 1;
	start_daemon -u geekotest "$OPENQA/script/openqa" prefork -m production --proxy & sleep 1;
}

start_openqa_workers() {
	for ((i=1; i<=$WORKERS; i++)); do
		su - _openqa-worker -c "$OPENQA/script/worker --instance $i --verbose & sleep 1";
	done;
}

start_openvswitch() {
	mkdir -p /etc/openvswitch;
	mkdir -p /var/run/openvswitch;
	test -f /etc/openvswitch/conf.db || ovsdb-tool create;
	ovsdb-server /etc/openvswitch/conf.db -vconsole:emer -vsyslog:err -vfile:info --remote=punix:/var/run/openvswitch/db.sock --private-key=db:Open_vSwitch,SSL,private_key --certificate=db:Open_vSwitch,SSL,certificate --bootstrap-ca-cert=db:Open_vSwitch,SSL,ca_cert --no-chdir --log-file=/var/log/openvswitch/ovsdb-server.log --pidfile=/var/run/openvswitch/ovsdb-server.pid --detach;
	ovs-vswitchd unix:/var/run/openvswitch/db.sock -vconsole:emer -vsyslog:err -vfile:info --mlockall --no-chdir --log-file=/var/log/openvswitch/ovs-vswitchd.log --pidfile=/var/run/openvswitch/ovs-vswitchd.pid --detach
	/usr/share/openvswitch/scripts/ovs-dpdk-migrate-2.6.sh
}

tunctl_config() {
	if [ ! -c /dev/net/tun ]; then
		mkdir -p /dev/net;
		mknod /dev/net/tun c 10 200;
	fi
	for ((i=0; i<$WORKERS; i++)); do
		tunctl -u _openqa-worker -p -t tap$i;
	done;
}

setup_bridge() {
	ovs-vsctl br-exists br0 || ovs-vsctl add-br br0;
	cp /root/ifcfg-br0 /etc/sysconfig/network/;
	for ((i=0; i<$WORKERS; i++)); do
		echo "OVS_BRIDGE_PORT_DEVICE_1='tap$i'" >> /etc/sysconfig/network/ifcfg-br0;
		(ovs-vsctl list-ports br0 | grep -w tap$i) || ovs-vsctl add-port br0 tap$i tag=999;
	done;
	chown root /etc/sysconfig/network/ifcfg-br0;
	chmod 600 /etc/sysconfig/network/ifcfg-br0;
	ip addr add 10.0.2.2/15 dev br0;
	set +e;
	ip route add 10.0.0.0/15 dev br0;
	set -e;
	ip link set br0 up;
}

start_os-autoinst-ovs() {
	/usr/lib/os-autoinst/os-autoinst-openvswitch;
}

start_postgres() {
	su - postgres -c "/usr/lib/postgresql-init start"
}

init_db() {
	if [ ! -f /etc/openqa/db-initialized ]; then
		su - postgres -c "createuser geekotest && createdb -O geekotest openqa";
		/usr/share/openqa/script/initdb --user geekotest --init_database;
		echo "[localhost]" >> /etc/openqa/client.conf;
		su - geekotest -c "/usr/share/openqa/script/create_admin admin" 2>/dev/null | \
		sed -n -e '/^Key:/s/^Key:/key =/p' -e '/^Secret:/s/^Secret:/secret =/p' >> /etc/openqa/client.conf && \
		echo >> /etc/openqa/client.conf;
		date > /etc/openqa/db-initialized;
	fi
}

