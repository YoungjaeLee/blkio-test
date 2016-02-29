#!/bin/bash

AIO=
THREAD=4
RRATIO=100
IODEPTH=128

print_usage(){
	echo "./test.sh -f [file_name] -n [n_thread] -r [r_ratio] -d [iodepth] -a"
}

while getopts ":f:an:r:hd:" opt; do
	case $opt in
		d)
			IODEPTH=$OPTARG
			;;
		f)
			DEV=$OPTARG
			;;
		a)
			AIO="-a"
			;;
		n)
			THREAD=$OPTARG
			;;
		r)
			RRATIO=$OPTARG
			;;
		h)
			print_usage
			exit 0
			;;
		esac
done

__DEVSIZE=$(blockdev --getsize $DEV)
DEVSIZE=$(($__DEVSIZE * 512))

set -x
./test -f $DEV -D $DEVSIZE -n $THREAD -d $IODEPTH $AIO -t 30 -r $RRATIO
set +x
