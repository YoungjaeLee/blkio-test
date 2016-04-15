#!/bin/bash

PERIOD=1
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
	./create_user.sh -i B$i -L 10g -o $OUTPUT_DIR -s 0 -r 100 -t 4 -C B -b 512 -B $BW -I $IOPS &
	#B_BW_LIMIT=$(($B_BW_LIMIT+$BW))
	#B_IOPS_LIMIT=$(($B_IOPS_LIMIT+$IOPS))
	B_BW_LIMIT=1
	B_IOPS_LIMIT=256
	ID=$(($ID + 1))
done

PREV_B_IOPS_LIMIT=-1
PREV_B_BW_LIMIT=-1

if [ -e .meta/monitor ]
then
	exit 0
fi

touch .meta/monitor

CURR_S_BW_REQ=$TOTAL_S_BW_REQ
CURR_S_IOPS_REQ=$TOTAL_S_IOPS_REQ

LT_CNT=0
HT_CNT=0
CNT_TH=3

sleep 1

while true
do
	SRBYTES=0
	SWBYTES=0
	SRIOP=0
	SWIOP=0
	ID=0
	for i in `seq 1 $S_USERS`
	do
		STAT=$(grep $DEV /root/cgroupv2/blkio_test_S$ID/io.stat)
		ID=$(($ID + 1))
		if [ -z "$STAT" ]
		then
			continue
		fi
		IFS='\ =' read -ra VAL <<< "$STAT"
		#8:16 rbytes 205180092416 wbytes 0 rios 25046398 wios 0

		SRBYTES=$(($SRBYTES + ${VAL[2]}))
		SWBYTES=$(($SWBYTES + ${VAL[4]}))
		SRIOP=$(($SRIOP + ${VAL[6]}))
		SWIOP=$(($SWIOP + ${VAL[8]}))
	done

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

	SRBW=$(echo "scale=0; ($SRBYTES-$SPRBYTES)/1000000/$PERIOD" | bc -l)
	#SRIOPS=$(echo "($SRIOP-$SPRIOP)/1000" | bc -l)
	SRIOPS=$(echo "scale=0; ($SRIOP-$SPRIOP)/$PERIOD" | bc -l)
	SPRBYTES=$SRBYTES
	SPRIOP=$SRIOP

	BRBW=$(echo "scale=0; ($BRBYTES-$BPRBYTES)/1000000/$PERIOD" | bc -l)
	#BRIOPS=$(echo "($BRIOP-$BPRIOP)/1000" | bc -l)
	BRIOPS=$(echo "scale=0; ($BRIOP-$BPRIOP)/$PERIOD" | bc -l)
	BPRBYTES=$BRBYTES
	BPRIOP=$BRIOP

	echo "Shared users: read $SRBW MB/s $SRIOPS IOPS BW limit: $CURR_S_BW_REQ IOPS limit: $CURR_S_IOPS_REQ"
	echo "BE users: read $BRBW MB/s $BRIOPS IOPS"

	TOTAL_RBW=$(($SRBW+$BRBW))
	TOTAL_RIOPS=$(($SRIOPS+$BRIOPS))

	LT=$(echo "scale=0; ($CURR_S_BW_REQ * 0.9)/1" | bc -l) 
	HT=$(echo "scale=0; ($CURR_S_BW_REQ * 0.95)/1" | bc -l)
	if [ $SRBW -lt $LT ]
	then
		HT_CNT=0
		LT_CNT=$(($LT_CNT + 1))
		if [ $LT_CNT -gt $CNT_TH ]
		then
			LT_CNT=0

			if [ $TOTAL_RBW -lt $CURR_S_BW_REQ ]
			then
				B_BW_LIMIT=$(($B_BW_LIMIT + 10))
				B_IOPS_LIMIT=$(($B_BW_LIMIT * 256))
				CURR_S_BW_REQ=$(echo "scale=0; ($SRBW * 1.05)/1" | bc -l)
				if [ $TOTAL_S_BW_REQ -lt $CURR_S_BW_REQ ]
				then
					CURR_S_BW_REQ=$TOTAL_S_BW_REQ
				fi
			else
				B_BW_LIMIT=$(($B_BW_LIMIT - 10))

				if [ $B_BW_LIMIT -lt 1 ]
				then
					B_BW_LIMIT=1
				fi
				B_IOPS_LIMIT=$(($B_BW_LIMIT * 256))
			fi
		fi
	elif [ $SRBW -gt $HT ]
	then
		LT_CNT=0
		HT_CNT=$(($HT_CNT + 1))
		if [ $HT_CNT -gt $CNT_TH ]
		then
			HT_CNT=0
			if [ $CURR_S_BW_REQ -lt $TOTAL_S_BW_REQ ]
			then
				CURR_S_BW_REQ=$(echo "scale=0; ($SRBW * 1.1)/1" | bc -l)
				if [ $TOTAL_S_BW_REQ -lt $CURR_S_BW_REQ ]
				then
					CURR_S_BW_REQ=$TOTAL_S_BW_REQ
				fi
			else
				B_BW_LIMIT=$(($B_BW_LIMIT + 10))
				B_IOPS_LIMIT=$(($B_BW_LIMIT * 256))
			fi
		fi
	elif [ $SRBW -lt $CURR_S_BW_REQ ]
	then
		if [ $CURR_S_BW_REQ -lt $TOTAL_S_BW_REQ ]
		then
			CURR_S_BW_REQ=$(echo "scale=0; ($SRBW * 1.05)/1" | bc -l)
		fi
		if [ $TOTAL_S_BW_REQ -lt $CURR_S_BW_REQ ]
		then
			CURR_S_BW_REQ=$TOTAL_S_BW_REQ
		fi
	else
		LT_CNT=0
		HT_CNT=0
	fi

	#LT=$(echo "scale=0; ($CURR_S_IOPS_REQ * 0.9)/1" | bc -l)
	#if [ $SRIOPS -lt $LT ]
	#then
		#if [ $TOTAL_RIOPS -lt $TOTAL_S_IOPS_REQ ]
		#then
			#B_BW_LIMIT=$(($B_BW_LIMIT + 10))
			#B_IOPS_LIMIT=$(($B_BW_LIMIT * 256))
		#else
			##B_IOPS_LIMIT=$((($TOTAL_RIOPS-$TOTAL_S_IOPS_REQ) / 10 ))
			##B_IOPS_LIMIT=$(($B_IOPS_LIMIT * 10))
			#B_IOPS_LIMIT=$(($B_IOPS_LIMIT - 10))
			#if [ $B_IOPS_LIMIT -lt 256 ]
			#then
				#B_IOPS_LIMIT=256
			#fi
			#B_BW_LIMIT=$((B_IOPS_LIMIT / 256))
		#fi
	#fi

	if [ $PREV_B_IOPS_LIMIT != $B_IOPS_LIMIT ] 
	then
		set -x
		#echo "$DEV bps=$(($B_BW_LIMIT * 1024 * 1024)) iops=$B_IOPS_LIMIT" > /root/cgroupv2/BE/io.max
		echo "$DEV rbps=$(($B_BW_LIMIT * 1024 * 1024)) riops=$B_IOPS_LIMIT" > /root/cgroupv2/BE/io.max
		PREV_B_BW_LIMIT=$B_BW_LIMIT
		PREV_B_IOPS_LIMIT=$B_IOPS_LIMIT
		set +x
	else
		if [ $PREV_B_BW_LIMIT != $B_BW_LIMIT ] 
		then
		set -x
		#echo "$DEV bps=$(($B_BW_LIMIT * 1024 * 1024)) iops=$B_IOPS_LIMIT" > /root/cgroupv2/BE/io.max
		echo "$DEV rbps=$(($B_BW_LIMIT * 1024 * 1024)) riops=$B_IOPS_LIMIT" > /root/cgroupv2/BE/io.max
		PREV_B_BW_LIMIT=$B_BW_LIMIT
		PREV_B_IOPS_LIMIT=$B_IOPS_LIMIT
		set +x
		fi
	fi

	S_CNT=$(ls .meta/S*.pid | wc -l)
	TOTAL_S_BW_REQ=$(($BW * $S_CNT))
	TOTAL_S_IOPS_REQ=$(($IOPS * $S_CNT))

	sleep $PERIOD
done

