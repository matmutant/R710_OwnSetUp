#!/bin/sh
# Set the `ipmitool` connect line here.  Right now everything is programmed
# to be on a bare metal OS, and likely will not work on a VM where an IP
# login to the iDRAC will work.
#
IPMI_TOOL="ipmitool"
$IPMI_TOOL raw 0x30 0x30 0x01 0x01
exit 0
