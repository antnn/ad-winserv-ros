#!/bin/bash
/sbin/pppd \
remotename sstpcon1 \
linkname   sstpcon1 \
ipparam    sstpcon1 \
ifname     sstpcon1 \
pty "/sbin/sstpc --ipparam sstpcon1 --nolaunchpppd 192.168. --cert-warn  --password StrongPass " \
user MT-User \
nodetach \
lock \
noipdefault \
nodefaultroute \
noauth \
mtu 1400 \
refuse-eap \
refuse-pap \
refuse-chap \
refuse-mschap \
nobsdcomp \
nodeflate \
novj \
lcp-echo-failure 0 \
lcp-echo-interval 0 \
plugin /usr/lib64/pppd/2.5.0/sstp-pppd-plugin.so \
sstp-sock /var/run/sstpc/sstpc-sstpcon1 \
