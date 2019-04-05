#!/bin/bash -xe

memchips=`dmidecode -t memory|grep "Serial Number:"|cut -d: -f 2|md5sum|awk '{print $1}'`

if ! [ -d /etc/storpool ]; then
	mkdir /etc/storpool
fi

if [ -f /etc/storpool/${memchips}.memtested ]; then
	echo Memory already tested
	exit 0
fi

swapoff -a
sync
sysctl vm.drop_caches=3

cd /root/storpool
for i in /sys/devices/system/node/node*; do
	node=`basename $i`
	nodenum=`echo $node|sed s/node//`
	memavail=`grep MemFree: $i/meminfo |awk '{print $4-3145728}'`
	if [ "$memavail" -lt 3145728 ]; then
		echo Not enough memory in numa node $i, skipping
		continue
	fi
	cpulist=`(cd $i && ls -d cpu[0-9]* |sed s/cpu// |sort -n)`
	numcpu=`echo "$cpulist"|wc -w`
	if [ "$numcpu" -lt 2 ]; then
		allowedcpu=1
	else
		let allowedcpu=${numcpu}-2
	fi
	let memtotest=${memavail}/${allowedcpu}
	finalcpulist=`(cd $i && ls -d cpu[0-9]* |sed s/cpu// |sort -n|tail -n ${allowedcpu})`
#	cpu=`(cd $i && ls -d cpu*|head -n1 |sed s/cpu//)`
	for cpu in $finalcpulist ; do
		cgexec -g memory:/ -g cpuset:/ taskset -c $cpu numactl --membind $nodenum ./memtester ${memtotest}k 1 > /tmp/memtester.${node}.${cpu}.log &
		jobs=$jobs" $!"
	done
done

for i in $jobs; do
	wait $i
	if ! [ $? -eq 0 ]; then
		echo job $i failed, bailing out
		cat /tmp/memtester.*.log
		exit 2
	fi
done

if [ -s /var/log/mcelog ]; then
        echo MCE errors found, failing
        cat /var/log/mcelog
	exit 2
fi

touch /etc/storpool/${memchips}.memtested
