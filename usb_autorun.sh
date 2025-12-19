#!/bin/bash

exec 1> >(logger -s -t $(basename $0)) 2>&1
#set -x

#echo $0 $@

usage()
{
    echo "Usage: $0 {add|remove} device_name (e.g. sdb1)"
    exit 1
}

if [[ $# -ne 2 ]]; then
    usage
fi

ACTION=$1
DEVBASE=$2
DEVICE="/dev/${DEVBASE}"

AUTOFILE="ttfile.bin"
WORKDIR="/home/root/autowork"
PUBKEY="/usr/share/usb_autorun/public.pem"

MAX_SIGN_SIZE=1000
MAX_DATA_SIZE=2000000

SCRIPT_TIMEOUT=300

GPIO_SOCKET="/tmp/gpio_module.socket"

GPIO_CMD_START="usb_processing"
GPIO_CMD_ERROR="usb_error"
GPIO_CMD_SUCCESS="usb_ok"
GPIO_CMD_NORMAL="usb_exec"

gpio_cmd()
{
	if [ -e $GPIO_SOCKET ]; then
		echo -n "$1" | socat - UNIX-CONNECT:"$GPIO_SOCKET"
	fi
}

check_process()
{
	OWN_PID=$$
	CHILD=$(pgrep -x -P $OWN_PID "$(basename $0)")
	PIDS=$(pgrep -x "$(basename $0)")
	PIDS=$(echo "$PIDS" | grep -v $OWN_PID)

	for p in $CHILD; do
		PIDS=$(echo "$PIDS" | grep -v $p)
	done

	if [ -z "$PIDS" ]; then
		# No more instances running
		return 0
	else
		echo $PIDS
		return 1
	fi
}

stop_autorun()
{
	P=0

	while true; do
		PIDS=$(check_process)
		RC=$?

		if [ "$RC" -eq 0 ]; then
			break
		fi

		if [ $P -ge 10 ]; then
			kill -9 $(PIDS)
			kill -15 $(PIDS)
			break
		else
			kill $PIDS
		fi

		((P++))

		sleep 1
	done
}

do_safety_check()
{
	echo "Safety check"
	# Check if already mounted
	
	if ! check_process > /dev/null; then
		echo "USB autorun already running"
		# Not run?
		exit 1
		# Kill other instance?
		# Wait?
	fi

	# trap 'handle_sigint' SIGINT

	# Is the device ready? Is it still rebooting?
	#     Not run -> show error
	#     Wait until finished
}

safe_run()
{
	SCRIPT=$1

	echo "Start executing script"
	echo "****************"

	mkdir -p $WORKDIR/results

	pushd $WORKDIR > /dev/null
	/bin/bash $SCRIPT &
	SCRIPT_PID=$!

	timeout $SCRIPT_TIMEOUT tail --pid=$SCRIPT_PID -f /dev/null

	RC=$?

	if [ $RC -eq 124 ]; then
		echo "Script timeout!"
	fi

	popd > /dev/null

	echo "****************"
	echo "Script finised with rc = $RC"

	return $RC
}

run_script()
{
	SCRIPT=$1
	TAR=$2
	EPOCH=$(date +"%s")

	safe_run $SCRIPT 2>&1 | tee -a $WORKDIR/log
	RC=${PIPESTATUS[0]}


	if [ ! -z "$TAR" ]; then
		# Tar results
		tar -czf $WORKDIR/result.tar.gz -C $WORKDIR log results/
		if [ ! $? -eq  0 ]; then
			return 122
		fi

		cp $WORKDIR/result.tar.gz $MOUNT_POINT/$TAR-$EPOCH.tar.gz
		if [ ! $? -eq  0 ]; then
			return 123
		fi
	fi


	return $RC

}

exit_normal()
{
	if [ -n $DEVBASE ]; then
		/usr/bin/usb_mount.sh remove $DEVBASE
	fi
	rm -rf $WORKDIR
	exit 1
}

exit_error()
{
	if [ -n $DEVBASE ]; then
		/usr/bin/usb_mount.sh remove $DEVBASE
	fi
	rm -rf $WORKDIR
	gpio_cmd $GPIO_CMD_ERROR
	exit 1
}

exit_success()
{
	if [ -n $DEVBASE ]; then
		/usr/bin/usb_mount.sh remove $DEVBASE
	fi
	#rm -rf $WORKDIR
	gpio_cmd $GPIO_CMD_SUCCESS
	exit 0
}

do_execute()
{
	BIN_FILE=$1
	echo "Checking CPIO"
	CPIO_FILES=$(cpio -vt < $BIN_FILE)

	if [ $? -ne 0 ]; then
		echo "Error reading CPIO file"
		exit_error
	fi

	CPIO_NAMES=$(echo "$CPIO_FILES" | awk '{print $NF}' | sort | tr "\\n" "|")

	CORRECT_NAMES="data.tar.gz|sign|"

	if [[ "$CPIO_NAMES" != "$CORRECT_NAMES" ]]; then
		echo "Incorrect filenames in $BIN_FILE"
		exit_error
	fi

	#TODO Use variables for file sizes
	if [[ $(echo "$CPIO_FILES" | awk '{print $5,$NF}' | awk '$2 == "data.tar.gz" && $1 <= 500000000 || $2 == "sign" && $1 <= 1000' | wc -l) -ne 2 ]]; then
		echo "CPIO files too big"
		exit_error
	fi

	echo "CPIO file is correct"

	rm -rf $WORKDIR
	mkdir -p $WORKDIR
	#TODO remove permissions and links and others?
	cpio -idmv --no-absolute-filenames -D $WORKDIR < $BIN_FILE

	if [ $? -ne 0 ]; then
		echo "UnCPIO error"
		exit_error
	fi

	# Check sign
	openssl dgst -sha256 -verify $PUBKEY -signature $WORKDIR/sign $WORKDIR/data.tar.gz

	if [ $? -ne 0 ]; then
		echo "Signature incorrect"
		exit_error
	fi

	echo "Signature correct"

	# Now we can trust the file

	# Untar
	tar -zxf $WORKDIR/data.tar.gz -C $WORKDIR

	if [ $? -ne 0 ]; then
		echo "Untar error"
		exit_error
	fi

	echo "Untar correct"

	# Run the script
	run_script $WORKDIR/script.sh result

	if [ $? -eq 0 ]; then
		touch $WORKDIR/success
		exit_success
	else
		exit_error
	fi
}


do_autorun()
{
	# Check if it is safe to mount
	# Check device exist
	# Malicius code or format?

	echo "Autorun start for $DEVBASE"

	# Mount
	/usr/bin/usb_mount.sh add $DEVBASE

	if [ $? -ne 0 ]; then
		echo "Error mounting $DEVICE"
		exit_normal
	fi

	MOUNT_POINT=$(/bin/mount | /bin/grep ${DEVICE} | /usr/bin/awk '{ print $3 }')

	echo "$DEVICE mounted succesfully at $MOUNT_POINT"

	if [ ! -f "$MOUNT_POINT/$AUTOFILE" ]; then
		echo "$AUTOFILE does not exist"
		exit_normal
	fi

	#exit 0 

	gpio_cmd $GPIO_CMD_START
	# From now on if error -> exit_error

	do_execute $MOUNT_POINT/$AUTOFILE
}

do_cleanup()
{
	/usr/bin/usb_mount.sh remove $DEVBASE

	if [ -f $WORKDIR/success ] && [ -f $WORKDIR/out_script.sh ]; then
		run_script $WORKDIR/out_script.sh
	fi

	rm -rf $WORKDIR
	gpio_cmd $GPIO_CMD_NORMAL
	exit 0
}

case "${ACTION}" in
	run)
		DEVBASE=""
		do_execute $2
		;;
	add)
		do_safety_check
		do_autorun
		;;
	add_daemon)
		#setsid --fork $0 add $DEVBASE > >(logger -t $(basename $0)) 2>&1 < /dev/null & disown
		setsid --fork $0 add $DEVBASE >/dev/null 2>&1 < /dev/null
		exit 0
		;;
	remove)
		stop_autorun
		do_cleanup
		;;
	remove_daemon)
		#setsid --fork $0 remove $DEVBASE > >(logger -s -t $(basename $0)) 2>&1 < /dev/null & disown
		setsid --fork $0 remove $DEVBASE >/dev/null 2>&1 < /dev/null
		exit 0
		;;
	*)
		usage
		;;
esac

