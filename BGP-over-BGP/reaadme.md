# Bypassing Expressroute Prefix Limits with "BGP over BGP"+ Split Default Routes- DRAFT
Expressroute currently allows on prem to advertise 4k routes with standard licensing and 10k routes with premium licensing. In rare situations, customers need to send more than 10k prefixes into Azure. IMPORTANT- the complexity of solving this is high and you must have a solid understanding of both on prem and Azure BGP. Specifically FIB/RIB
behavior, next hop BGP requirements and underlay vs overlay forwarding in Azure. The other important aspect of this option is supportability on the customer side as well as
the Azure side. This overview does not cover Expressroute fundamentals or other networking aspects like the built in redundancy or basic forwarding of ER, steering traffic to
an NVA or NVA HA. On top of solving the route limits challenge, this will hopefully help with other creative ideas by "hiding" routes in the NVA for other designs.

**Important Notes**
- ER connectivity already established. The 150 network in this lab is used to simulate one of the 15k prefixes.
- All north/south/east/west traffic must traverse an NVA.
- VNET must use NVA for outbound Internet utilizing Azure's Internet (no forced tunneling for Internet).
- Customer requires advertising 15k non contiguous prefixes and CAN'T SUMMARIZE.
- Traffic load to/from the 15k prefixes is not large.
- An overlay from on prem to the NVA is not allowed.
- Multi-NIC NVA required
- The amount of routes the NVA can support is outside the scope this solution.
- Lab uses public address space for on prem.

**Topology before "BGP over BGP" NOTE- the 150 network is part of the 15k routes and can't be advertised over the BGP session between CE1 and ER. This is a standard NVA deployment.**
![alt text](https://github.com/jwrightazure/lab/blob/master/BGP-over-BGP/basic-er-nva-topo.png)

# A Note on Forced Tunnelling
Forced tunneling will not solve this challenge due to the requirement of the VNET using the NVA for outbound internet. If you advertise 0/0 from on prem, the NVA will receive the route, still use it's guest OS default route to the fabric and the fabric will steer it to on prem. Remember, the VNET must use the NVA and Azure for Internet traffic. Disabling route propagation + plus a 0/0 UDR on the outside NVA interface will work for Internet bound traffic but not for the 15k routes which we discuss next. EX: VM in Azure initiates a connecttion to the Internet, follows the 0/0 UDR to the NVA, the guest OS has a default route out the "outside" interface to the fabric and it will successfully go to the Internet. Remember the customer requirement is to advertise 15k routes from on prem and is running into the 4k/10k prefix adverisement limit from on prem over ER.

# BGP over BGP
To solve this, you could establish a new BGP session between a different on prem device/interface and the NVA using multihop BGP. The new BGP session will advertise the 15k routes from on prem to the NVA only. This makes the 15k prefixes transparent to Azure but visible to the NVA. As a safeguard for a future step, configure a route table for the outside NVA subnet setting the next hop as Internet. Outbound internet from a VM in Azure is successful. The VM will follow it's 0/0 to the NVA, the NVA guest OS has 0/0 pointed to the fabric, the fabric route table has 0/0 next hop Internet. The next section will describe the forwarding issue for traffic initiated from the Azure VM to the 150 network that is part of the 15k prefixes that are advertised over the new BGP multihop adjacency. Another safeguards- static route on the guest OS for 11.11.11.11/32 (BGP multihop address on CE1) points out the "inside" interface to 10.1.1.1. This protects against any possible route recursion. I would also ensure that on prem only advertises 11.11.11.11/32 over the BGP session to ER and not over multihop. You could also disable route propagation on the inside interface as well and have a route table that points the 11.11.11.11 to 10.1.1.1.

**Topology with "BGP over BGP"**
![alt text](https://github.com/jwrightazure/lab/blob/master/BGP-over-BGP/bgp-multihop.png)

# Forwarding issue and resolution
A VM initiates a connection to the internet and it works fine as previously discussed. When a VM initiates a connection to 150.0.0.1, it follows 0/0 to the NVA. I'm using a Cisco CSR in this example. As you can see from the output below, the NVA sees 150.0.0.1/32 (I'm using a /32 for lab purposes only) in it's BGP table. The lookup for that prefix shows the next hop to be the loopback address of CE1 11.11.11.11 which is correct based on multihop mechanics. If you look at the route table of the CSR for destination 11.11.11.11, it points to the fabric next hop of 10.1.1.1 which we previously defined with a guest OS static route earlier. The CSR will forward the packet destin to 150.0.0.1 to 10.1.1.1 which is the fabric and the fabric will drop it because the underlay knows nothing about the 150 prefix. Remember, we are only advertising 11.11.11.11/32 from CE1 to the underlay via ER. To solve this, inject 0/0 from on prem to trick the fabric into forwarding any unknown traffic to on prem. Injecting 0/0 has no impact to steering outbound Internet traffic out the NVA. All prefixes advertised over BGP multihop will follow the same path. 

# NVA Routes
![alt text](https://github.com/jwrightazure/lab/blob/master/BGP-over-BGP/routes.png)

**Summary**
- Summarization would be a better option to solve this problem but not always an option
- Complexity is somewhat high and support could be challenging. Strong knowledge of on prem BGP and Azure networking
- If using this solution, limit your route advertisement to the underlay and include BGP multihop address and 0/0
- Configure a route table on the NVA outside inteface for 0/0 with next hop internet, multi-NIC NVA required
- Configure guest OS with 0/0 pointed to outside fabric address and a static route for the CE1 BGP multihop address out the inside interface to the fabric
- Turn off route propagation on the VM subnet and set a UDR 0/0 for the NVA inside interface
- 15k routes in this scenario is transparent to the fabric
