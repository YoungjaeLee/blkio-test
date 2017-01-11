#!/bin/bash

# SSD READ
MAX_BW=( 318 411 466 503 526 537 543 545 546 546 542 536 )
MAX_IOPS=( 77754 50235 28445 15379 8028 4101 2073 1041 521 260 129 63 )

# SSD WRITE
#MAX_BW=( 282.5	349.433	378.951	392.372	389.263	381.079	381.317	378.926	379.356	378.519	380.5	375.015 )
#MAX_IOPS=( 68969.7	42655.4	23129.3	11974.2	5939.68	2907.4	1454.61	722.743	361.782	180.492	90.7182	44.7052 )

# HDD READ
#MAX_BW=( 0.860987 1.70665 3.34299 6.51125 12.1792 21.817 35.5616 54.364 70.187 83.8244 86.8654 87.1784 )
#MAX_IOPS=( 210 208 204 198 185 166 135 103 67 40 20 10 )

# HDD WRITE
#MAX_BW=( 0.933898	1.69038	3.14997	5.86995	10.8987	19.1206	32.0104	50.2669	66.9928	80.5205	86.2144	84.1498 )
#MAX_IOPS=( 228.002 206.346 192.259	179.137	166.301	145.879	122.11	95.8765	63.8893	38.3952	20.5551	10.0314 )


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

DEVICE_SIZE=440
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
	IOPS=$(echo $IOPS/$NUM | bc -l)
	#IOPS=$(($IOPS/$NUM))
	set -x
	./__run.sh -l -i $i -b $BLKSIZE -s 0 -L $LV_SIZE -t $((160 / $NUM / 2)) -o $OUTPUT_DIR/$NUM -c $CGROUP_IDX -B $BW -I $IOPS  &
	#./__run.sh -r 0 -l -i $i -b $BLKSIZE -s 0 -L $LV_SIZE -t 1 -a $((64 / $NUM)) -o $OUTPUT_DIR/$NUM -c $CGROUP_IDX -B $BW -I $IOPS  &
	#./__run.sh -l -i $i -b $BLKSIZE -s 0 -L $LV_SIZE -t 1 -a $((64 / $NUM)) -o $OUTPUT_DIR/$NUM -c $CGROUP_IDX  &
	#./__run.sh -l -i $i -b $BLKSIZE -s 0 -L $LV_SIZE -t 1 -o $OUTPUT_DIR/$NUM &
	#./__run.sh -l -i $i -b $BLKSIZE -s 0 -L $LV_SIZE -t 1 -a 32 -o results/$NUM &
	set +x
	BLKSIZE=$(($BLKSIZE * 2))
done
