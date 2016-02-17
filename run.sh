#!/bin/bash

while getopts ":n:t" opt; do
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
	./__run.sh -l -i $i -b 128 &
done
