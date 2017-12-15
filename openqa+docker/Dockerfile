FROM opensuse:42.2

# Install openQA and pre-requisites
RUN zypper ar -f obs://devel:openQA/openSUSE_Leap_42.2 openQA && \
    zypper ar -f obs://devel:openQA:Leap:42.2/openSUSE_Leap_42.2 openQA-perl-modules && \
    zypper ar -f http://download.suse.de/ibs/SUSE:/CA/openSUSE_Leap_42.1/SUSE:CA.repo && \
    zypper --gpg-auto-import-keys refresh && \
    zypper in -y --force-resolution NetworkManager openQA apache2 which w3m glibc-locale \
                 glibc-locale-32bit perl-App-cpanminus bridge-utils libcap-progs tunctl \
                 openQA-worker openQA-client os-autoinst openvswitch os-autoinst-openvswitch \
                 qemu qemu-tools qemu-block-curl qemu-block-rbd qemu-ipxe qemu-x86 \
                 qemu-vgabios qemu-sgabios qemu-seabios SuSEfirewall2 syslogd \
                 postgresql-server && \
    zypper clean

# Install needles and tests
RUN mkdir -p /var/lib/openqa/share/tests && \
    mkdir -p /var/lib/pgsql/data/ && \
    cd /var/lib/openqa/share/tests && \
    git clone git://github.com/os-autoinst/os-autoinst-distri-opensuse.git opensuse && \
    cd /var/lib/openqa/share/tests/opensuse/products/opensuse && \
    git clone git://github.com/os-autoinst/os-autoinst-needles-opensuse.git needles && \
    zypper in -y ca-certificates-suse && \
    cd /var/lib/openqa/share/tests/opensuse/products/sle && \
    git clone https://gitlab.suse.de/openqa/os-autoinst-needles-sles.git needles && \
    cd /var/lib/openqa/share/tests && \
    ln -s opensuse sle && \
    ln -s opensuse sle-12-SP2 && \
    ln -s opensuse sle-12-SP3 && \
    zypper clean

# Add config and startup files. Read comments on run_openqa.sh about how to start
# openQA outside of docker
ADD ifcfg-br0 /root/
ADD openqa_functions.sh /root/
ADD run_openqa.sh /root/

EXPOSE 80

# Check needed build arguments and configure apache and openQA
RUN chmod +x /root/run_openqa.sh && \
    chown postgres /var/lib/pgsql/data/ && \
    mv /etc/apache2/vhosts.d/openqa.conf.template /etc/apache2/vhosts.d/openqa.conf && \
    a2enmod headers && a2enmod proxy && a2enmod proxy_http && a2enmod proxy_wstunnel && \
    sed -i -e '/httpsonly/s/.*/httpsonly = 0/' -e '/# method/amethod = Fake' /etc/openqa/openqa.ini && \
    setcap CAP_NET_ADMIN=ep /usr/bin/qemu-system-x86_64 && \
    cp /etc/openqa/workers.ini /root/ && \
    sed -ri -e 's/^FW_ROUTE=.*/FW_ROUTE="yes"/' -e 's/^FW_MASQUERADE=.*/FW_MASQUERADE="yes"/' \
            -e 's/^FW_DEV_INT=.*/FW_DEV_INT="br0"/' /etc/sysconfig/SuSEfirewall2

ENTRYPOINT ["/root/run_openqa.sh"]

