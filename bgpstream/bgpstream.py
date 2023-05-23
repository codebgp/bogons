#!/usr/bin/env python3

import csv
import pybgpstream
import radix
import requests

from netaddr import IPAddress, IPNetwork, IPRange

from requests.adapters import HTTPAdapter
from requests.packages.urllib3.util.retry import Retry

retry_strategy = Retry(
    total=8,
    status_forcelist=[429, 500, 502, 503, 504],
    allowed_methods=["HEAD", "GET", "OPTIONS"]
)


def add_pfx(rt, prefix, as_path, origin):
    # Add a prefix to the radix tree containing the routing table

    # First, let's see if the entry already exists.
    # It it exists, we just add the new AS-Path to the list;
    # If it does not exist, we add the whole entry

    rnode = rt.search_exact(prefix)

    if not rnode:
        # No entry found, let's create it and populate it

        rnode = rt.add(prefix)

        rnode.data["as-paths"] = []
        rnode.data["as-paths"].append(as_path)
        
        rnode.data["origins"] = []
        rnode.data["origins"].append(origin)

    else:
        # Simply add data to the lists we should already find

        rnode.data["as-paths"].append(as_path)
        rnode.data["origins"].append(origin)


def pfx_lookup(rt, prefix):
    # Return all the prefixes we find and their data

    rnodes = rt.search_covered(prefix)
    
    # We return 
    if len(rnodes) > 0:
        output = []
        for node in rnodes:
            output.append({"prefix": node.prefix, "as-paths": node.data["as-paths"]})
        
        return(output)

def setup_rt(rt4, rt6):
    stream = pybgpstream.BGPStream(
        from_time="2022-08-01 00:00:01",
        until_time="2022-08-01 23:59:00",
        collectors=["rrc13", "rrc04"],
        record_type="ribs",
    )
    stream.set_data_interface_option("broker", "cache-dir", "./cache")

    num_entries_4 = 0
    num_entries_6 = 0
    
    for rec in stream.records():
        for elem in rec:
        # rib|R|1438416000.000000|ris|rrc00|None|None|4608|203.119.76.5|2.21.94.0/23|203.119.76.5|4608 1221 4637 6453 34164 34164||None|None
            #print (elem.fields)
            origin = elem.fields["as-path"].split()[-1]
            
            if IPNetwork(elem.fields['prefix']).version == 4:
                add_pfx(rt4, elem.fields['prefix'], elem.fields["as-path"], origin)
                num_entries_4 +=1
            else:
                add_pfx(rt6, elem.fields['prefix'], elem.fields["as-path"], origin)
                num_entries_6 +=1

    print("{} v4 and {} v6 entries added".format(num_entries_4, num_entries_6))

def remove_prepends(as_path):
    asns = as_path.split()

    previous = ""

    counter = 0

    output = ""

    for asn in asns:
        if asn != previous:
            previous = asn
            output += "{} ".format(asn)
        else:
            next

    return(output)

def calculate_cidrs(prefix, num_hosts):

    startip = IPAddress(prefix)
    endipint = int(startip) + int(num_hosts) -1
    endip = IPAddress(endipint)
    ranges = IPRange(startip, endip)
    
    return ranges.cidrs()



def main():

    rt4 = radix.Radix()
    rt6 = radix.Radix()
    
    print("Starting setup")

    setup_rt(rt4, rt6)

    print("Setup over")

    q = requests.Session()
    
    url = 'https://ftp.ripe.net/pub/stats/ripencc/nro-stats/latest/nro-delegated-stats'
    r = q.get(url)
    
    content = r.content.decode('utf-8')

    print("Starting to check CSV entries")
    reader = csv.reader(content.splitlines(), delimiter='|')
    
    entries = list(reader)
    
    file_output = ""

    # ['afrinic', 'ZZ', 'ipv4', '212.122.224.0', '8192', '20230202', 'reserved', 'afrinic', 'e-stats']

    for entry in entries:
        if entry[2] == "ipv4":
            try:
                if entry[6] == "available" or entry[6] == "reserved":
                    networks = calculate_cidrs(entry[3], entry[4])

                    for network in networks:
                        routes = pfx_lookup(rt4, str(network))
                        
                        
                        if routes:
                            for route in routes:
                                as_path_output = ""
                                
                                for as_path in route["as-paths"]:
                                    to_append = remove_prepends(as_path)
                                    as_path_output += "'{}',".format(to_append)

                                #aspath = route["as_path"].split()
                                #origin = aspath[-1]

                                if len(as_path_output) > 0:
                                    file_output += "{},{},{}\n".format(route["prefix"], entry[6], as_path_output[:-1])

            except Exception as e:
                print("Error: {}".format(e))
                #next
    
    print("Finished preparing output.")
    print("Saving data to file")
    with open("bogon_as_paths.csv",'w') as outfile:
        outfile.write(file_output)
    print("Data saved.  Done.")
            
if __name__ == "__main__":

    main()


