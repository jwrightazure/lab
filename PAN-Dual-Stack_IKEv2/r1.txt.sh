hostname r1

crypto ikev2 proposal prop1
 encryption aes-cbc-256
 integrity sha256
 group 14
!
crypto ikev2 policy pol1
 proposal prop1
!
crypto ikev2 keyring key1
 peer all
  address 0.0.0.0 0.0.0.0
  pre-shared-key PaloAltoCSCO4$
!
crypto ikev2 profile prof1
 match identity remote address 0.0.0.0
 match identity remote address ::/0
 authentication remote pre-share
 authentication local pre-share
 keyring local key1
!
crypto isakmp policy 1
 encr aes 256
 hash sha256
 authentication pre-share
 group 14
 lifetime 28800
crypto isakmp key PaloAltoCSCO4$ address 0.0.0.0
crypto isakmp invalid-spi-recovery
crypto isakmp keepalive 10
!
crypto ipsec transform-set TSET esp-aes 256 esp-sha256-hmac
 mode tunnel
!
crypto ipsec profile VTI
 set transform-set TSET
 set ikev2-profile prof1
!
crypto ipsec profile VTI-2
 set transform-set TSET
 set ikev2-profile prof1
!
interface Tunnel10
 ip address 169.254.1.2 255.255.255.252
 tunnel source Ethernet0/0
 tunnel mode ipsec ipv4
 tunnel destination 192.168.1.2
 tunnel path-mtu-discovery
 tunnel protection ipsec profile VTI
!
interface Tunnel11
 no ip address
 ipv6 address 2001:1234:93::1/64
 ipv6 enable
 tunnel source Ethernet0/0
 tunnel mode ipsec ipv4 v6-overlay
 tunnel destination 192.168.2.2
 tunnel protection ipsec profile VTI-2
!
interface Ethernet0/0
 ip address 192.168.4.2 255.255.255.0
 duplex auto
!
ip route 0.0.0.0 0.0.0.0 192.168.4.1
