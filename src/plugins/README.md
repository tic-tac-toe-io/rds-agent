

| . | Raspbian/RPI3 | Ubuntu1804/BBB |
|---|---|---|
| nodejs(`os.arch!`) | arm | arm |
| nodejs(`os.platform!`) | linux | linux | 
| nodejs(`os.release`) | 4.14.98-v7+ | 4.14.108-ti-r104 |
| `OS_ARCH` (`uname -m`) | armv7l | armv7l |
| `OS_NAME` | linux-raspbian-stretch | linux-ubuntu-bionic |
| `OS_KERNEL` (`uname -s`) | linux | linux |
| `OS_DIST_NAME` (`lsb_release -a 2>/dev/null | grep "^Distributor"`) | raspbian | ubuntu |
| `OS_DIST_CODENAME` (`lsb_release -a | grep "^Codename"`) | stretch | bionic |



## Raspbian/RPI3

`2019-04-08-raspbian-stretch-lite.zip`

### `/proc/cpuinfo`

```text
$ cat /proc/cpuinfo
processor	: 0
model name	: ARMv7 Processor rev 4 (v7l)
BogoMIPS	: 38.40
Features	: half thumb fastmult vfp edsp neon vfpv3 tls vfpv4 idiva idivt vfpd32 lpae evtstrm crc32
CPU implementer	: 0x41
CPU architecture: 7
CPU variant	: 0x0
CPU part	: 0xd03
CPU revision	: 4

processor	: 1
model name	: ARMv7 Processor rev 4 (v7l)
BogoMIPS	: 38.40
Features	: half thumb fastmult vfp edsp neon vfpv3 tls vfpv4 idiva idivt vfpd32 lpae evtstrm crc32
CPU implementer	: 0x41
CPU architecture: 7
CPU variant	: 0x0
CPU part	: 0xd03
CPU revision	: 4

processor	: 2
model name	: ARMv7 Processor rev 4 (v7l)
BogoMIPS	: 38.40
Features	: half thumb fastmult vfp edsp neon vfpv3 tls vfpv4 idiva idivt vfpd32 lpae evtstrm crc32
CPU implementer	: 0x41
CPU architecture: 7
CPU variant	: 0x0
CPU part	: 0xd03
CPU revision	: 4

processor	: 3
model name	: ARMv7 Processor rev 4 (v7l)
BogoMIPS	: 38.40
Features	: half thumb fastmult vfp edsp neon vfpv3 tls vfpv4 idiva idivt vfpd32 lpae evtstrm crc32
CPU implementer	: 0x41
CPU architecture: 7
CPU variant	: 0x0
CPU part	: 0xd03
CPU revision	: 4

Hardware	: BCM2835
Revision	: a02082
Serial		: 00000000f9438fd9
```

**MPU**

```text
$ cat /proc/cpuinfo | grep "^Hardware" | awk -F':' '{print $2}' | sed 's/\ //g'
BCM2835
```

**Model**

```text
$ cat /proc/cpuinfo | grep "^Revision" | awk -F':' '{print $2}' | sed 's/\ //g'
a02082

$ cat /proc/device-tree/model
Raspberry Pi 3 Model B Rev 1.2
```

Refer to [this page](https://www.raspberrypi-spy.co.uk/2012/09/checking-your-raspberry-pi-board-version/) for the list of revisions for all RPI variants.

**Serial Number**

```text
$ awk '/Serial/ {print $3}' /proc/cpuinfo
00000000f9438fd9
```


### lscpu

```text
$ /usr/bin/lscpu
Architecture:          armv7l
Byte Order:            Little Endian
CPU(s):                4
On-line CPU(s) list:   0-3
Thread(s) per core:    1
Core(s) per socket:    4
Socket(s):             1
Model:                 4
Model name:            ARMv7 Processor rev 4 (v7l)
CPU max MHz:           1200.0000
CPU min MHz:           600.0000
BogoMIPS:              38.40
Flags:                 half thumb fastmult vfp edsp neon vfpv3 tls vfpv4 idiva idivt vfpd32 lpae evtstrm crc32
```



## Ubuntu1804/BBB

`bone-ubuntu-18.04.2-console-armhf-2019-04-10-2gb.img.xz`

### `/proc/cpuinfo`

```text
$ cat /proc/cpuinfo
processor	: 0
model name	: ARMv7 Processor rev 2 (v7l)
BogoMIPS	: 995.32
Features	: half thumb fastmult vfp edsp thumbee neon vfpv3 tls vfpd32
CPU implementer	: 0x41
CPU architecture: 7
CPU variant	: 0x3
CPU part	: 0xc08
CPU revision	: 2

Hardware	: Generic AM33XX (Flattened Device Tree)
Revision	: 0000
Serial		: 0000000000000000
```


**MPU**

```text
$ cat /proc/cpuinfo | grep "^Hardware" | awk -F':' '{print $2}' | sed 's/^\ *//g'
Generic AM33XX (Flattened Device Tree)

$ hexdump -e '8/1 "%c"' /sys/bus/i2c/devices/0-0050/eeprom -s 4 -n 8 && echo ""
A335BNLT
```

**Model**

```text
$ hexdump -e '8/1 "%c"' /sys/bus/i2c/devices/0-0050/eeprom -s 12 -n 4 && echo ""
00C0

$ cat /proc/device-tree/model
TI AM335x BeagleBone Black
```

Refer to [this page](https://github.com/beagleboard/image-builder) for the list of revisions for all RPI variants.

**Serial Number**

```text
$ hexdump -e '8/1 "%c"' /sys/bus/i2c/devices/0-0050/eeprom -s 16 -n 12 && echo ""
3615BBBK094A
```



### lscpu

```text
$ /usr/bin/lscpu
Architecture:        armv7l
Byte Order:          Little Endian
CPU(s):              1
On-line CPU(s) list: 0
Thread(s) per core:  1
Core(s) per socket:  1
Socket(s):           1
Vendor ID:           ARM
Model:               2
Model name:          Cortex-A8
Stepping:            r3p2
CPU max MHz:         1000.0000
CPU min MHz:         300.0000
BogoMIPS:            995.32
Flags:               half thumb fastmult vfp edsp thumbee neon vfpv3 tls vfpd32
```


## Nodejs Network Interfaces (`os.networkInterfaces!`)

12.4.0 on ubnutu-bionic-desktop

```json
{
  lo: [
    {
      address: '127.0.0.1',
      netmask: '255.0.0.0',
      family: 'IPv4',
      mac: '00:00:00:00:00:00',
      internal: true,
      cidr: '127.0.0.1/8'
    },
    {
      address: '::1',
      netmask: 'ffff:ffff:ffff:ffff:ffff:ffff:ffff:ffff',
      family: 'IPv6',
      mac: '00:00:00:00:00:00',
      internal: true,
      cidr: '::1/128',
      scopeid: 0
    }
  ],
  enx9cebe8376669: [
    {
      address: '10.42.0.62',
      netmask: '255.255.255.0',
      family: 'IPv4',
      mac: '9c:eb:e8:37:66:69',
      internal: false,
      cidr: '10.42.0.62/24'
    },
    {
      address: 'fe80::7f05:e359:b3eb:ce7d',
      netmask: 'ffff:ffff:ffff:ffff::',
      family: 'IPv6',
      mac: '9c:eb:e8:37:66:69',
      internal: false,
      cidr: 'fe80::7f05:e359:b3eb:ce7d/64',
      scopeid: 2
    }
  ]
}
```

10.16.0 on ubnutu-bionic-desktop

```json
{ lo:
   [ { address: '127.0.0.1',
       netmask: '255.0.0.0',
       family: 'IPv4',
       mac: '00:00:00:00:00:00',
       internal: true,
       cidr: '127.0.0.1/8' },
     { address: '::1',
       netmask: 'ffff:ffff:ffff:ffff:ffff:ffff:ffff:ffff',
       family: 'IPv6',
       mac: '00:00:00:00:00:00',
       scopeid: 0,
       internal: true,
       cidr: '::1/128' } ],
  enx9cebe8376669:
   [ { address: '10.42.0.62',
       netmask: '255.255.255.0',
       family: 'IPv4',
       mac: '9c:eb:e8:37:66:69',
       internal: false,
       cidr: '10.42.0.62/24' },
     { address: 'fe80::7f05:e359:b3eb:ce7d',
       netmask: 'ffff:ffff:ffff:ffff::',
       family: 'IPv6',
       mac: '9c:eb:e8:37:66:69',
       scopeid: 2,
       internal: false,
       cidr: 'fe80::7f05:e359:b3eb:ce7d/64' } ] }
```


8.16.0 on ubnutu-bionic-desktop

```json
{ lo:
   [ { address: '127.0.0.1',
       netmask: '255.0.0.0',
       family: 'IPv4',
       mac: '00:00:00:00:00:00',
       internal: true,
       cidr: '127.0.0.1/8' },
     { address: '::1',
       netmask: 'ffff:ffff:ffff:ffff:ffff:ffff:ffff:ffff',
       family: 'IPv6',
       mac: '00:00:00:00:00:00',
       scopeid: 0,
       internal: true,
       cidr: '::1/128' } ],
  enx9cebe8376669:
   [ { address: '10.42.0.62',
       netmask: '255.255.255.0',
       family: 'IPv4',
       mac: '9c:eb:e8:37:66:69',
       internal: false,
       cidr: '10.42.0.62/24' },
     { address: 'fe80::7f05:e359:b3eb:ce7d',
       netmask: 'ffff:ffff:ffff:ffff::',
       family: 'IPv6',
       mac: '9c:eb:e8:37:66:69',
       scopeid: 2,
       internal: false,
       cidr: 'fe80::7f05:e359:b3eb:ce7d/64' } ] }
```


4.9.1 on ubnutu-bionic-desktop

```json
{ lo:
   [ { address: '127.0.0.1',
       netmask: '255.0.0.0',
       family: 'IPv4',
       mac: '00:00:00:00:00:00',
       internal: true },
     { address: '::1',
       netmask: 'ffff:ffff:ffff:ffff:ffff:ffff:ffff:ffff',
       family: 'IPv6',
       mac: '00:00:00:00:00:00',
       scopeid: 0,
       internal: true } ],
  enx9cebe8376669:
   [ { address: '10.42.0.62',
       netmask: '255.255.255.0',
       family: 'IPv4',
       mac: '9c:eb:e8:37:66:69',
       internal: false },
     { address: 'fe80::7f05:e359:b3eb:ce7d',
       netmask: 'ffff:ffff:ffff:ffff::',
       family: 'IPv6',
       mac: '9c:eb:e8:37:66:69',
       scopeid: 2,
       internal: false } ] }
```