# Shell Script

This script (`bogons_sync-ripe.sh`) downloads the nro-delegated-stats file from RIPE and retrieves the IPv4/IPv6 prefixes and ASNs that are either available or reserved.
Furthermore, it applies them to bird's default configuration file (bird.conf) as filters.

## Prerequisites

1. bc - An arbitrary precision calculator language. For Ubuntu: `apt-get install bc` 

2. iprange - manage IP ranges. For Ubuntu: `apt-get install iprange` 

## Use

The script without any arguments (e.g. `./bogons-sync-ripe.sh`), outputs 4 files: ASN numbers in the form of ranges (`asn-ranges-ripe-sorted.txt`), and IPv4/IPv6 prefixes in various formats (`ipv4-cidr-merged-ripe.txt`, `ipv4-ranges-ripe.txt` and `ipv6-cidr-merged-ripe.txt`), allowing the user to feed the script's output in the routing daemon of choice.

If the script is run with parameter the config file of bird (e.g. `./bogons-sync-ripe.sh bird.conf`),
it checks if the configuration file exists in the default path `/etc/bird/bird.conf`, and applies the outpout in the form of filters.

## Cron

A cronjob that runs every hour, with script outputs appended to a log file:

```
0 * * * * /root/bogons-sync-ripe/bogons_sync-ripe.sh bird.conf | tee -a /root/bogons-sync-ripe/output.log 2>&1 2>>/root/bogons-sync-ripe/bogons_sync-ripe.err 1>/dev/null
```

# Bird's configuration file

This file (`bird.conf`) can be used as guide in order to configure your Route Collector, if you choose to use bird 2 as your routing daemon.

## Note:
Because of the thousands of prefixes and ASNs which are generated by the bash script and in order for all of them to be set as bird's filters fast and in the proper place, the lines in bird.conf which contain the ASN numbers as well as the IPV4/IPV4 prefixes have to be between commented marks, e.g.:

```
# ASNMARK <------------
define BOGON_ASNS = [];
# ASNMARKEND	<-----------
```
```
# V4MARK <------------
define BOGON_PREFIXES_V4 = [];
# V4MARKEND	<-----------
```
```
# V6MARK <------------
define BOGON_PREFIXES_V6 = [];
# V6MARKEND	<-----------
```
 
Feel free to raise a PR with any improvements/additions! :)

Ioannis E. Paterakis (jpat@codebgp.com) and Lefteris Manassakis (lefteris@codebgp.com), CodeBGP.
