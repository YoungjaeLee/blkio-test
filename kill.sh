#pid=$(ps -ef | grep iogen | grep root | awk '{print $2}')

#pid=$(cat .meta/$1.pid)

#echo "Terminate the process($pid)"
#kill -15 $pid

while getopts "p:ad:i:" opt; do
	case $opt in
		p)
			PREFIX=$OPTARG
			SIGNUM=15
			SIGTXT=SIGTERM
			;;
		a)
			rm -rf /home/leeyo/blkio-test/.meta/monitor
			SIGNUM=15
			SIGTXT=SIGTERM
			;;
		i)
			PREFIX=$OPTARG
			SIGNUM=10
			SIGTXT=SIGUSR0
			;;
		d)
			PREFIX=$OPTARG
			SIGNUM=12
			SIGTXT=SIGUSR1
			;;
	esac
done

pidfiles=$(ls .meta/$PREFIX*.pid)

for pidfile in $pidfiles
do
	pid=$(cat $pidfile)
	echo "Signal($SIGTXT) the process($pid)"
	kill -$SIGNUM $pid
done

