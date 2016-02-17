PID=$(ps -ef | grep iogen | grep root | awk '{print $2}')

echo "Terminate the process($PID)"
kill -15 $PID
