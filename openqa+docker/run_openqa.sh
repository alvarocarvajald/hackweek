#!/bin/bash -ex

# Load functions first
source /root/openqa_functions.sh

# Start syslog
syslogd

# Start dbus daemon
start_dbus

# Add hostname to openQA's client.conf if it's not there already
grep $(hostname) /etc/openqa/client.conf >/dev/null 2>&1 || \
tail -4 /etc/openqa/client.conf | sed 's/localhost/'$(hostname)'/' >> /etc/openqa/client.conf

# Finish workers configuration. Check -e WORKERS
setup_workers_config

# Finish network configuration
start_openvswitch
tunctl_config
setup_bridge

# Start Apache
apache2ctl start

# Start openQA processes
start_openqa
start_openqa_workers
start_os-autoinst-ovs

# Stay checking the logs
journalctl -f

