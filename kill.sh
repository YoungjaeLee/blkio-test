#pid=$(ps -ef | grep iogen | grep root | awk '{print $2}')

#pid=$(cat .meta/$1.pid)

#echo "Terminate the process($pid)"
#kill -15 $pid

pidfiles=$(ls .meta/*.pid)

for pidfile in $pidfiles
do
	pid=$(cat $pidfile)
	echo "Terminate the process($pid)"
	kill -15 $pid
done

