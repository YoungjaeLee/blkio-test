#!/bin/sh

sudo chown -R leeyo:leeyo results

for j in `seq 1 $1`
do
echo "results/$j"
for i in `seq 1 $j`
do
grep bytes results/$j/$i.out | awk '{print $14 " " $18}' > results/$j/$i.iops
tail -n2 results/$j/$i.out | grep bytes | awk '{print $2 " " $6 " " $10}'
done
echo " "
done
