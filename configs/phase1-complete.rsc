# 2026-09-01 14:11:49 by RouterOS 7.24.1
# software id = 5ZE0-74LK
#
# model = CRS326-24G-2S+
# serial number = HM80B1MVKS2
/interface bridge
add name=bridge1 vlan-filtering=yes
/interface ethernet
set [ find default-name=ether20 ] disabled=yes
set [ find default-name=ether21 ] disabled=yes
set [ find default-name=ether22 ] disabled=yes
set [ find default-name=ether23 ] disabled=yes
set [ find default-name=ether24 ] disabled=yes
/interface vlan
add interface=bridge1 name=vlan10 vlan-id=10
add interface=bridge1 name=vlan20 vlan-id=20
add interface=bridge1 name=vlan30 vlan-id=30
add interface=bridge1 name=vlan40 vlan-id=40
/interface list
add name=LAN
/ip pool
add name=pool-vlan10 ranges=10.10.10.100-10.10.10.200
add name=pool-vlan20 ranges=10.10.20.100-10.10.20.200
add name=pool-vlan30 ranges=10.10.30.100-10.10.30.200
/interface bridge port
add bridge=bridge1 frame-types=admit-only-vlan-tagged interface=ether2 pvid=\
    99
add bridge=bridge1 frame-types=admit-only-vlan-tagged interface=ether3 pvid=\
    99
add bridge=bridge1 frame-types=admit-only-untagged-and-priority-tagged \
    interface=ether4 pvid=10
add bridge=bridge1 frame-types=admit-only-untagged-and-priority-tagged \
    interface=ether5 pvid=10
add bridge=bridge1 frame-types=admit-only-untagged-and-priority-tagged \
    interface=ether6 pvid=10
add bridge=bridge1 frame-types=admit-only-untagged-and-priority-tagged \
    interface=ether7 pvid=10
add bridge=bridge1 frame-types=admit-only-untagged-and-priority-tagged \
    interface=ether8 pvid=20
add bridge=bridge1 frame-types=admit-only-untagged-and-priority-tagged \
    interface=ether9 pvid=20
add bridge=bridge1 frame-types=admit-only-untagged-and-priority-tagged \
    interface=ether10 pvid=20
add bridge=bridge1 frame-types=admit-only-untagged-and-priority-tagged \
    interface=ether11 pvid=20
add bridge=bridge1 frame-types=admit-only-untagged-and-priority-tagged \
    interface=ether12 pvid=30
add bridge=bridge1 frame-types=admit-only-untagged-and-priority-tagged \
    interface=ether13 pvid=30
add bridge=bridge1 frame-types=admit-only-untagged-and-priority-tagged \
    interface=ether14 pvid=30
add bridge=bridge1 frame-types=admit-only-untagged-and-priority-tagged \
    interface=ether15 pvid=30
add bridge=bridge1 frame-types=admit-only-untagged-and-priority-tagged \
    interface=ether16 pvid=40
add bridge=bridge1 frame-types=admit-only-untagged-and-priority-tagged \
    interface=ether17 pvid=40
add bridge=bridge1 frame-types=admit-only-untagged-and-priority-tagged \
    interface=ether18 pvid=40
add bridge=bridge1 frame-types=admit-only-untagged-and-priority-tagged \
    interface=ether19 pvid=40
add bridge=bridge1 frame-types=admit-only-untagged-and-priority-tagged \
    interface=ether20 pvid=99
add bridge=bridge1 frame-types=admit-only-untagged-and-priority-tagged \
    interface=ether21 pvid=99
add bridge=bridge1 frame-types=admit-only-untagged-and-priority-tagged \
    interface=ether22 pvid=99
add bridge=bridge1 frame-types=admit-only-untagged-and-priority-tagged \
    interface=ether23 pvid=99
add bridge=bridge1 frame-types=admit-only-untagged-and-priority-tagged \
    interface=ether24 pvid=99
/ip settings
set rp-filter=strict
/interface bridge vlan
add bridge=bridge1 tagged=bridge1,ether2,ether3 untagged=\
    ether4,ether5,ether6,ether7 vlan-ids=10
add bridge=bridge1 tagged=bridge1,ether2,ether3 untagged=\
    ether8,ether9,ether10,ether11 vlan-ids=20
add bridge=bridge1 tagged=bridge1,ether2,ether3 untagged=\
    ether12,ether13,ether14,ether15 vlan-ids=30
add bridge=bridge1 tagged=bridge1,ether2,ether3 untagged=\
    ether16,ether17,ether18,ether19 vlan-ids=40
add bridge=bridge1 untagged=ether20,ether21,ether22,ether23,ether24 vlan-ids=\
    99
/interface list member
add interface=vlan10 list=LAN
add interface=vlan20 list=LAN
add interface=vlan30 list=LAN
add interface=vlan40 list=LAN
/ip address
add address=10.10.10.1/24 interface=vlan10 network=10.10.10.0
add address=10.0.0.2/24 interface=ether1 network=10.0.0.0
add address=10.10.20.1/24 interface=vlan20 network=10.10.20.0
add address=10.10.30.1/24 interface=vlan30 network=10.10.30.0
add address=10.10.40.1/24 interface=vlan40 network=10.10.40.0
/ip dhcp-server
add address-pool=pool-vlan10 interface=vlan10 name=dhcp-vlan10
add address-pool=pool-vlan20 interface=vlan20 name=dhcp-vlan20
add address-pool=pool-vlan30 interface=vlan30 name=dhcp-vlan30
/ip dhcp-server network
add address=10.10.10.0/24 dns-server=1.1.1.1,8.8.8.8 gateway=10.10.10.1
add address=10.10.20.0/24 dns-server=10.10.20.1 gateway=10.10.20.1
add address=10.10.30.0/24 dns-server=10.10.30.1 gateway=10.10.30.1
add address=10.10.40.0/24 dns-server=10.10.40.1 gateway=10.10.40.1
/ip dns
set allow-remote-requests=yes servers=1.1.1.1,8.8.8.8
/ip firewall filter
add action=accept chain=input comment=established/related connection-state=\
    established,related
add action=drop chain=input comment=invalid connection-state=invalid
add action=accept chain=input comment=ICMP protocol=icmp
add action=accept chain=input comment="management LAN" src-address=\
    10.10.10.0/24
add action=accept chain=input comment="DNS + DHCP from LAN" dst-port=53,67 \
    in-interface-list=LAN protocol=udp
add action=accept chain=input comment="DNS over TCP from LAN" dst-port=53 \
    in-interface-list=LAN protocol=tcp
add action=accept chain=input comment="management from desktop" dst-port=\
    22,8291 in-interface=vlan20 protocol=tcp src-address=10.10.20.50
add action=drop chain=input comment="drop all other input"
add action=accept chain=forward comment=established/related connection-state=\
    established,related
add action=drop chain=forward comment=invalid connection-state=invalid
add action=accept chain=forward comment="LAN to internet" in-interface-list=\
    LAN out-interface=ether1
add action=accept chain=forward comment="management to all VLANs" \
    in-interface=vlan10
add action=accept chain=forward comment="desktop to management" dst-port=\
    22,8006 in-interface=vlan20 out-interface=vlan10 protocol=tcp \
    src-address=10.10.20.50
add action=drop chain=forward comment="drop all other forward"
/ip firewall nat
add action=masquerade chain=srcnat out-interface=ether1
/ip route
add dst-address=0.0.0.0/0 gateway=10.0.0.1
/ip service
set ftp disabled=yes
set telnet disabled=yes
set www disabled=yes
set reverse-proxy disabled=yes
set api disabled=yes
set api-ssl disabled=yes
/system clock
set time-zone-name=America/Vancouver
/system routerboard settings
set enter-setup-on=delete-key
