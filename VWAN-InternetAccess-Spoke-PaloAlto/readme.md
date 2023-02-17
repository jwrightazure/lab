# Azure Networking Lab- VWAN with Internet access through load balanced Palo Alto Firewalls in a spoke.

This lab illustrates how to build a basic VWAN environment with Internet access provided by a load balanced pair of Palo Alto Firewalls in the spoke. The same principles apply if you were to use other vendor's NVA in the spoke in place of PAN. All Azure configs are done in Azure CLI so you can change them as needed to match your environment. Note- VM username is "azureuser" and passwords are "Msft123Msft123". The VM in Spoke2 will have outbound Internet access through the FWs in Spoke1. VWAN Hub is injecting a default route out all of the connections with a next hop of the Azure Load Balancer. The FW is providing NAT functionality which will map to it's public IP associated with the Trust NIC. In order to test connectivity, you will need to console/Bastion into the VM in Spoke2 to test access or apply a UDR with your source IP to next hop Internet. 

# Base Topology
![alt text](https://github.com/jwrightazure/lab/blob/master/images/VWAN-DualPAN-topo.PNG)

**Build Resource Groups, VNETs and Subnets. Change SourceIP to reflect your source IP**
<pre lang="...">
##Variables#
RG="VWAN-PAN-Lab"
Location="eastus2"
hubname="vhub1"
SourceIP="x.x.x.x/32"
</pre>

**Before deploying PAN, you may have to accept license agreement unless you have used it before. You can accomplish this through deploying PAN in the portal or Powershell/Azure CLI commands via Cloudshell**
<pre lang="...">
Sample Azure CLI:
az vm image terms accept --urn paloaltonetworks:vmseries-flex:byol:latest
</pre>

##Create RG and VWAN Hub
<pre lang="...">
az group create --name VWAN-PAN-Lab --location $Location
az network vwan create --name VWAN --resource-group $RG --branch-to-branch-traffic true --location $Location
az network vhub create --address-prefix 192.168.0.0/24 --name $hubname --resource-group $RG --vwan VWAN --location $Location --sku basic
</pre>

##Create Spoke 1 and Spoke 2. Spoke 1 will have the FW providing outbound Internet access. Spoke 2 will have the test VM.
<pre lang="...">
az network vnet create --resource-group $RG --name Spoke1 --location $Location --address-prefixes 10.1.0.0/16 --subnet-name Spoke1VM --subnet-prefix 10.1.10.0/24
az network vnet subnet create --address-prefix 10.1.0.0/24 --name FirewallSubnet --resource-group $RG --vnet-name Spoke1
az network vnet subnet create --address-prefix 10.1.1.0/24 --name LBnet --resource-group $RG --vnet-name Spoke1
az network vnet subnet create --address-prefix 10.1.2.0/24 --name Mgmt --resource-group $RG --vnet-name Spoke1

az network nsg create --resource-group $RG --name PAN-NSG --location $Location
az network nsg rule create --resource-group $RG --nsg-name PAN-NSG --name PAN-NSG --access Allow --protocol "*" --direction Inbound --priority 100 --source-address-prefix 10.0.0.0/8 --source-port-range "*" --destination-address-prefix "*" --destination-port-range "*"
az network nsg rule create --resource-group $RG --nsg-name PAN-NSG --name SSH --access Allow --protocol "TCP" --direction Inbound --priority 200 --source-address-prefix "*" --source-port-range "*" --destination-address-prefix "*" --destination-port-range "22"
az network nsg rule create --resource-group $RG --nsg-name PAN-NSG --name HTTPS --access Allow --protocol "TCP" --direction Inbound --priority 300 --source-address-prefix "*" --source-port-range "*" --destination-address-prefix "*" --destination-port-range "443"
az network nsg rule create --resource-group $RG --nsg-name PAN-NSG --name Azure --access Allow --protocol "*" --direction Inbound --priority 400 --source-address-prefix AzureCloud.EastUS --source-port-range "*" --destination-address-prefix "*" --destination-port-range "*"

az network lb create --name PAN-LB --resource-group $RG --sku Standard --private-ip-address 10.1.1.100 --subnet LBnet --vnet-name Spoke1
az network lb address-pool create --resource-group $RG --lb-name PAN-LB --name PAN-backendpool
az network lb probe create --resource-group $RG --lb-name PAN-LB --name myHealthProbe --protocol tcp --port 22
az network lb rule create --resource-group $RG --lb-name PAN-LB -n MyHAPortsRule  --protocol All --frontend-port 0 --backend-port 0 --backend-pool-name PAN-backendpool --probe-name myHealthProbe

az network route-table create --name PAN-RT --resource-group $RG --location $Location
az network route-table route create --resource-group $RG --name to-Internet --route-table-name PAN-RT --address-prefix 0.0.0.0/0 --next-hop-type Internet
az network vnet subnet update --name FirewallSubnet --vnet-name Spoke1 --resource-group $RG --route-table PAN-RT
az network vnet subnet update --name Mgmt --vnet-name Spoke1 --resource-group $RG --route-table PAN-RT

# Create a Palo Alto firewalls in the hub VNET
az network public-ip create --name PAN1MgmtIP --resource-group $RG --idle-timeout 30 --sku Standard
az network public-ip create --name PAN1-Trust-PublicIP --resource-group $RG --idle-timeout 30 --sku Standard
az network nic create --name PAN1MgmtInterface --resource-group $RG --subnet Mgmt --vnet-name Spoke1 --public-ip-address PAN1MgmtIP --private-ip-address 10.1.2.4 --ip-forwarding true --network-security-group PAN-NSG
az network nic create --name PAN1TrustInterface --resource-group $RG --subnet FirewallSubnet --vnet-name Spoke1 --private-ip-address 10.1.0.4 --ip-forwarding true --lb-name PAN-lb --lb-address-pools PAN-backendpool --network-security-group PAN-NSG --public-ip-address PAN1-Trust-PublicIP 
az vm create --resource-group $RG --location $Location --name PAN1 --size Standard_D3_v2 --nics PAN1MgmtInterface PAN1TrustInterface  --image paloaltonetworks:vmseries-flex:byol:latest --admin-username azureuser --admin-password Msft123Msft123 --no-wait

az network public-ip create --name PAN2MgmtIP --resource-group $RG --idle-timeout 30 --sku Standard
az network public-ip create --name PAN2-Trust-PublicIP --resource-group $RG --idle-timeout 30 --sku Standard
az network nic create --name PAN2MgmtInterface --resource-group $RG --subnet Mgmt --vnet-name Spoke1 --public-ip-address PAN2MgmtIP --private-ip-address 10.1.2.5 --ip-forwarding true --network-security-group PAN-NSG
az network nic create --name PAN2TrustInterface --resource-group $RG --subnet FirewallSubnet --vnet-name Spoke1 --private-ip-address 10.1.0.5 --ip-forwarding true --lb-name PAN-lb --lb-address-pools PAN-backendpool --network-security-group PAN-NSG --public-ip-address PAN2-Trust-PublicIP 
az vm create --resource-group $RG --location $Location --name PAN2 --size Standard_D3_v2 --nics PAN2MgmtInterface PAN2TrustInterface  --image paloaltonetworks:vmseries-flex:byol:latest --admin-username azureuser --admin-password Msft123Msft123 --no-wait

az network vnet create --resource-group $RG --name Spoke2 --location $Location --address-prefixes 10.2.0.0/16 --subnet-name Spoke2VM --subnet-prefix 10.2.10.0/24
az network public-ip create --name Spoke2VMPubIP --resource-group $RG --location $Location --allocation-method Dynamic
az network nic create --resource-group $RG -n Spoke2VMNIC --location $Location --subnet Spoke2VM --vnet-name Spoke2 --public-ip-address Spoke2VMPubIP --private-ip-address 10.2.10.4
az VM create -n Spoke2VM --resource-group $RG --image UbuntuLTS --admin-username azureuser --admin-password Msft123Msft123 --nics Spoke2VMNIC --no-wait

az network route-table create --name Spoke2-RT --resource-group $RG --location $Location
az network route-table route create --resource-group $RG --name to-Internet --route-table-name Spoke2-RT --address-prefix $SourceIP --next-hop-type Internet
az network vnet subnet update --name Spoke2VM --vnet-name Spoke2 --resource-group $RG --route-table Spoke2-RT
</pre>

##Check VWAN hub routing status. Do not proceed until the service is provisioned.
<pre lang="...">
az network vhub show -g $RG -n $hubname --query 'routingState' -o tsv
</pre>

##Create connections from the VWAN hub to each spoke. Inject 0/0 into the fabric pointing to next hop of the private IP of the CSR in Spoke1.
<pre lang="...">
connname=to-spoke1
az network vhub connection create --name to-Spoke1 --resource-group $RG --remote-vnet Spoke1 --vhub-name $hubname
az network vhub connection create --name to-Spoke2 --resource-group $RG --remote-vnet Spoke2 --vhub-name $hubname 
connid=$(az network vhub connection show -g $RG -n to-Spoke1 --vhub-name $hubname --query id -o tsv)
az network vhub route-table route add --name defaultRouteTable --vhub-name $hubname --resource-group $RG --route-name default --destination-type CIDR --destinations "0.0.0.0/0" --next-hop-type ResourceID --next-hop $connid
vnetid=$(az network vnet show -g $RG -n Spoke1 --query id --out tsv)
az network vhub connection create --name to-Spoke1 --resource-group $RG --remote-vnet $vnetid --vhub-name $hubname --route-name default --address-prefixes "0.0.0.0/0" --next-hop "10.1.1.100"
</pre>

##Document the FW management IP
<pre lang="...">
az network public-ip show --resource-group $RG -n PAN1MgmtIP --query "{address: ipAddress}"
</pre>


**Repo has 2 FW XML configuration files. Apply configuration to the appropriate FW**
- Download Firewall XML file for PAN1 and PAN2: 
- HTTPS to the firewall 1
- Select Device tab
- Select Operations tab
- Select Import Named Configuration Snapshot. Upload the appropriate XML files in this repo.
- Select Load Named Configuration Snapshot. Select the firewall XML you previously uploaded.
- Select Commit (top right) and then commit the configuration
- Repeat process for firewall 2

##From the VM in Spoke2, curl ipconfig.io. The output should be the public IP of either FW.
<pre lang="...">
az network public-ip show --resource-group $RG -n Spoke2VMPubIP --query "{address: ipAddress}"
az network public-ip show --resource-group $RG -n PAN1-Trust-PublicIP --query "{address: ipAddress}"
az network public-ip show --resource-group $RG -n PAN2-Trust-PublicIP --query "{address: ipAddress}"
</pre>
