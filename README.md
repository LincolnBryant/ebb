erly boot & build (ebb)
-----------------------

ebb is an experimental platform for provisioning and managing Linux and BSD clusters.

Note: The operative word is *experimental*! It will eat your pets, ruin your homework, `rm -rf --no-preserve-root` your hard drive, etc.

### v1 Goals

ebb aims to be a single application that provisions cluster hardware with a loose focus on HPC workloads. A bit more general than [Warewulf](https://warewulf.org/), a bit less crufty than [XCat](https://xcat.org/), and far less complex than [OpenCHAMI](https://openchami.org/).

For the initial relese, ebb is focused on provisioning, specifically:
  * ipmi (console access)
  * redfish (server configuration) 
  * dhcp (for netbooting, with and without proxy mode)
  * tftp (for delivering iPXE bootstrap)
  * http(s) (for serving OS images)
