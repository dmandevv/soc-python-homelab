# 2026-08-30 09:55:38 by RouterOS 7.24.1
# software id = 5ZE0-74LK
#
# model = CRS326-24G-2S+
# serial number = HM80B1MVKS2
/interface bridge
add name=bridge1
/ip pool
add name=temp-pool ranges=10.10.10.100-10.10.10.200
/ip dhcp-server
add address-pool=temp-pool interface=bridge1 name=temp-dhcp
/interface bridge port
add bridge=bridge1 interface=ether2
add bridge=bridge1 interface=ether3
add bridge=bridge1 interface=ether4
add bridge=bridge1 interface=ether5
add bridge=bridge1 interface=ether6
add bridge=bridge1 interface=ether7
add bridge=bridge1 interface=ether8
add bridge=bridge1 interface=ether9
add bridge=bridge1 interface=ether10
add bridge=bridge1 interface=ether11
add bridge=bridge1 interface=ether12
add bridge=bridge1 interface=ether13
add bridge=bridge1 interface=ether14
add bridge=bridge1 interface=ether15
add bridge=bridge1 interface=ether16
add bridge=bridge1 interface=ether17
add bridge=bridge1 interface=ether18
add bridge=bridge1 interface=ether19
add bridge=bridge1 interface=ether20
add bridge=bridge1 interface=ether21
add bridge=bridge1 interface=ether22
add bridge=bridge1 interface=ether23
add bridge=bridge1 interface=ether24
/ip settings
set rp-filter=strict
/ip address
add address=10.10.10.1/24 interface=bridge1 network=10.10.10.0
add address=10.0.0.2/24 interface=ether1 network=10.0.0.0
/ip dhcp-server network
add address=10.10.10.0/24 dns-server=1.1.1.1,8.8.8.8 gateway=10.10.10.1
/ip dns
set allow-remote-requests=yes servers=1.1.1.1,8.8.8.8
/ip firewall filter
add action=accept chain=input comment=established/related connection-state=\
    established,related
add action=drop chain=input comment=invalid connection-state=invalid
add action=accept chain=input comment=ICMP protocol=icmp
add action=accept chain=input comment="management LAN" src-address=\
    10.10.10.0/24
add action=drop chain=input comment="drop all other input"
/ip firewall nat
add action=masquerade chain=srcnat out-interface=ether1
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
