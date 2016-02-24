#!/bin/bash

AIO=
THREAD=4
RRATIO=100

print_usage(){
	echo "./test.sh -f [file_name] -n [n_thread] -r [r_ratio] -a"
}

while getopts ":f:an:r:h" opt; do
	case $opt in
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
./test -f $DEV -D $DEVSIZE -n $THREAD -d 256 $AIO -t 30 -r $RRATIO
set +x
