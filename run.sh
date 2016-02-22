#!/bin/bash

NUM=1

while getopts ":n:" opt; do
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

for i in `seq 1 $NUM`
do
	./__run.sh -l -i $i -b 128 -s 1 &
done
