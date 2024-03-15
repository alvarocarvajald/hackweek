#!/bin/bash
# /etc/ietd.conf
# Target mania-sbd:fa4548ec-8b53-45de-bbbe-355ea5c506ae
# Lun 0 Path=/srv/iscsi/mania-sbd-0,Type=fileio



CONFFILE="/etc/ietd.conf"
QASYSTEMS="mania s390x qam"
QAUSERS="atighineanu jkohoutek hsehic jadamek acarvajal rbranco ldevulder fgerling bschmidt"
DISKS="sbd ocfs2 drbd clustermd"
OPENQA_NUM_TESTS=12
#COUNTER="0"

/etc/init.d/iscsitarget stop

mv $CONFFILE $CONFFILE-$(date +%F-%R)
for qa in $QASYSTEMS; do 
	echo "Target $qa"	>>$CONFFILE
		COUNTER="0"
		for disk in $DISKS; do
			if [ "$disk" == "sbd" ]; then
				DISKSIZE=4
				DISKNR=7
				
			else
				DISKSIZE=1024
				DISKNR=7
			fi

			for disknr in `seq 0 $DISKNR`; do
				[[ -f "/srv/iscsi/$qa-$disk-$disknr" ]] || dd if=/dev/zero of=/srv/iscsi/$qa-$disk-$disknr bs=1M count=$DISKSIZE; 
				echo "Lun $COUNTER Path=/srv/iscsi/$qa-$disk-$disknr,Type=fileio" >>$CONFFILE
				echo "	Alias $qa-$disk-$disknr" >>$CONFFILE
				let COUNTER=COUNTER+1
			done
		done
done
for qa in $QAUSERS; do 
	echo "Target $qa"	>>$CONFFILE
		for disk in $DISKS; do
		COUNTER="0"
			if [ "$disk" == "sbd" ]; then
				DISKSIZE=4
				DISKNR=23
				for disknr in `seq 0 $DISKNR`; do
					[[ -f "/srv/iscsi/$qa-$disk-$disknr" ]] || dd if=/dev/zero of=/srv/iscsi/$qa-$disk-$disknr bs=1M count=$DISKSIZE; 
					echo "Lun $COUNTER Path=/srv/iscsi/$qa-$disk-$disknr,Type=fileio" >>$CONFFILE
					echo "	Alias $qa-$disk-$disknr" >>$CONFFILE
					let COUNTER=COUNTER+1
				done
			fi
			
		done
done

#For openqa
echo "Target 0-openqa"	>>$CONFFILE
for COUNTER in $(seq 0 $((OPENQA_NUM_TESTS*5-1))); do
        DISKSIZE=1024
#        if [ $((COUNTER%5)) == 0 ]; then
#		DISKSIZE=4
#	fi
#	[[ -f "/srv/iscsi/0-openqa/lun-$COUNTER" ]] || dd if=/dev/zero of=/srv/iscsi/0-openqa/lun-$COUNTER bs=1M count=$DISKSIZE
	echo "Lun $COUNTER Path=/srv/iscsi/0-openqa/lun-$COUNTER,Type=fileio" >>$CONFFILE
	echo "  Alias 0-openqa-lun-$COUNTER" >>$CONFFILE
done


/etc/init.d/iscsitarget start
