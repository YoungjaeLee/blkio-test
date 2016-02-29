#!/bin/bash

DEVICE_SIZE=440
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

BLKSIZE=4
LV_SIZE=$(($DEVICE_SIZE / $NUM))g

if [ ! -e results/$NUM ]
then
	mkdir results/$NUM
fi

set -x
for i in `seq 1 $NUM`
do
	#./__run.sh -l -i $i -b $BLKSIZE -s 0 -L $LV_SIZE -t $((160 / $NUM / 2)) -o results/$NUM &
	./__run.sh -l -i $i -b $BLKSIZE -s 0 -L $LV_SIZE -t 1 -a 32 -o results/$NUM &
	BLKSIZE=$(($BLKSIZE * 2))
done
