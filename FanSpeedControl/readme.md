# Fan speed

## Basics   
Dell R710 is basically noisy with its fan at minimum 3600rpm when idle. There is no 'manufacturer documented' way to control fan speed.

## Simple Trick : manual control  

set to manual control, then to lowest speed possible (1200rpm) and monitor temp
```
ipmitool -I lanplus -H <iDRACip> -U <User> -P <pw> raw 0x30 0x30 0x01 0x00
ipmitool -I lanplus -H <iDRACip> -U <User> -P <pw> raw 0x30 0x30 0x02 0xff 0x00
ipmitool -I lanplus -H <iDRACip> -U <User> -P <pw> sdr type temperature
``` 
## Automation with Rich Gannon's Script
source : http://richgannon.net/projects/dellfanspeed/

### Run as a service

#### Prepare files
- Slightly modified Rich Gannon's script (`/usr/src/r710_fan_controller.sh`)  
- Fan speed restore script (`/usr/src/r710_fan_restore.sh`)

NB: it might not be the best thing to daemonize the nearly untouched script, but for now, it does the job it is meant to. 
TODO: re-write script to make it more daemon-proof. 

#### Run Scripted fan control using systemd
To start manual/scripted fan control, a service that run's the script is needed : 

/etc/systemd/system/dell-speedfancontrol.service
```
[Unit]
Description=DellSpeedFanControl
After=default.target

[Service]
Type=forking
ExecStart=/usr/src/r710_fan_controller.sh
#ExecStop=/usr/src/r710_fan_restore.sh
Restart=on-failure

[Install]
WantedBy=default.target
```

enable the service : `systemctl enable dell-speedfancontrol.service`


#### Restore Auto fan speed at shudown/reboot/halt
To restore iDRAC managed fan speed, a service that start's on shutdown/reboot/halt is needed.

/etc/systemd/system/dell-speedfanrestore.service
```
[Unit]
Description=Restore fan speed on shutdown
DefaultDependencies=no
Before=shutdown.target reboot.target halt.target
# This works because it is installed in the target and will be
#   executed before the target state is entered
# Also consider kexec.target

[Service]
Type=oneshot
ExecStart=/usr/src/r710_fan_restore.sh

[Install]
WantedBy=halt.target reboot.target shutdown.target
```

enable the service : `systemctl enable dell-speedfanrestore.service`

