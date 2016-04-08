#!/bin/bash

IDX=0
DEV_BW=400
DEV_IOPS=50000
DEV_SIZE=440

DEV="8:16"

SPRBYTES=0
SPWBYTES=0
SPRIOP=0
SPWIOP=0
BPRBYTES=0
BPWBYTES=0
BPRIOP=0
BPWIOP=0

while getopts ":s:b:" opt; do
	case $opt in
		s)
			S_USERS=$OPTARG
			;;
		b)
			B_USERS=$OPTARG
			;;
		:)
			"Option -$OPTARG requires an argument." >&2
			exit 1
			;;
		\?)
			echo "Invalid options: -$OPTARG." >&2
			exit 1
			;;
	esac
done

OUTPUT_DIR=S$S_USERS-B$B_USERS
USERS=$(($S_USERS + $B_USERS))

BW=$(echo "scale=0; $DEV_BW/$S_USERS" | bc -l)
IOPS=$(echo "scale=0; $DEV_IOPS/$S_USERS" | bc -l)
VOL=$(echo "scale=0; $DEV_SIZE / $USERS" | bc -l)

TOTAL_S_BW_REQ=0
TOTAL_S_IOPS_REQ=0
ID=0
for i in `seq 1 $S_USERS`
do
	while true
	do
		if [ -e .meta/S$ID.pid ]
		then
			ID=$(($ID + 1))
		else
			break
		fi
	done

	#./create_user.sh -i S$i -L 10g -o $OUTPUT_DIR -s 0 -r 100 -a 16 -C S -b 4 -B $BW -I $IOPS &
	./create_user.sh -i S$ID -L 10g -o $OUTPUT_DIR -s 0 -r 100 -t 4 -C S -b 8 -B $BW -I $IOPS &
	TOTAL_S_BW_REQ=$(($TOTAL_S_BW_REQ+$BW))
	TOTAL_S_IOPS_REQ=$(($TOTAL_S_IOPS_REQ+$IOPS))
	ID=$(($ID + 1))
done

B_BW_LIMIT=0
B_IOPS_LIMIT=0
ID=0
for i in `seq 1 $B_USERS`
do
	while true
	do
		if [ -e .meta/B$ID.pid ]
		then
			ID=$(($ID + 1))
		else
			break
		fi
	done

	#./create_user.sh -i B$i -L 10g -o $OUTPUT_DIR -s 0 -r 100 -a 16 -C B -b 4 -B $BW -I $IOPS &
	./create_user.sh -i B$i -L 10g -o $OUTPUT_DIR -s 0 -r 100 -t 4 -C B -b 32 -B $BW -I $IOPS &
	B_BW_LIMIT=$(($B_BW_LIMIT+$BW))
	B_IOPS_LIMIT=$(($B_IOPS_LIMIT+$IOPS))
	ID=$(($ID + 1))
done

PREV_B_IOPS_LIMIT=-1
PREV_B_BW_LIMIT=-1

if [ -e .meta/monitor ]
then
	exit 0
fi

touch .meta/monitor

while true
do
	STAT=$(grep $DEV /root/cgroupv2/Shared/io.stat)
	if [ -z "$STAT" ]
	then
		continue
	fi
	IFS='\ =' read -ra VAL <<< "$STAT"
	#8:16 rbytes 205180092416 wbytes 0 rios 25046398 wios 0

	SRBYTES=${VAL[2]}
	SWBYTES=${VAL[4]}
	SRIOP=${VAL[6]}
	SWIOP=${VAL[8]}

	STAT=$(grep $DEV /root/cgroupv2/BE/io.stat)
	if [ -z "$STAT" ]
	then
		continue
	fi
	IFS='\ =' read -ra VAL <<< "$STAT"

	BRBYTES=${VAL[2]}
	BWBYTES=${VAL[4]}
	BRIOP=${VAL[6]}
	BWIOP=${VAL[8]}

	SRBW=$(echo "scale=0; ($SRBYTES-$SPRBYTES)/1000000" | bc -l)
	#SRIOPS=$(echo "($SRIOP-$SPRIOP)/1000" | bc -l)
	SRIOPS=$(echo "($SRIOP-$SPRIOP)" | bc -l)
	SPRBYTES=$SRBYTES
	SPRIOP=$SRIOP

	BRBW=$(echo "scale=0; ($BRBYTES-$BPRBYTES)/1000000" | bc -l)
	#BRIOPS=$(echo "($BRIOP-$BPRIOP)/1000" | bc -l)
	BRIOPS=$(echo "($BRIOP-$BPRIOP)" | bc -l)
	BPRBYTES=$BRBYTES
	BPRIOP=$BRIOP

	echo "Shared users: read $SRBW MB/s $SRIOPS IOPS"
	echo "BE users: read $BRBW MB/s $BRIOPS IOPS"

	TOTAL_RBW=$(($SRBW+$BRBW))
	TOTAL_RIOPS=$(($SRIOPS+$BRIOPS))

	LIMIT_CHECK=0
	LT=$(echo "scale=0; ($TOTAL_S_BW_REQ * 0.9)/1" | bc -l) 
	HT=$(echo "scale=0; ($TOTAL_S_BW_REQ * 1)/1" | bc -l)
	if [ $SRBW -lt $LT ]
	then
		B_BW_LIMIT=$((($TOTAL_RBW-$TOTAL_S_BW_REQ) / 10 ))
		B_BW_LIMIT=$(($B_BW_LIMIT * 10))

		if [ $B_BW_LIMIT -lt 1 ]
		then
			B_BW_LIMIT=1
		fi
		B_IOPS_LIMIT=$(($B_BW_LIMIT * 256))
		LIMIT_CHECK=1
	elif [ $SRBW -gt $HT ]
	then
		#B_BW_LIMIT=$(($B_BW_LIMIT * 2))
		B_BW_LIMIT=$(($B_BW_LIMIT + 10))
		B_IOPS_LIMIT=$(($B_BW_LIMIT * 256))
	fi

	LT=$(echo "scale=0; ($TOTAL_S_IOPS_REQ * 0.9)/1" | bc -l)
	if [ $SRIOPS -lt $LT ]
	then
		B_IOPS_LIMIT=$((($TOTAL_RIOPS-$TOTAL_S_IOPS_REQ) / 10 ))
		B_IOPS_LIMIT=$(($B_IOPS_LIMIT * 10))
		if [ $B_IOPS_LIMIT -lt 256 ]
		then
			B_IOPS_LIMIT=256
		fi
		B_BW_LIMIT=$((B_IOPS_LIMIT / 256))
	#else
		#if [ $LIMIT_CHECK != 1 ]
		#then
			#B_IOPS_LIMIT=$(($B_IOPS_LIMIT * 2))
		#fi
	fi

	if [ $PREV_B_IOPS_LIMIT != $B_IOPS_LIMIT ] 
	then
		set -x
		echo "$DEV rbps=$(($B_BW_LIMIT * 1024 * 1024)) riops=$B_IOPS_LIMIT" > /root/cgroupv2/BE/io.max
		PREV_B_BW_LIMIT=$B_BW_LIMIT
		PREV_B_IOPS_LIMIT=$B_IOPS_LIMIT
		set +x
	else
		if [ $PREV_B_BW_LIMIT != $B_BW_LIMIT ] 
		then
		set -x
		echo "$DEV rbps=$(($B_BW_LIMIT * 1024 * 1024)) riops=$B_IOPS_LIMIT" > /root/cgroupv2/BE/io.max
		PREV_B_BW_LIMIT=$B_BW_LIMIT
		PREV_B_IOPS_LIMIT=$B_IOPS_LIMIT
		set +x
		fi
	fi

	S_CNT=$(ls .meta/S*.pid | wc -l)
	TOTAL_S_BW_REQ=$(($BW * $S_CNT))
	TOTAL_S_IOPS_REQ=$(($IOPS * $S_CNT))

	sleep 1
done

