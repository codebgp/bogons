#!/usr/bin/env bash

### USER CONFIGURABLE DATA

# Put here any custom ipv4 prefixes you want to append to the output files
# The format must be an array, e.g:
# MY_IPV4_PREFIXES=("0.0.0.0/8" "10.0.0.0/8")
# If you don't have any prefixes of your own, please leave the array declared
# and empty

MY_IPV4_PREFIXES=()


# Put here any custom ipv6 prefixes you want to append to the output files
# The format must be an array, e.g:
# MY_IPV6_PREFIXES=("::/8" "0100::/64" "2001:2::/48")
# If you don't have any prefixes of your own, please leave the array declared
# and empty

MY_IPV6_PREFIXES=()

function atoi() {
	IP=$1; IPNUM=0
	for (( i=0 ; i<4 ; ++i )); do
		((IPNUM+=${IP%%.*}*$((256**$((3-${i}))))))
		IP=${IP#*.}
	done
	echo $IPNUM
}

function itoa() {
	echo -n $(($(($(($((${1}/256))/256))/256))%256)).
	echo -n $(($(($((${1}/256))/256))%256)).
	echo -n $(($((${1}/256))%256)).
	echo $((${1}%256))
}


# Checks for prerequisites
if ! [ -x "$(command -v bc)" ]; then
  echo 'bc software is missing. Please install bc software...Exiting' >&2
  echo; exit 255;
fi

if ! [ -x "$(command -v iprange)" ]; then
  echo 'iprange software is missing. Please install iprange software...Exiting' >&2
  echo; exit 255;
fi


PWD="$(dirname "$(readlink -f $0)")";
cd ${PWD}

if { set -C; 2>/dev/null >./bsyncripe.lock; }; then
        trap "rm -f ./bsyncripe.lock" EXIT
else
	echo "[${CURRDATE}] $0 already running, or we have a stale lockfile...exiting"; echo; exit 255
fi

mkdir -p backups/
CURRDATE=`date +%d_%b_%G_%H.%M.%S`
BIRDCONFIG="${1}"

# Keep a backups folder with a 15days' history
echo -n "[${CURRDATE}] Cleaning up old backups..."
find backups/ -type f -mtime +15 -delete 2>/dev/null
echo "Done."

# Checks if we have an updated nro-delegated-stats file
echo -n "[${CURRDATE}] Picking old checksum..."
OLDSHASUM=$(ls -latr backups/nro-delegated-stats* 2>/dev/null 1>/dev/null && sha256sum $(ls -latr backups/nro-delegated-stats* | tail -1 |gawk '{print $9}') | gawk '{print $1}')

CCOUNTER=10
FETCHNEWNRO="true"
if ! [ -z ${OLDSHASUM+x} ]; then
 echo "Done."
 # we got checksum of older nro file...
 until [ $CCOUNTER -lt 1 ]; do
   echo -n "[${CURRDATE}] Fetching current checksum of nro-delegated-stats...(${CCOUNTER})..."
   NEWSHASUM=$(curl --connect-timeout 5 -s https://ftp.ripe.net/pub/stats/ripencc/nro-stats/latest/nro-delegated-stats.sha256 | gawk '{print $1}')
   if ! [ -z ${NEWSHASUM+x} ]; then
     # we got new checksum of nro file 
     echo "Done."
     # check them out...
     echo -n "[${CURRDATE}] Comparing checksums..."
     if [ "$OLDSHASUM" == "$NEWSHASUM" ]; then
	FETCHNEWNRO="false"
        echo "Same."
     else
        echo "Different."
     fi
     break;
   else
    echo "Error...retrying in 1 minute"
    sleep 60
    let CCOUNTER-=1
   fi
 done
else
 echo "Absent."
fi

# Picking up the new nro-delegated-stats file
if [ "$FETCHNEWNRO" == "true" ]; then
   COUNTER=10
   until [ $COUNTER -lt 1 ]; do
	echo -n "[${CURRDATE}] Fetching new nro-delegated-stats file...(${COUNTER})..."
	curl --connect-timeout 5 -s https://ftp.ripe.net/pub/stats/ripencc/nro-stats/latest/nro-delegated-stats >| ./backups/nro-delegated-stats-${CURRDATE}.txt
	if [[ $? != 0 ]]; then
		echo "Error...retrying in 1 minute"
    		sleep 60
		let COUNTER-=1
	else
		echo "Done."
		break;
	fi
   done
else 
   echo "[${CURRDATE}] nro-delegated-stats file is the same with the previous one...Exiting gracefully"
   echo; exit 0
fi

# Sorting procedure
if [[ -f "./backups/nro-delegated-stats-${CURRDATE}.txt" ]]; then
 grep -v "|summary" ./backups/nro-delegated-stats-${CURRDATE}.txt >| ./backups/fullbogons-ip-ripe-${CURRDATE}.txt


 # IPV4 extracting, converting and merging/compacting to a.b.c.d/cidr format
 echo -n "[${CURRDATE}] Sorting IPv4 prefixes..."
 echo -n >| ./ipv4-ranges-ripe.txt
 for n in `grep "|ipv4|" ./backups/fullbogons-ip-ripe-${CURRDATE}.txt |grep -E "\|reserved\||\|available\|"`; do

	IPSTART=$(echo \"${n}\"| gawk -F "|" '{print $4}')
	IPSTARTINT="$(atoi ${IPSTART})"
	IPENDINT="$(echo "scale=0;${IPSTARTINT}+$(echo \"${n}\"| gawk -F "|" '{print $5}')-1" | bc)"
	IPEND=$(itoa ${IPENDINT})

	echo "${IPSTART} - ${IPEND}" >> ./ipv4-ranges-ripe.txt
 done

 iprange --merge ./ipv4-ranges-ripe.txt >| ./ipv4-cidr-merged-ripe.txt

 # appending my IPv4 prefixes, if any
 for prefix in ${MY_IPV4_PREFIXES[@]}; do
	echo "${prefix}" >> ./ipv4-cidr-merged-ripe.txt
 done

 # unifying
 cat ./ipv4-cidr-merged-ripe.txt | sort | uniq >| ./ipv4-cidr-merged-ripe-sorted.txt

 echo "Done."


 # IPV6 extracting, converting and merging/compacting to ::/cidr format
 echo -n "[${CURRDATE}] Sorting IPv6 prefixes..."
 grep "|ipv6|" ./backups/fullbogons-ip-ripe-${CURRDATE}.txt |grep -E "\|reserved\||\|available\|"| gawk -F "|" '{print $4"/"$5}' >| ./ipv6-cidr-merged-ripe.txt

 # appending my IPv6 prefixes, if any
 for prefix in ${MY_IPV6_PREFIXES[@]}; do
	echo "${prefix}" >> ./ipv6-cidr-merged-ripe.txt
 done

 # unifying
 cat ./ipv6-cidr-merged-ripe.txt | sort | uniq >| ./ipv6-cidr-merged-ripe-sorted.txt

 echo "Done."

 # ASN ranges 
 echo -n "[${CURRDATE}] Sorting ASNs..."
 echo -n >| ./asn-ranges-ripe.txt

 for n in `grep "|asn|" ./backups/fullbogons-ip-ripe-${CURRDATE}.txt |grep -E "\|reserved\||\|available\|"| gawk -F "|" '{print $4"/"$5}'`; do
	ASNFROM=$(echo "${n}" | gawk -F "/" '{print $1}')
	RANGE=$(echo "${n}" | gawk -F "/" '{print $2}')
	ASNTO="$(echo "scale=0;${ASNFROM}+${RANGE}-1" | bc)"
	if [ $RANGE -gt 1 ]; then
		echo "${ASNFROM}..${ASNTO}" >> ./asn-ranges-ripe.txt
	elif [ $RANGE -eq 1 ]; then
		echo "${ASNFROM}" >> ./asn-ranges-ripe.txt
	fi
 done

 awk 'NR==1{first=$1;last=$1;next} $1 == last+1 {last=$1;next} {print first,last;first=$1;last=first} END{print first,last}' ./asn-ranges-ripe.txt | awk '{for (i=1;i<=NF;i++) if (!a[$i]++) printf("%s%s",$i,FS)}{printf("\n")}' |sed 's/\b\s\b/\.\./g' |sed '$!s/$/,/' |sed -e s/\ // >| ./asn-ranges-ripe-sorted.txt

 echo "Done."

 # Applying prefixes and asn ranges to a bird.conf file, and reloading bird.
 if [ -f "/etc/bird/$1" ]; then
	echo -n "[${CURRDATE}] Editing bird.conf..."

	\cp -f /etc/bird/${BIRDCONFIG} ./backups/${BIRDCONFIG}-${CURRDATE}

	sed -i 's/\/\(.*\)/\/\1{\1,32},/' ./ipv4-cidr-merged-ripe-sorted.txt 
	sed -i 's/\/\(.*\)/\/\1{\1,128},/' ./ipv6-cidr-merged-ripe-sorted.txt
	sed -i '$ s/.$//' ./ipv4-cidr-merged-ripe-sorted.txt
	sed -i '$ s/.$//' ./ipv6-cidr-merged-ripe-sorted.txt
	echo -n "define BOGON_PREFIXES_V4 = [$(cat ./ipv4-cidr-merged-ripe-sorted.txt)];" | paste -sd' ' >| ./ipv4-cidr-merged-ripe-oneline.txt
	echo -n "define BOGON_PREFIXES_V6 = [$(cat ./ipv6-cidr-merged-ripe-sorted.txt)];" | paste -sd' ' >| ./ipv6-cidr-merged-ripe-oneline.txt
	echo -n "define BOGON_ASNS = [$(cat ./asn-ranges-ripe-sorted.txt)];" | paste -sd' ' >| ./asn-ranges-ripe-oneline.txt

	\cp -f ./backups/${BIRDCONFIG}-${CURRDATE} ./backups/${BIRDCONFIG}-${CURRDATE}.bak
	sed -i -ne '/V4MARK/{p;r ipv4-cidr-merged-ripe-oneline.txt' -e ':a;n;/V4MARKEND/!ba};p' ./backups/${BIRDCONFIG}-${CURRDATE}
	sed -i -ne '/V6MARK/{p;r ipv6-cidr-merged-ripe-oneline.txt' -e ':a;n;/V6MARKEND/!ba};p' ./backups/${BIRDCONFIG}-${CURRDATE}
	sed -i -ne '/ASNMARK/{p;r asn-ranges-ripe-oneline.txt' -e ':a;n;/ASNMARKEND/!ba};p' ./backups/${BIRDCONFIG}-${CURRDATE}
	
	echo "Done."

	# Bird reload the new configuration, if applicable
	diff -q /etc/bird/${BIRDCONFIG} ./backups/${BIRDCONFIG}-${CURRDATE} >/dev/null
	if [[ $? == 1 ]]; then
		# files differ
		\cp -f ./backups/${BIRDCONFIG}-${CURRDATE} /etc/bird/${BIRDCONFIG}
		/usr/sbin/birdc conf >/dev/null
        	if [[ $? == 0 ]]; then
        		echo -n "[${CURRDATE}] config OK...reloading routers"
			# You may need to change these commands according to your bird.conf configuration file definitions
			/usr/sbin/birdc reload mp_bgp	
		else
        		echo -n "[${CURRDATE}] Error in config file, restoring previous conf..."
			\cp -f ./${BIRDCONFIG}-${CURRDATE}.bak /etc/bird/${BIRDCONFIG}
        		if [[ $? == 0 ]]; then
				echo "Done."
			else
				echo "ERROR. Ivestigate by yourself."; echo; exit 255
			fi
		fi
	else
		echo "[${CURRDATE}] Files are the same, not reloading bird."
	fi

 fi

 # Clean up the temporary files
 echo -n "[${CURRDATE}] Cleaning up..."
 \rm -f ./ipv4-cidr-merged-ripe-sorted.txt
 \rm -f ./ipv4-cidr-merged-ripe-oneline.txt
 \rm -f ./asn-ranges-ripe.txt
 \rm -f ./asn-ranges-ripe-oneline.txt
 sed -i s/,// ./asn-ranges-ripe-sorted.txt
 \rm -f ./ipv6-cidr-merged-ripe-sorted.txt
 \rm -f ./ipv6-cidr-merged-ripe-oneline.txt
 echo "Done."

else
 echo "[${CURRDATE}] nro-delegated-stats file absent...Exiting"
 echo; exit 255
fi


echo; exit 0
