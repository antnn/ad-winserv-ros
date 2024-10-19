/interface bridge add name=bridge1
/interface bridge port add interface=ether2 bridge=bridge1
/ip address add address=192.168.88.1/24 interface=bridge1
/ip address add address=192.168.122.3/24 interface=ether1
/ip route add gateway=192.168.122.1
/ip dns set servers=1.1.1.1

/ip dhcp-server add name=dhcp1 interface=bridge1 lease-time=1800
/ip dhcp-server network add address=192.168.88.0/24 gateway=192.168.88.1 dns-server=192.168.88.1
/ip pool add name=dhcp_pool1 ranges=192.168.88.4-192.168.88.254
/ip dhcp-server set dhcp1 address-pool=dhcp_pool1

/ip firewall nat add chain=srcnat out-interface=ether1 action=masquerade

/certificate add name=root-ca common-name=MikroTik-CA key-usage=key-cert-sign,crl-sign
/certificate sign root-ca
/certificate add name=sstp-server-cert common-name=192.168.122.1 days-valid=365 key-size=2048 key-usage=digital-signature,key-encipherment,tls-server
/certificate sign sstp-server-cert ca=root-ca ca-crl-host=192.168.122.1

/ppp secret add local-address=10.0.0.1 name=MT-User password=StrongPass remote-address=10.0.0.5 service=sstp
/interface sstp-server server set default-profile=default-encryption enabled=yes certificate=sstp-server-cert
