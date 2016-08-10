#!/bin/bash

PERIOD=3
IDX=0
#DEV_BW=400
#DEV_IOPS=50000
DEV_BW=300
DEV_IOPS=75000
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

SHBLK=4
SH_INIT_TH=4
BEBLK=128
BE_INIT_TH=4

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

#BW=$(echo "scale=0; $DEV_BW/$S_USERS" | bc -l)
#IOPS=$(echo "scale=0; $DEV_IOPS/$S_USERS" | bc -l)
BW=( 150 75 37 19 )
IOPS=( 37500 18500 9250 4625 )
#BW=( 150 150 150 )
#IOPS=( 37500 37500 37500 )
VOL=$(echo "scale=0; $DEV_SIZE / $USERS" | bc -l)


BEBW=200
BEIOPS=25000
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

	./create_user.sh -i S$ID -L 10g -o $OUTPUT_DIR -s 0 -r 100 -t 4 -T $SH_INIT_TH -C S -b $SHBLK -B ${BW[$ID]} -I ${IOPS[$ID]} &
	#./create_user.sh -i S$ID -L 10g -o $OUTPUT_DIR -s 0 -r 100 -a 8 -t 1 -T 1 -C S -b $SHBLK -B ${BW[$ID]} -I ${IOPS[$ID]} &
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

	./create_user.sh -i B$i -L 10g -o $OUTPUT_DIR -s 0 -r 100 -t 4 -T $BE_INIT_TH -C B -b $BEBLK -B $BEBW -I $BEIOPS &
	#./create_user.sh -i B$i -L 10g -o $OUTPUT_DIR -s 0 -r 100 -a 8 -t 1 -T 1 -C B -b $BEBLK -B $BEBW -I $BEIOPS &
	#B_BW_LIMIT=$(($B_BW_LIMIT+$BW))
	#B_IOPS_LIMIT=$(($B_IOPS_LIMIT+$IOPS))
	B_BW_LIMIT=10
	B_IOPS_LIMIT=2560
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

STATE=0

while true
do

<<'COMMENT'
	STAT=$(grep $DEV /root/cgroupv2/Shared/io.stat)
	if [ -z "$STAT" ]
	then
		continue
	fi
	IFS='\ =' read -ra VAL <<< "$STAT"

	SRBYTES=${VAL[2]}
	SWBYTES=${VAL[4]}
	SRIOP=${VAL[6]}
	SWIOP=${VAL[8]}
COMMENT


	SRBYTES=0
	SWBYTES=0
	SRIOP=0
	SWIOP=0
	ID=0
	for i in `seq 1 $S_USERS`
	do
		STAT=$(grep $DEV /root/cgroupv2/spyre/blkio_test_S$ID/io.stat)
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

	BRBYTES=0
	BWBYTES=0
	BRIOP=0
	BWIOP=0
	ID=1
	for i in `seq 1 $B_USERS`
	do
		STAT=$(grep $DEV /root/cgroupv2/spyre/blkio_test_B$ID/io.stat)
		ID=$(($ID + 1))
		if [ -z "$STAT" ]
		then
			continue
		fi
		IFS='\ =' read -ra VAL <<< "$STAT"
		#8:16 rbytes 205180092416 wbytes 0 rios 25046398 wios 0

		BRBYTES=$(($BRBYTES + ${VAL[2]}))
		BWBYTES=$(($BWBYTES + ${VAL[4]}))
		BRIOP=$(($BRIOP + ${VAL[6]}))
		BWIOP=$(($BWIOP + ${VAL[8]}))
	done

<<'COMMENT'
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
COMMENT

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

<<'COMMENT'
	TOTAL_RBW=$(($SRBW+$BRBW))
	TOTAL_RIOPS=$(($SRIOPS+$BRIOPS))

	LT=$(echo "scale=0; ($CURR_S_BW_REQ * 0.9)/1" | bc -l) 
	HT=$(echo "scale=0; ($CURR_S_BW_REQ * 0.95)/1" | bc -l)
	if [ $SRBW -lt $LT ]
	then
		BOOST_SHARED=0
		HT_CNT=0
		LT_CNT=$(($LT_CNT + 1))
		if [ $LT_CNT -gt $CNT_TH ]
		then
			LT_CNT=0
			if [ $TOTAL_RBW -lt $CURR_S_BW_REQ ]
			then
				B_BW_LIMIT=$(($B_BW_LIMIT + 10))
				B_IOPS_LIMIT=$(($B_BW_LIMIT * 256))
				#CURR_S_BW_REQ=$(echo "scale=0; ($CURR_S_BW_REQ * 0.9)/1" | bc -l)
				CURR_S_BW_REQ=$(echo "scale=0; ($SRBW * 1.05)/1" | bc -l)
			else
				B_BW_LIMIT=$(($B_BW_LIMIT - 10))
				if [ $B_BW_LIMIT -lt 10 ]
				then
					B_BW_LIMIT=10
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
				CURR_S_BW_REQ=$(echo "scale=0; ($SRBW * 1.15)/1" | bc -l)
				if [ $TOTAL_S_BW_REQ -lt $CURR_S_BW_REQ ]
				then
					CURR_S_BW_REQ=$TOTAL_S_BW_REQ
				fi

				B_BW_LIMIT=$(($B_BW_LIMIT - 10))
				if [ $B_BW_LIMIT -lt 10 ]
				then
					B_BW_LIMIT=10
				fi
				B_IOPS_LIMIT=$(($B_BW_LIMIT * 256))

				BOOST_SHARED=1

			else
				if [ $BRBW -lt $(echo "scale=0; ($B_BW_LIMIT * 0.9)/1" | bc -l) ]
				then
					B_BW_LIMIT=$BRBW
				else
					B_BW_LIMIT=$(($B_BW_LIMIT + 10))
				fi

				if [ $B_BW_LIMIT -lt 10 ]
				then
					B_BW_LIMIT=10
				fi
				B_IOPS_LIMIT=$(($B_BW_LIMIT * 256))
			fi
		fi
	else
#		if [ $CURR_S_BW_REQ -lt $TOTAL_S_BW_REQ ]
#		then
#			CURR_S_BW_REQ=$(echo "scale=0; ($SRBW * 1.05)/1" | bc -l)
#			if [ $TOTAL_S_BW_REQ -lt $CURR_S_BW_REQ ]
#			then
#				CURR_S_BW_REQ=$TOTAL_S_BW_REQ
#			fi
#		fi

		if [ $BRBW -lt $(echo "scale=0; ($B_BW_LIMIT * 0.9)/1" | bc -l) ]
		then
			B_BW_LIMIT=$BRBW
			if [ $B_BW_LIMIT -lt 10 ]
			then
				B_BW_LIMIT=10
			fi
		elif [ $BOOST_SHARED = 1 ]
		then
			B_BW_LIMIT=$(($B_BW_LIMIT + 10))
		fi
		B_IOPS_LIMIT=$(($B_BW_LIMIT * 256))

		LT_CNT=0
		HT_CNT=0
	fi

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

COMMENT
	sleep $PERIOD
done

