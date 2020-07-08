# S2S VPN a Cisco CSR and Active/Active Azure VPN Gateway
This lab guide illustrates how to build a basic IPSEC/IKEv2 VPN tunnel between a CSR and active/active Azure VPN gateways. Each tunnel is using BGP plus VTIs for tunnel termination. Traffic sourcing from either side of the tunnel will ECMP load share. The CSR configs are broken out for each tunnel and can be combined as needed. The lab includes 2 test Linux VMs for additional verification and testing. On prem is simulated with a VNET so no hardware is needed. All username/password are azureuser/Msft123Msft123.
# Base Topology

![alt text](https://github.com/jwrightazure/lab/blob/master/images/csr-topo.PNG)

![alt text](https://github.com/jwrightazure/lab/blob/master/images/csr-bgp.PNG)

**Before deploying CSR in the next step, you may have to accept license agreement unless you have used it before. You can accomplish this through deploying a CSR in the portal or Powershell commands via Cloudshell**
<pre lang="...">
Sample Powershell:
Get-AzMarketplaceTerms -Publisher "Cisco" -Product "cisco-csr-1000v" -Name "17_2_1-byol"
Get-AzMarketplaceTerms -Publisher "Cisco" -Product "cisco-csr-1000v" -Name "17_2_1-byol" | Set-AzMarketplaceTerms -Accept
</pre>

**Build Resource Groups, VNET and Subnets for the hub and onprem networks. The Azure VPN gateways will take about 20 minutes to deploy.**
<pre lang="...">
az group create --name VPN --location eastus2
az network vnet create --resource-group VPN --name VPNhub --location eastus2 --address-prefixes 10.0.0.0/16 --subnet-name VPNhubVM --subnet-prefix 10.0.10.0/24
az network vnet subnet create --address-prefix 10.0.0.0/24 --name GatewaySubnet --resource-group VPN --vnet-name VPNhub
az network vnet create --resource-group VPN --name onprem --location eastus2 --address-prefixes 10.1.0.0/16 --subnet-name onpremVM --subnet-prefix 10.1.10.0/24
az network vnet subnet create --address-prefix 10.1.0.0/24 --name zeronet --resource-group VPN --vnet-name onprem
az network vnet subnet create --address-prefix 10.1.1.0/24 --name onenet --resource-group VPN --vnet-name onprem
az network public-ip create --name Azure-VNGpubip1 --resource-group VPN --allocation-method Dynamic
az network public-ip create --name Azure-VNGpubip2 --resource-group VPN --allocation-method Dynamic
az network vnet-gateway create --name Azure-VNG --public-ip-address Azure-VNGpubip1 Azure-VNGpubip2 --resource-group VPN --vnet VPNhub --gateway-type Vpn --vpn-type RouteBased --sku VpnGw1 --asn 65001 --no-wait 
az network public-ip create --name CSRPublicIP --resource-group VPN --idle-timeout 30 --allocation-method Static
az network nic create --name CSROutsideInterface -g VPN --subnet zeronet --vnet onprem --public-ip-address CSRPublicIP --ip-forwarding true --private-ip-address 10.1.0.4
az network nic create --name CSRInsideInterface -g VPN --subnet onenet --vnet onprem --ip-forwarding true --private-ip-address 10.1.1.4
az vm create --resource-group VPN --location eastus2 --name CSR --size Standard_DS3_v2 --nics CSROutsideInterface CSRInsideInterface --image cisco:cisco-csr-1000v:17_2_1-byol:17.2.120200508 --admin-username azureuser --admin-password Msft123Msft123 --no-wait 
az network public-ip create --name VPNhubVM --resource-group VPN --location eastus2 --allocation-method Dynamic
az network nic create --resource-group VPN -n VPNVMNIC --location eastus2 --subnet VPNhubVM --private-ip-address 10.0.10.10 --vnet-name VPNhub --public-ip-address VPNhubVM --ip-forwarding true
az vm create -n VPNVM -g VPN --image UbuntuLTS --admin-username azureuser --admin-password Msft123Msft123 --nics VPNVMNIC --no-wait 
az network public-ip create --name onpremVM --resource-group VPN --location eastus2 --allocation-method Dynamic
az network nic create --resource-group VPN -n onpremVMNIC --location eastus2 --subnet onpremVM --private-ip-address 10.1.10.10 --vnet-name onprem --public-ip-address onpremVM --ip-forwarding true
az vm create -n onpremVM -g VPN --image UbuntuLTS --admin-username azureuser --admin-password Msft123Msft123 --nics onpremVMNIC --no-wait 
az network route-table create --name vm-rt --resource-group VPN
az network route-table route create --name vm-rt --resource-group VPN --route-table-name vm-rt --address-prefix 10.0.0.0/16 --next-hop-type VirtualAppliance --next-hop-ip-address 10.1.1.4
az network vnet subnet update --name onpremVM --vnet-name onprem --resource-group VPN --route-table vm-rt
</pre>

**Document the public IPs for the test VMs, CSR and Azure VPN gateways and copy them to notepad. If the public IPs for the Azure VPN gateways return "none", do not continue. The gateways are deployed when they return a public IP.**
<pre lang="...">
az network public-ip show --resource-group VPN --name Azure-VNGpubip1 --query [ipAddress] --output tsv
az network public-ip show --resource-group VPN --name Azure-VNGpubip2 --query [ipAddress] --output tsv
az network public-ip show --resource-group VPN --name CSRPublicIP --query [ipAddress] --output tsv
az network public-ip show --resource-group VPN --name VPNhubVM --query [ipAddress] --output tsv
az network public-ip show --resource-group VPN --name onpremVM --query [ipAddress] --output tsv
</pre>

**Document BGP information for the VPN gateway.**
<pre lang="...">
az network vnet-gateway list --query [].[name,bgpSettings.asn,bgpSettings.bgpPeeringAddress] -o table --resource-group VPN
</pre>

**Build the tunnel connection to the CSR. Replace "CSRPublicIP" with the public IP you copied to notepad. Note- only the /32 of the CSR loopback is allowed across the tunnel. All traffic will be allowed across the tunnel.**
<pre lang="...">
az network local-gateway create --gateway-ip-address "CSRPublicIP" --name to-onprem --resource-group VPN --local-address-prefixes 192.168.1.1/32 --asn 65002 --bgp-peering-address 192.168.1.1
az network vpn-connection create --name to-onprem --resource-group VPN --vnet-gateway1 Azure-VNG -l eastus2 --shared-key Msft123Msft123 --local-gateway2 to-onprem --enable-bgp
</pre>

**SSH to the CSR and paste in the below config. Make sure to change "Azure-VNGpubip1" and "Azure-VNGpubip2" . After this step, the test VMs will be able to reach each other.**
<pre lang="...">
ip route 10.1.10.0 255.255.255.0 10.1.1.1
crypto ikev2 proposal Azure-Ikev2-Proposal 
 encryption aes-cbc-256
 integrity sha1
 group 2
!
crypto ikev2 policy Azure-Ikev2-Policy 
 match address local 10.1.0.4
 proposal Azure-Ikev2-Proposal
!         
crypto ikev2 keyring to-onprem-keyring
 peer "Azure-VNGpubip1"
  address "Azure-VNGpubip1"
  pre-shared-key Msft123Msft123
 !
 peer "Azure-VNGpubip2"
  address "Azure-VNGpubip2"
  pre-shared-key Msft123Msft123
 !
crypto ikev2 profile Azure-Ikev2-Profile
 match address local 10.1.0.4
 match identity remote address "Azure-VNGpubip1" 255.255.255.255 
 match identity remote address "Azure-VNGpubip2" 255.255.255.255 
 authentication remote pre-share
 authentication local pre-share
 keyring local to-onprem-keyring
 lifetime 28800
 dpd 10 5 on-demand

crypto ipsec transform-set to-Azure-TransformSet esp-gcm 256 
 mode tunnel
!
!
crypto ipsec profile to-Azure-IPsecProfile
 set transform-set to-Azure-TransformSet 
 set ikev2-profile Azure-Ikev2-Profile
!
interface Loopback11
 ip address 192.168.1.1 255.255.255.255
!
interface Tunnel11
 ip address 192.168.2.1 255.255.255.255
 ip tcp adjust-mss 1350
 tunnel source 10.1.0.4
 tunnel mode ipsec ipv4
 tunnel destination "Azure-VNGpubip1"
 tunnel protection ipsec profile to-Azure-IPsecProfile
!
interface Tunnel12
 ip address 192.168.3.1 255.255.255.255
 ip tcp adjust-mss 1350
 tunnel source 10.1.0.4
 tunnel mode ipsec ipv4
 tunnel destination "Azure-VNGpubip2"
 tunnel protection ipsec profile to-Azure-IPsecProfile

router bgp 65002
 bgp router-id 192.168.1.1
 bgp log-neighbor-changes
 neighbor 10.0.0.4 remote-as 65001
 neighbor 10.0.0.4 ebgp-multihop 255
 neighbor 10.0.0.4 update-source Loopback11
 neighbor 10.0.0.5 remote-as 65001
 neighbor 10.0.0.5 ebgp-multihop 255
 neighbor 10.0.0.5 update-source Loopback11
 !
 address-family ipv4
  network 10.1.10.0 mask 255.255.255.0
  neighbor 10.0.0.4 activate
  neighbor 10.0.0.5 activate
  maximum-paths 2
 exit-address-family

ip route 10.0.0.4 255.255.255.255 Tunnel11
ip route 10.0.0.5 255.255.255.255 Tunnel12
</pre>

