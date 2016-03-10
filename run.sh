#!/bin/bash

#MAX_BW=( 318 411 466 503 526 537 543 545 546 546 542 536 )
#MAX_IOPS=( 77754 50235 28445 15379 8028 4101 2073 1041 521 260 129 63 )

MAX_BW=( 0.860987 1.70665 3.34299 6.51125 12.1792 21.817 35.5616 54.364 70.187 83.8244 86.8654 87.1784 )
MAX_IOPS=( 210 208 204 198 185 166 135 103 67 40 20 10 )

get_max_iops(){
	idx=0
	temp=$1;

	while true; do
		if [ $temp = 4 ]
		then
			break;
		fi
		temp=$(($temp / 2))
		idx=$(($idx + 1))
	done

	echo ${MAX_IOPS[$idx]}
}

get_max_bw(){
	idx=0
	temp=$1;

	while true; do
		if [ $temp = 4 ]
		then
			break;
		fi
		temp=$(($temp / 2))
		idx=$(($idx + 1))
	done

	echo ${MAX_BW[$idx]}
}

DEVICE_SIZE=900
NUM=1
OUTPUT_DIR=results
CGROUP_NUM=0

while getopts ":n:c:" opt; do
	case $opt in
		c)
			CGROUP_NUM=$OPTARG
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

BLKSIZE=4
LV_SIZE=$(($DEVICE_SIZE / $NUM))g

if [ ! -e results/$NUM ]
then
	mkdir results/$NUM
fi

if [ $CGROUP_NUM = 0 ]
then
	PROC_PER_CGROUP=$NUM
else
	PROC_PER_CGROUP=$(($NUM / $CGROUP_NUM))
fi


for i in `seq 1 $NUM`
do
	if [ $CGROUP_NUM = 0 ]
	then
		CGROUP_IDX=$i
	else
		CGROUP_IDX=$((($i - 1) / $PROC_PER_CGROUP + 1))
	fi
	BW=$(get_max_bw $BLKSIZE)
	BW=$(echo $BW/$NUM*1000000 | bc -l)
	IOPS=$(get_max_iops $BLKSIZE)
	IOPS=$(($IOPS/$NUM))
	set -x
	#./__run.sh -l -i $i -b $BLKSIZE -s 0 -L $LV_SIZE -t $((160 / $NUM / 2)) -o $OUTPUT_DIR/$NUM -c $CGROUP_IDX -B $BW -I $IOPS  &
	./__run.sh -l -i $i -b $BLKSIZE -s 0 -L $LV_SIZE -t 1 -a $((64 / $NUM)) -o $OUTPUT_DIR/$NUM -c $CGROUP_IDX -B $BW -I $IOPS  &
	#./__run.sh -l -i $i -b $BLKSIZE -s 0 -L $LV_SIZE -t 1 -a $((64 / $NUM)) -o $OUTPUT_DIR/$NUM -c $CGROUP_IDX  &
	#./__run.sh -l -i $i -b $BLKSIZE -s 0 -L $LV_SIZE -t 1 -o $OUTPUT_DIR/$NUM &
	#./__run.sh -l -i $i -b $BLKSIZE -s 0 -L $LV_SIZE -t 1 -a 32 -o results/$NUM &
	set +x
	BLKSIZE=$(($BLKSIZE * 2))
done
