Q=0

while getopts "r:b:i:g:" opt; do
	case $opt in
		g)
			PREFIX=$OPTARG
			Q=1
			;;
		r)
			PREFIX=$OPTARG
			IOCLASS=1
			CLASSDATA="-n 0"
			IOCLASSTXT=REAL
			;;
		b)
			PREFIX=$OPTARG
			IOCLASS=2
			IOCLASSTXT=BE
			;;
		i)
			PREFIX=$OPTARG
			IOCLASS=3
			IOCLASSTXT=IDLE
			;;
	esac
done

pidfiles=$(ls .meta/$PREFIX*.pid)

for pidfile in $pidfiles
do
	pid=$(cat $pidfile)
	echo "ionice the process($pid) to $IOCLASSTXT"
	if [ $Q = 1 ]
	then
		ionice -p $pid
	else
		ionice -c $IOCLASS $CLASSDATA -p $pid
	fi
done

