#!/bin/sh

#
# This program created by Rich Gannon <rich@richgannon.net>.
#
# Version 1.1: 2017-10-31
#
# Updated copies of this program may be found by visiting:
# http://richgannon.net/projects/dellfanspeed
#
# This program comes with absolutely no warranty.  Please
# test thoroughly on your hardware and in your environment
# at your own risk.
#

#
# Set to 1 if PERC6, H200, H700, or other LSI MegaRAID-based
# RAID controller is in use (in RAID mode).
#
MEGARAID=1

#
# Set MEGACLI to 0 if you want to disable the check for
# the MegaCLI command utility `megacli`.  If set to 1
# and megacli command is in $PATH, this script will use
# megacli to pill drive temperatures.
#
MEGACLI=1

#
# Set this to 1 to output additional information to the terminal.
# Set this to 2 to output information information to the terminal.
#
DEBUG=1

#
# Time to sleep between polls in seconds.
#
SLEEP_TIMER=5

#
# Multiple value of SLEEP_TIMER to be used after increasing level
# before we're allowed to decrease it again.  This can help
# reduce fan's continuously increasing and decreasing too rapdily
# each poll.
#
# Example:
# SLEEP_TIMER = 5
# SLEEP_TIMER_MULTIPLY = 6
# 5 seconds x 6 = 30 seconds
#
SLEEP_TIMER_MULTIPLY=6

#
# Set temperature levels and fan levels here.  Fan speeds are in
# hex.  Please adjust only if you know what you are doing and
# test that the fan speeds are appropriate on your server!
# LEVEL0 is assumed when below LEVEL1.
#
CPU_LEVEL1=36
CPU_LEVEL2=42
CPU_LEVEL3=48
CPU_LEVEL4=55
CPU_LEVEL5=65

HDD_LEVEL1=36
HDD_LEVEL2=38
HDD_LEVEL3=40
HDD_LEVEL4=42
HDD_LEVEL4=44
HDD_LEVEL5=46

#
# Set the `ipmitool` connect line here.  Right now everything is programmed
# to be on a bare metal OS, and likely will not work on a VM where an IP
# login to the iDRAC will work.
#
IPMI_TOOL="ipmitool"

#
# Approximate RPM values in my R710 Gen II are as follows:
# 0x09 = 2100
# 0x10 = 2800
# 0x13 = 3240
# 0x22 = 4680
# 0x32 = 6600
# 0x38 = 7440
# auto = controlled by iDRAC firmware (default Dell bahavior)
#

FAN_LEVEL0=0x09
FAN_LEVEL1=0x13
FAN_LEVEL2=0x22
FAN_LEVEL3=0x32
FAN_LEVEL4=0x38
FAN_LEVEL5=auto

#
# Don't change this.  Initializing variables.
#
OLD_LEVEL=5
FAN_IS_AUTO=1
CMD_FAN_AUTO=0
TIMER_MULTIPLY=0

#
# If MegaCLI utility is available, it is much faster than smartctl
#
if [ "`which megacli`" = "" ]; then
	MEGACLI=0
fi

#
# Trap if CTRL+C is pressed.  If it is, we will call our exit_graceful()
# function to relinquish control back to the iDRAC Firmware.
#
trap exit_graceful INT

poll_drive_temp() {
	high_drive_temp=0
	if [ $MEGACLI -eq 1 ]; then
		for drive_temp in `megacli -PDList -aALL | grep "Drive Temperature" | awk '{print $3}' | cut -d ':' -f2 | cut -d 'C' -f1`; do
			if [ $drive_temp -gt $high_drive_temp ]; then
				high_drive_temp=$drive_temp
			fi

			if [ $DEBUG -eq 2 ]; then
				echo "Drive Temp: $drive_temp"
			fi
		done

		if [ $DEBUG -gt 0 ]; then
			echo "Highest drive temperature: $high_drive_temp Celcius."
		fi
		return 0
	fi

	if [ $MEGARAID -eq 1 ]; then
		for drive in 00 01 02 03 04 05 06 07; do
			if [ "`smartctl -d megaraid,$drive -a /dev/sda -a | grep SAS`" != "" ]; then
				drive_temp=`smartctl -d megaraid,$drive /dev/sda -A | grep "Current Drive Temperature" | awk '{print $4}' | tail -n1` || drive_temp=0
			else
				drive_temp=`smartctl -d megaraid,$drive -A /dev/sda | grep "Temperature" | awk '{print $10}' | tail -n1` || drive_temp=0
			fi

			if [ $drive_temp ]; then

				if [ $drive_temp -gt $high_drive_temp ]; then
					high_drive_temp=$drive_temp
				fi
			else
				drive_temp="not installed"
			fi

			if [ $DEBUG -eq 2 ]; then
				echo "$drive: $drive_temp"
			fi
		done
	else
		for drive in `lsblk -d | grep sd | awk '{print $1}'`; do
			if [ "`smartctl -a $drive -a | grep SAS`" != "" ]; then
				drive_temp=`smartctl /dev/$drive -A | grep "Current Drive Temperature" | awk '{print $4}'` || drive_temp=0
			else
				drive_temp=`smartctl -A /dev/$drive | grep "Temperature" | awk '{print $10}' | tail -n1` || drive_temp=0
			fi

			if [ $drive_temp ]; then
				if [ $drive_temp -gt $high_drive_temp ]; then
					high_drive_temp=$drive_temp
				fi
			else
				drive_temp="not installed"
			fi

			if [ $DEBUG -eq 2 ]; then
				echo "$drive Temp: $drive_temp"
			fi
		done
	fi

	if [ $DEBUG -gt 0 ]; then
		echo "Highest drive temperature: $high_drive_temp Celcius."
	fi
}

#
# Poll CPU core temperatures via lm_sensors coretemp driver
#
poll_core_temp() {
	high_core_temp=0
	for core_temp in `sensors | grep Core | awk '{print $3}' | cut -d '+' -f2 | cut -d '.' -f1`; do
		if [ $core_temp -gt $high_core_temp ]; then
			high_core_temp=$core_temp
		fi

		if [ $DEBUG -eq 2 ]; then
			echo "Core Temp: $core_temp"
			echo "High Temp: $high_core_temp"
		fi
	done

	if [ $DEBUG -gt 0 ]; then
		echo "Highest CPU core temperature: $high_core_temp Celcius."
	fi
}

#
# Compare Max polled temperatures and set the appropriate level based
# on our user-configured levels.
#
level_test() {
	if [ $high_core_temp -lt $CPU_LEVEL1 ] && [ $high_drive_temp -lt $HDD_LEVEL1 ]; then
		NEW_LEVEL=0
		if [ "$FAN_LEVEL0" = "auto" ]; then
			CMD_FAN_AUTO=1
		else
			IPMI_CMD="raw 0x30 0x30 0x02 0xff $FAN_LEVEL0"
		fi
	elif [ $high_core_temp -lt $CPU_LEVEL2 ] && [ $high_drive_temp -lt $HDD_LEVEL2 ]; then
		NEW_LEVEL=1
		if [ "$FAN_LEVEL1" = "auto" ]; then
			CMD_FAN_AUTO=1
		else
			IPMI_CMD="raw 0x30 0x30 0x02 0xff $FAN_LEVEL1"
		fi
	elif [ $high_core_temp -lt $CPU_LEVEL3 ] && [ $high_drive_temp -lt $HDD_LEVEL3 ]; then
		NEW_LEVEL=2
		if [ "$FAN_LEVEL2" = "auto" ]; then
			CMD_FAN_AUTO=1
		else
			IPMI_CMD="raw 0x30 0x30 0x02 0xff $FAN_LEVEL2"
		fi
	elif [ $high_core_temp -lt $CPU_LEVEL4 ] && [ $high_drive_temp -lt $HDD_LEVEL4 ]; then
		NEW_LEVEL=3
		if [ "$FAN_LEVEL3" = "auto" ]; then
			CMD_FAN_AUTO=1
		else
			IPMI_CMD="raw 0x30 0x30 0x02 0xff $FAN_LEVEL3"
		fi
	elif [ $high_core_temp -lt $CPU_LEVEL5 ] && [ $high_drive_temp -lt $HDD_LEVEL5 ]; then
		NEW_LEVEL=4
		if [ "$FAN_LEVEL4" = "auto" ]; then
			CMD_FAN_AUTO=1
		else
			IPMI_CMD="raw 0x30 0x30 0x02 0xff $FAN_LEVEL4"
		fi
	else
		NEW_LEVEL=5
		if [ "$FAN_LEVEL5" = "auto" ]; then
			CMD_FAN_AUTO=1
		else
			IPMI_CMD="raw 0x30 0x30 0x02 0xff $FAN_LEVEL5"
		fi
	fi
}

#
# If we change our temp level, we need to issue a command.  If we don't change
# our level to a new one, no need to issue an IPMI command.
#
level_compare() {
	if [ $OLD_LEVEL -eq $NEW_LEVEL ]; then
		if [ $DEBUG -gt 0 ]; then
			echo "Remaining in fan level $OLD_LEVEL."
		fi
		TIMER_MULTIPLY=$SLEEP_TIMER_MULTIPLY
	elif [ $OLD_LEVEL -gt $NEW_LEVEL ] && [ $TIMER_MULTIPLY -gt 0 ]; then
		if [ $DEBUG -gt 0 ]; then
			echo "Wait $TIMER_MULTIPLY more polls before reducing fan level."
		fi
		TIMER_MULTIPLY=`expr $TIMER_MULTIPLY - 1`
	else
		level_change
		TIMER_MULTIPLY=$SLEEP_TIMER_MULTIPLY
	fi
}

level_change() {
	if [ $CMD_FAN_AUTO -eq 1 ] && [ $FAN_IS_AUTO -ne 1 ]; then
		if [ $DEBUG -gt 0 ]; then
			echo "Commanding fan to auto mode."
		fi
		`$IPMI_TOOL raw 0x30 0x30 0x01 0x01`
		FAN_IS_AUTO=1
		CMD_FAN_AUTO=0
	elif [ $CMD_FAN_AUTO -eq 1 ] && [ $FAN_IS_AUTO -eq 1 ]; then
		if [ $DEBUG -gt 0 ]; then
			echo "Fan already in auto mode."
		fi
		CMD_FAN_AUTO=0
	elif [ $CMD_FAN_AUTO -eq 0 ] && [ $FAN_IS_AUTO -eq 1 ]; then
		if [ $DEBUG -gt 0 ]; then
			echo "Commanding fan to manual mode."
		fi
		`$IPMI_TOOL raw 0x30 0x30 0x01 0x00`
		FAN_IS_AUTO=0
		CMD_FAN_AUTO=0
	else
		if [ $DEBUG -gt 0 ]; then
			echo "Fan already in manual mode."
		fi
	fi
	if [ $DEBUG -gt 0 ]; then
		echo "Changing to fan level $NEW_LEVEL."
	fi
	`$IPMI_TOOL $IPMI_CMD`
	OLD_LEVEL=$NEW_LEVEL
}


exit_graceful() {
        echo "Exit requested."
        echo "Enabling iDRAC automatic fan control."
        `$IPMI_TOOL raw 0x30 0x30 0x01 0x01`
        exit 0
}

#
# Begin executing the program in a continuous loop.
#
while true; do
	if [ $DEBUG -gt 0 ]; then
		echo "Start Polling..."
	fi
	poll_core_temp
	poll_drive_temp
	level_test
	level_compare
	if [ $DEBUG -gt 0 ]; then
		echo "Wait $SLEEP_TIMER seconds..."
		echo
	fi
	sleep $SLEEP_TIMER
done

exit 0
