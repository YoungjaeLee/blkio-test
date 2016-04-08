#!/bin/bash

IMAGE_FILE_DIR=/home/leeyo/disk1
IMAGE_FILE_SIZE=1 # GB
LOOP_DEV_PATH=

VG=leeyo
LV=
LV_SIZE=128g

DEV=
CGROUP_PREFIX=blkio_test_
CGROUP_NAME=
IDX=1
BLKSIZE=4 # KB
RRATIO=100 # percentage
THREAD=4
SEQ=1 # 0:random 1:sequential
META_DIR=.meta

create_lv(){
	LV=$VG$1
	lvcreate -L $2 -n $LV $VG

	if [ $? = 0 ]
	then
		LVM_DEV_PATH=$(readlink -f /dev/$VG/$LV)
		IFS='\/' read -ra VAL <<< "$LVM_DEV_PATH"
		DEV=$(cat /sys/block/${VAL[2]}/dev)
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

create_image_file(){
	IMAGE_FILE_PATH=$IMAGE_FILE_DIR/$1.dat
	dd if=/dev/zero of=$IMAGE_FILE_PATH bs=1M count=$2
	
	echo "$IMAGE_FILE_PATH created."
}

create_loop_dev(){
	LOOP_DEV_PATH=$(losetup -f)
	losetup -f $IMAGE_FILE_PATH

	if [ $? = 0 ]
	then
		IFS='\/' read -ra VAL <<< "$LOOP_DEV_PATH"

		DEV=$(cat /sys/block/${VAL[2]}/dev)
		echo "$LOOP_DEV_PATH[$DEV] created."
		return 0
	else
		echo "failed to create loop_dev"
		return 1
	fi
}

delete_image_file(){
	rm -rf $IMAGE_FILE_PATH

	echo "$IMAGE_FILE_PATH deleted."
}

delete_loop_dev(){
	losetup -d $LOOP_DEV_PATH

	echo "$LOOP_DEV_PATH deleted."
}

create_cgroup_add_pid(){
	cgm create blkio $CGROUP_NAME
	echo "$CGROUP_NAME for blkio created."
	cgm movepid blkio $CGROUP_NAME $1
	echo "pid[$1] moved to $CGROUP_NAME"
}

delete_cgroup(){
	cgm remove blkio $CGROUP_NAME
}

OUTPUT_DIR=results/default
CGROUP_IDX=-1
MAX_IOPS=0
MAX_BW=0

while getopts ":i:b:r:s:lt:L:o:a:c:I:B:" opt; do
	case $opt in
		I)
			MAX_IOPS=$OPTARG
			;;
		B)
			MAX_BW=$OPTARG
			;;
		c)
			CGROUP_IDX=$OPTARG
			;;
		a)
			AIO="-a $OPTARG"
			;;
		t)
			THREAD=$OPTARG
			;;
		i)
			IDX=$OPTARG
			;;
		b)
			BLKSIZE=$OPTARG
			;;
		r)
			RRATIO=$OPTARG
			;;
		s)
			SEQ=$OPTARG
			;;
		l)
			LVM=1
			;;
		L)
			LV_SIZE=$OPTARG
			;;
		o)
			OUTPUT_DIR=$OPTARG
			;;
		:)
			echo "Option -$OPTARG requires an argument." >&2
			exit 1
			;;
		\?)
			echo "Invalid option: -$OPTARG." >&2
			exit 1
			;;
	esac
done

if [ $CGROUP_IDX = -1 ]
then
	CGROUP_NAME=$CGROUP_PREFIX$IDX
else
	CGROUP_NAME=$CGROUP_PREFIX$CGROUP_IDX
fi

if [ ! -e $META_DIR ]
then
	mkdir $META_DIR
fi

if [ $LVM = 1 ]
then
	create_lv $IDX $LV_SIZE
	__DEVSIZE=$(blockdev --getsize $LVM_DEV_PATH)
	DEV_PATH=$LVM_DEV_PATH
else
	create_image_file $IDX  $(($IMAGE_FILE_SIZE * 1024))
	create_loop_dev
	__DEVSIZE=$(blockdev --getsize $LOOP_DEV_PATH)
	DEV_PATH=$LOOP_DEV_PATH
fi

DEVSIZE=$(($__DEVSIZE * 512))

set -x
./iogen -B $DEVSIZE -b $BLKSIZE -r $RRATIO -s $SEQ -d $DEV_PATH -t $THREAD $AIO > $OUTPUT_DIR/$IDX.out &
PID=$!
set +x
create_cgroup_add_pid $PID

echo $PID > $META_DIR/$IDX.pid
echo $DEV > $META_DIR/$IDX.dev
echo $CGROUP_NAME > $META_DIR/$IDX.cgroup

if [ $MAX_BW != 0 ]
then
	#cgm setvalue blkio $CGROUP_NAME blkio.throttle.read_bps_device "$DEV $MAX_BW"
	cgm setvalue blkio $CGROUP_NAME blkio.throttle.write_bps_device "$DEV $MAX_BW"
fi

if [ $MAX_IOPS != 0 ]
then
	#cgm setvalue blkio $CGROUP_NAME blkio.throttle.read_iops_device "$DEV $MAX_IOPS"
	cgm setvalue blkio $CGROUP_NAME blkio.throttle.write_iops_device "$DEV $MAX_IOPS"
fi

echo "waiting for $PID"
wait $PID

delete_cgroup

if [ $LVM = 1 ]
then
	delete_lv
else
	delete_loop_dev
	delete_image_file
fi

rm -rf $META_DIR/$IDX.*
