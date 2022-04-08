# VM Provisioning

## Sypnosis

This script automates the process of provisioning server as well as hardening.

## Description

### COD VM Provisioning part currently supports:
* identify and automatically connects to vCenter
* identify esx host with lowest memory usage on specified cluster
* identify datastore with largest free space on specified cluster
* create vm from manually sysprep-ed template from wintel (olan)
* using oscustomizationspec to configure administrator account, time, etc
* assign vCPU & vRAM accordingly
* enable hot add functionality
* automatically identify network adapter from ip provided
* assign vNIC (production/backup) if any
* assign additional disk(s) if any
* generate a dynamic script for hardening the vm
* update vmtools if needed
* can be use against multiple vcenter
* utilize custom attribute for virtual machine details

### COD VM Hardening part currently supports:
* rename production/backup adapter if any
* assign ip configuration accordingly if any
* disable firewall services and policy
* initialize & online RAW disk if any
* currently only supports vDisk, no physical RDM yet
* activate trend micro deep security agent

# Pre-requisites

## VMWare PowerCLI Modules Installed

```powershell
Install-Module -Name VMware.PowerCLI -Scope CurrentUser
```

## Comma separated value (.csv) File with VM details

**vm-provision-list.csv** with VM details inside the same folder containing these values:-

Auto-filled in list *"eCIRF - View Request.csv"* can be downloaded at [Approved CIRF - FOR COD USE ONLY Tab]

Simply rename this file to *"vm-provision-list.csv"* and put in the same folder as script

### 1.  Required

#### **Required** Information are essential for Automated VM Provisioning to succeeed.

* Farm - Determines which **vCenter** to provision, need to provide valid **credential** for each **vCenter/Farm** specified
* Name - **Unique** Virtual Machine Name, duplicates/existing VM name cannot be used
* Template - Template existing at vCenter/Farm. Non-existing of Template will result in a provisioning failure
* Cluster - Cluster existing at vCenter/Farm. Non-existing of Template will result in a provisioning failure
* Tier - The storage tier, acceptable value is **Standard, Performance, High Performance, Super High Performance**
* vCPU - The amount of virtual **CPU** for the server
* vRAM - The amount of virtual **Memory** for the server

| Farm | Name | Template | Cluster | Tier | vCPU | vRAM |
| ------ | ------ | ------ | ------ | ------ | ------ | ------ |
| CISCO UCS | VM1 | TPLT_2019 | Common Production | Standard | 4 | 8 |
| DR COMMON SAP | VM2 | TPLT_2016 | COMMON & SAP | Performance | 4 | 8 |

### 2.  Optional

#### **Optional** Information are for bypassing automated checks or to ensure hardening process completed till the end

* Folder - Project/Application Name of the request
* VMHost - Used as a bypass in some cases
* Datastore - Used as a bypass in some cases
* vDiskCount - Total count of any additional disk other than C,E,U
* DiskSize[i] - Additional disk respective size in GB (currently only vDisk is supported)
* ProductionIP - To ensure complete hardening process
* BackupIP - To ensure complete hardening process
* ProductionNIc - Used a bypass for some cases
* BackupNIC - Used a bypass for some cases

| Folder | VMHost | Datastore | vDiskCount | DiskSize1 | DiskSize2 | ProductionIP | BackupIP | ProductionNIC | BackupNIC |
| ------ | ------ | ------ | ------ | ------ | ------ | ------ | ------ | ------ |  ------ |
| ... | ... | ... | ... | ... | ... | ... | ... | ... | ... |


### 3.  Custom Attributes

#### Information for billing purposes and other details

| eCIRF Number | Project Name | PSR | Cost Center | Custodian | Requester | SR Number |
| ------ | ------ | ------ | ------ | ------ | ------ | ------ |
| ... | ... | ... | ... | ... | ... | ... |

## Error

### For any error, please email me and attach the transcript .log located inside the log folder
