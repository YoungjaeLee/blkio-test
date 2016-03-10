#!/bin/bash

NUM=1
S=1

while getopts ":s:n:" opt; do
	case $opt in
		s)
			S=$OPTARG
			;;
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
for i in `seq $S $NUM`
do
	./run.sh -n $i
	sleep 300
	./kill.sh
	sleep 60
done
