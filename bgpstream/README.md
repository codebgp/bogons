# BGPStream bogon "extractor"



This script collects all the bogons seen by collectors accessed via [pybgpstream](https://bgpstream.caida.org/docs/tutorials/pybgpstream) (you can configure it to use RIS, routeviews) and saves them in a CSV file.

You need to configure the timeframe in the __setup_rt()__ function.

This script:

- Downloads the [NRO Delegated Stats](https://ftp.ripe.net/pub/stats/ripencc/nro-stats/latest/nro-delegated-stats) file;
- Extracts all of the "reserved" and "available" networks;
- Compares this list to the networks announced as seen by the collectors;
- Saves all the "bogon" announcement in a CSV file with the full AS-Path for later consumption.

This script was written by Massimiliano Stucchi (max@stucchi.ch) as part of research together with Aftab Siddiqui on Bogons for the MANRS Project.

