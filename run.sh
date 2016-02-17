#!/bin/bash

IMAGE_FILE_DIR=/home/leeyo/disk1
IMAGE_FILE_SIZE=1 # GB
LOOP_DEV_PATH=

VG=leeyo
LV=
LV_SIZE=10g

DEV=
CGROUP_PREFIX=blkio_test_
IDX=1
BLKSIZE=4 # KB
RRATIO=100 # percentage
SEQ=1 # 0:random 1:sequential
META_DIR=.meta

create_lv(){
	LV=$VG$1
	lvcreate -L $2 -n $LV $VG

	if [ $? = 0 ]
	then
		LVM_DEV_PATH=$(readlink -f /dev/mapper/$VG-$LV)
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
	cgm create blkio $CGROUP_PREFIX$IDX
	echo "$CGROUP_PREFIX$IDX for blkio created."
	cgm movepid blkio $CGROUP_PREFIX$IDX $1
	echo "pid[$1] moved to $CGROUP_PREFIX$IDX"
}

delete_cgroup(){
	cgm remove blkio $CGROUP_PREFIX$IDX
}

while getopts ":i:b:r:sl" opt; do
	case $opt in
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
		:)
			echo "Option -$OPTARG requires an argument."
			exit 1
		;;
	esac
done

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

./iogen -B $DEVSIZE -b $BLKSIZE -r $RRATIO -s $SEQ -d $DEV_PATH > $IDX.out &
PID=$!
echo "iogen executed($PID) (-B $DEVSIZE -b $BLKSIZE -r $RRATIO -s $SEQ -d $DEV_PATH > $IDX.out)"
create_cgroup_add_pid $PID

echo $PID > $META_DIR/$IDX.pid
echo $DEV > $META_DIR/$IDX.dev
echo $CGROUP_PREFIX$IDX > $META_DIR/$IDX.cgroup

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
