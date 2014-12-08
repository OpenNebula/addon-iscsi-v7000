# iSCSI Storage Driver for IBM Storwize V7000 SAN

## Description

The iSCSI storage driver for IBM Storwize V7000 SAN provides OpenNebula with the possibility of using V7000 volumes as block devices for VM images. The use of block based storage presents several benefits over image based storage, especially regarding performance. The entire SAN volume management is achieved through the OpenNebula front-end. This driver supports multipathing, replication and failover with two SAN boxes. Only an iSCSI client and multipath setup is required on host side.

## Author

* [Laurent Grawet](mailto:dev@grawet.be)

## Compatibility

This add-on is compatible with OpenNebula 4.6+

## Prerequisites

An optional deployment host is recommended to prepare virtual disks (mkfs, image upload...) but this can be handled by the front-end as well. The benefits are you can take this workload off the front-end and you only have to restart deployment host in case of trouble, not the whole front-end. The deployment host can of course be an OpenNebula VM. You can also decide to use multiple deployment hosts. They will be selected by round-robin like algorithm. If you decide not to use the deployment host(s), its prerequisites apply to the front-end.

### OpenNebula Front-end

- ssh with public key authentication to IBM V7000 for oneadmin user
- flock which is part of util-linux package

flock is used to manage v7000 access concurrency. Only one session will be opened on a single v7000 box at a time.

### OpenNebula Deployment Host(s)

- open-iscsi initiator
- multipath 
- ddpt

ddpt is used to clone to a different target datastore using sparse copy to speed up data transfers. You can still use traditional dd command if you prefer. See the beginning of v7000_script.sh file and set USE_DDPT=0.

### OpenNebula Hosts

- open-iscsi initiator
- multipath

### IBM Storwize V7000

- A oneadmin user with public key authentication
- Registered OpenNebula hosts and deployment host(s) for iSCSI.

## Installation

### OpenNebula Front-End

* Copy these files/directories:
  - datastore/v7000 -> /var/lib/one/remotes/datastore/v7000
  - tm/v7000 -> /var/lib/one/remotes/tm/v7000
* Add "v7000" to "arguments" attribute of TM_MAD and DATASTORE_MAD in /etc/one/oned.conf

  ```
  TM_MAD = [
    executable = "one_tm",
    arguments = "-t 15 -d dummy,lvm,shared,fs_lvm,qcow2,ssh,vmfs,ceph,dev,v7000"
  ]

  DATASTORE_MAD = [
    executable = "one_datastore",
    arguments  = "-t 15 -d dummy,fs,vmfs,lvm,ceph,dev,v7000"
  ]
  ```

* Add the following to the bottom of /etc/one/oned.conf

  ```
  TM_MAD_CONF = [
    name = "v7000", ln_target = "NONE", clone_target = "SELF", shared = "yes"
  ]
  ```

* For live migration, you have to add the following to
  - /var/lib/one/remotes/tm/shared/premigrate

      ```
      DRIVER_PATH=$(dirname $0)
      . ${DRIVER_PATH}/../../tm/v7000/premigrate $1 $2 $3 $4 $5 $6
      ```

  - /var/lib/one/remotes/tm/shared/postmigrate

      ```
      DRIVER_PATH=$(dirname $0)
      . ${DRIVER_PATH}/../../tm/v7000/postmigrate $1 $2 $3 $4 $5 $6
      ```

## Configuration

###Configuring the System Datastore

To use V7000 drivers, you have to configure the system datastore as shared. This sytem datastore will only hold the symbolic links to the block devices, so it will not take much space. See more details on the [System Datastore Guide](http://docs.opennebula.org/4.10/administration/storage/system_ds.html).

It will also be used to hold context images, they will be created as regular files.

### Configuring iSCSI Datastores

The first step to create an iSCSI datastore is to set up a template file for it. In the following table you can see the supported configuration attributes. The datastore type is set by its drivers, in this case be sure to add `DS_MAD=v7000` and `TM_MAD=v7000` for the transfer mechanism, see below. The options regarding V7000 volumes management are detailed in the [IBM SVC and Storwize V7000 V640 CLI Guide](ftp://ftp.software.ibm.com/storage/san/sanvc/V6.4.0/SVC_and_Storwize_V7000_V640_CLI_Guide.pdf).

#### Mandatory configuration attributes

* **NAME**: `[name]` The name of the datastore.
* **DS_MAD**: `[v7000]` The DS type, use v7000 for the V7000 datastore.
* **TM_MAD**: `[v7000]` Transfer driver for the datastore, use v7000, see below
* **BRIDGE_LIST**: `[fqdn]` The deployment host(s) FQDN. Defaults to localhost.localdomain.
* **MGMT** : `[fqdn]` The V7000 master box FQDN. The default value is v7000-master.localdomain.

#### Optionnal configuration attributes

* **BASE_IQN** `[iqn]` The base IQN for V7000 iSCSI target. The default value is iqn.1986-03.com.ibm
* **THIN_PROVISION ** `[1|0]` Activate thin-provisioned volumes. The default value is 1.
* **SNAPSHOT** `[1 | 0]` Use snapshots or clone for non-persistent images. The default value is 1.
* **SNAPSHOT_RSIZE ** `[%]` *(mkvdisk -rsize option)*  Use with SNAPSHOT=1 parameter. Defines how much physical space is initially allocated to the thin-provisioned volume for non persistent image. The default value is 0 %.
* **RSIZE** `[%]` *(mkvdisk -rsize option)* Defines how much physical space is initially allocated to the thin-provisioned volumes for persistent images. The default value is 2 %.
* **COPIES** `[1 | 2]` *(mkvdisk -copies option)* Specifies the number of local volume copies to create. Setting the value to 2 creates a mirrored volume. The default value is 1.
* **IO_GROUP** `[io_grp]` *(mkvdisk -iogrp option)* Specifies the I/O group (node pair) with which to associate volumes. The default value is io_grp0.
* **MDISK_GROUP** `[mdisk_grp]` *(mkvdisk -mdiskgrp option)* Specifies one or more managed disk groups (storage pools) to use when creating volumes. The default value is mdiskgrp0.
* **SYNC_RATE** `[0 - 100]` *(mkvdisk -syncrate option)* Specifies the copy synchronization rate for volumes. A value of zero (0) prevents synchronization. The default value is 50.
* **VTYPE** `[striped]` *(mkvdisk -vtype option)* Specifies the virtualization type. The default virtualization type is striped and it is the only type currently implemented in this driver.
* **COPYRATE** `[0 - 100]` *(mkfcmap -copyrate option)* Specifies the copy rate for the clone mapping. The rate value can be 0 - 100. A value of 0 indicates no background copy process. The default value is 50
* **CLEANRATE** `[0 - 100]` *(mkfcmap -cleanrate option)* Sets the cleaning rate for the clone mapping. The rate value can be 0 - 100. The default value is 50.
* **GRAINSIZE** `[64 | 256]` *(mkfcmap -grainsize option)* Specifies the grain size for the clone mapping. The default value is 256. Once set, this value cannot be changed. The default value is 256

#### Configuration attributes for replication and failover with auxiliary box setup

* **MGMT_AUX** `[fqdn]` The V7000 auxiliary box FQDN for replication. The default value is v7000-aux.localdomain.
* **CLUSTER** `[cluster_id]` The V7000 Cluster ID. The default value is 00000200A0000000.
* **REPLICATION** `[1 | 0]` Used to activate replication one the slave box. The default value is 0.
* **FAILOVER** `[1 | 0]`Use auxiliary volumes instead of master ones on the auxiliary box. Volumes one the auxiliary box become masters. The default value is 0.

#### Configuring v7000 driver options

You can tweak some v7000 driver options inside v7000_script.sh file. The comments are self-explanatory.

### Configuring OpenNebula Hosts and Deployment Host(s)

Firstly you need to know/configure your initiator name, see /etc/iscsi/initiatorname.iscsi. Recommended open-iscsi settings in /etc/iscsi/iscsid.conf are:

```
node.startup = automatic
node.session.timeo.replacement_timeout=15
node.conn[0].timeo.noop_out_interval=5
node.conn[0].timeo.noop_out_timeout=5
```

Secondly you have to configure multipath daemon. Here is the configuration recommended by IBM for /etc/multipath.conf. It is also recommended to blacklist local disks. Here, it is /dev/sda.

```
defaults {
        polling_interval  5
}

devices {
        device{
                vendor          "IBM"
                product         "2145"
                path_grouping_policy  group_by_prio
                features        "1 queue_if_no_path"
                prio            alua
                path_checker    tur
                failback        immediate
                no_path_retry   20
        }
}

blacklist {
        devnode "^td[a-z]"
        devnode "^sda$"
}
```

Finally, configure the following permissions for oneadmin user in /etc/sudoers:

```
oneadmin    ALL=(ALL) NOPASSWD: /usr/bin/iscsiadm, /sbin/multipath, /sbin/dmsetup, /sbin/blockdev, /usr/bin/tee, /sbin/mkfs, /sbin/mkswap, /bin/dd, /usr/bin/ddpt
```

You have to restart open-iscsi and multipath services afterwards.

All is left to do is to register and login to all V7000 nodes with

`iscsiadm -m discovery -t st -p $NODE_IP:3260 --op update -n node.startup -v automatic`

Where \$NODE_IP is the ip of one of your nodes. So you wil have to execute the command for each \$NODE_IP. The settings will be retained and the iSCSI sessions automatically restarted at boot.

### Configuring IBM Storwize V7000

- Create a oneadmin user with public key authentication
- Register IQN of OpenNebula hosts and deployment host(s)

## Usage

I will illustrate the most complete solution: the dual box setup. If you want to achieve active-active setup, you can configure two datastores, one for each box. For each datastore you configure the other box as auxiliary.

Datastore1:
```
MGMT=box1
MGMT_AUX=box2
```
Datastore2:
```
MGMT=box2
MGMT_AUX=box1
```

Whith `REPLICATION=1` a replicated auxiliary volume will be created on `MGMT_AUX`. This volume is read-only, this is inherent to V7000 design. If you loose the master box, you will loose the VMs whose disks are mapped from this box. You can quickly recover by restarting the VMs and make them use the auxiliary volumes simply by setting `FAILOVER=1` datastore option.

Once you have recovered from the incident, you can set back `FAILOVER=0`. All running VMs will continue to use auxiliary volumes but they will switch to master volumes on next deployment. If you decide to create new volumes while `FAILOVER=1`, it is your responsibility to manage replication as soon as the other box is back online.

## Optimizations

You can configure jumbo frames (MTU=9000) on both V7000 and iSCSI initiators. Please, make sure jumbo frames are supported by your network equipment (switches, routers...)
You can also achieve a big performance improvement by using noop I/O scheduler inside VMs and deadline I/0 scheduler on the hosts instead of cfq. Configure it with `elevator=noop` or `elevator=deadline` kernel options.
