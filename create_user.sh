#!/bin/bash


VG=SPYRE
CGROUP_PREFIX=blkio_test_
CGROUPV2_DIR=/root/cgroupv2
META_DIR=.meta
BDEV=/dev/sdb
THREAD=1
MAX_WEIGHT=1000
MIN_WEIGHT=100

IDX=1
LV_SIZE=50g
OUTPUT_DIR=results/default
SEQ=0 # 0:random 1:sequential
RRATIO=100 # percentage
#AIO="-a 1"
CLASS=D
MAX_BW=400
MAX_IOPS=50000
BLK_SIZE=4 # KB

PVDEV=$(cat /sys/block/sdb/dev)

create_lv(){
	LV=$VG$1
	lvcreate -L $2 -n $LV $VG

	if [ $? = 0 ]
	then
		LVM_DEV_PATH=$(readlink -f /dev/$VG/$LV)
		IFS='\/' read -ra VAL <<< "$LVM_DEV_PATH"
		LVDEV=$(cat /sys/block/${VAL[2]}/dev)
		#MAX_SECTORS_KB=/sys/block/${VAL[2]}/queue/max_sectors_kb
		echo "logical volume ($VG/$LV) created."
		return 0
	else
		echo "failed to create a logical volume."
		return 1
	fi
}

delete_lv(){
	lvremove -f $VG/$LV

	if [ $? = 0 ]
	then
		echo "logical volume ($VG/$LV) removed."
		return 0
	else
		echo "failed to remove a logical volume ($VG/$LV)."
	fi
}

create_cgroup_add_pid(){
	if [ $CGROUP_VER = 2 ]
	then
		mkdir $CGROUPV2_DIR/$CGROUP_NAME
		#mkdir $CGROUPV2_DIR/spyre/blkio_test_S0
		echo "$CGROUP_NAME for io created."
		echo "$1" > $CGROUPV2_DIR/$CGROUP_NAME/cgroup.procs
		#echo "$1" > $CGROUPV2_DIR/spyre/blkio_test_S0/cgroup.procs
		echo "pid[$1] moved to $CGROUP_NAME"
	else
		cgm create blkio $CGROUP_NAME
		echo "$CGROUP_NAME for blkio created."
		cgm movepid blkio $CGROUP_NAME $1
		echo "pid[$1] moved to $CGROUP_NAME"
	fi
}

cgroup_set_values(){
	if [ $CGROUP_VER = 2 ]
	then
		set -x
		#echo "$LVDEV bps=$MAX_BW iops=$MAX_IOPS" > $CGROUPV2_DIR/$CGROUP_NAME/io.max
		echo "$PVDEV rbps=$MAX_BW riops=$MAX_IOPS" > $CGROUPV2_DIR/$CGROUP_NAME/io.max
		echo "$PVDEV $WEIGHT" > $CGROUPV2_DIR/$CGROUP_NAME/io.weight
		set +x 
	else
		cgm setvalue blkio $1 blkio.throttle.read_bps_device "$LVDEV $MAX_BW"
		cgm setvalue blkio $1 blkio.throttle.read_iops_device "$LVDEV $MAX_IOPS"
		#cgm setvalue blkio $1 blkio.throttle.read_bps_device "$PVDEV $MAX_BW"
		#cgm setvalue blkio $1 blkio.throttle.read_iops_device "$PVDEV $MAX_IOPS"
		cgm setvalue blkio $1 blkio.weight_device "$PVDEV $WEIGHT"
	fi
}

delete_cgroup(){
	if [ $CGROUP_VER = 2 ]
	then
		rmdir $CGROUPV2_DIR/$CGROUP_NAME
	else
		cgm remove blkio $CGROUP_NAME
	fi
}


while getopts ":i:C:B:I:b:a:r:s:L:o:t:T:" opt; do
	case $opt in
		T)
			INIT_R_THREAD=$OPTARG
			;;
		t)
			THREAD=$OPTARG
			;;
		i)
			IDX=$OPTARG
			;;
		L)
			LV_SIZE=$OPTARG
			;;
		o)
			OUTPUT_DIR=results/$OPTARG
			;;
		s)
			SEQ=$OPTARG
			;;
		r)
			RRATIO=$OPTARG
			;;
		a)
			AIO="-a $OPTARG"
			;;
		C)
			CLASS=$OPTARG
			;;
		B)
			MAX_BW=$OPTARG
			;;
		I)
			MAX_IOPS=$OPTARG
			;;
		b)
			BLK_SIZE=$OPTARG
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

if [ ! -e $OUTPUT_DIR ]
then
	mkdir $OUTPUT_DIR
fi

if [ ! -e $META_DIR ]
then
	mkdir $META_DIR
fi

CGROUP_NAME=$CGROUP_PREFIX$IDX

mountpoint -q $CGROUPV2_DIR
if [ $? = 0 ] 
then 
	CGROUP_VER=2
	MAX_WEIGHT=10000
	MIN_WEIGHT=1
else
	CGROUP_VER=1
	MAX_WEIGHT=1000
	MIN_WEIGHT=100
fi

create_lv $IDX $LV_SIZE

if [ $CLASS = "D" ]
then
	WEIGHT=1000
elif [ $CLASS = "S" ]
then
	WEIGHT=$MAX_WEIGHT
	if [ $CGROUP_VER = 2 ]
	then
		CGROUP_NAME="/spyre/$CGROUP_NAME"
	fi
elif [ $CLASS = "B" ]
then
	WEIGHT=$MIN_WEIGHT
	if [ $CGROUP_VER = 2 ]
	then
		CGROUP_NAME="/spyre/$CGROUP_NAME"
	fi
	#echo 64 > $MAX_SECTORS_KB
fi

__DEVSIZE=$(blockdev --getsize $LVM_DEV_PATH)
DEV_PATH=$LVM_DEV_PATH
DEVSIZE=$(($__DEVSIZE * 512))

#<<'COMMENT'
if [ $CLASS = "S" ]
then
	#ionice -c 2 -n 0 -p $PID
	IONICE="ionice -c 2 -n 0"
elif [ $CLASS = "B" ]
then
	#ionice -c 2 -n 7 -p $PID
	IONICE="ionice -c 3"
fi
#COMMENT



set -x
#chown leeyo:leeyo $DEV_PATH
#sudo -u leeyo ./iogen -B $DEVSIZE -b $BLK_SIZE -r $RRATIO -s $SEQ -d $DEV_PATH -t $THREAD -T $INIT_R_THREAD $AIO > $OUTPUT_DIR/$IDX.out &
$IONICE ./iogen -B $DEVSIZE -b $BLK_SIZE -r $RRATIO -s $SEQ -d $DEV_PATH -t $THREAD -T $INIT_R_THREAD $AIO -l $OUTPUT_DIR/${IDX}_rlat_dist > $OUTPUT_DIR/$IDX.out &
#./iogen -B $DEVSIZE -b $BLK_SIZE -r $RRATIO -s $SEQ -d $DEV_PATH -t $THREAD -T $INIT_R_THREAD $AIO -l $OUTPUT_DIR/${IDX}_rlat_dist > $OUTPUT_DIR/$IDX.out &
set +x
#PID=$(ps -ef | grep "$DEV_PATH" | grep iogen | grep leeyo | grep -v root | awk '{print $2}')
PID=$!
create_cgroup_add_pid $PID

echo $PID > $META_DIR/$IDX.pid
echo $LVDEV > $META_DIR/$IDX.dev
echo $CGROUP_NAME > $META_DIR/$IDX.cgroup

MAX_BW=$(echo $MAX_BW*1000000 / 1 | bc )
MAX_IOPS=$(echo $MAX_IOPS / 1 | bc )
cgroup_set_values $CGROUP_NAME

echo "waiting for $PID"
wait $PID

delete_cgroup
delete_lv

rm -rf $META_DIR/$IDX.*
