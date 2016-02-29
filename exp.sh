#!/bin/bash

NUM=1

while getops ":n:" opt; do
	case $opt in
		n)
			NUM=$OPTARG
			;;
		:)
			echo "Option -$OPTARG requires an argument."
			exit 1;
		;;
	esac
done

set -x
for i in `seq 1 $NUM`
do
	./run.sh -n $i
	sleep 300
	./kill.sh
	sleep 60
done
