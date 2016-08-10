#!/bin/sh
sleep 20
./kill.sh -d S3
sleep 20
./kill.sh -d S2
sleep 20
./kill.sh -d S1
sleep 20
./kill.sh -i S1
sleep 20
./kill.sh -i S2
sleep 20
./kill.sh -i S3
sleep 20
