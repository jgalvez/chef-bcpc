#!/bin/bash
# a script to find which nodes, defined in a cluster definition file
# cluster.txt are responding to ping
COUNT=0
if [[ -f cluster.txt ]]; then
    # fping is fast but might not be available
    if [[ -z `which fping` ]]; then
        # use standard ping instead 
        while read HOSTNAME MACADDR IPADDR ILOIPADDR DOMAIN ROLE; do
            if [[ ! "$HOSTNAME" = end ]]; then
                UP=`ping -c 1 $IPADDR | grep ttl |cut -f4 -d" " | cut -f1 -d":"`
                if [[ ! -z "$UP" ]]; then
                    COUNT=$((COUNT + 1))
                    echo $UP $ROLE
                fi
            fi
        done < cluster.txt                     
    else
        # we can use fping
        while read HOSTNAME MACADDR IPADDR ILOIPADDR DOMAIN ROLE; do
            ALLHOSTS="$ALLHOSTS $IPADDR"
        done < cluster.txt
        UP=`fping -aq $ALLHOSTS 2> /dev/null`
        for H in $UP; do
            COUNT=$((COUNT + 1))
            echo $H
        done
    fi
    echo "$COUNT hosts up"
else
    echo "Warning : no cluster definition (cluster.txt) found"
fi
