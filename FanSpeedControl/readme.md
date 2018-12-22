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
## Automation with RIch Gannon's Script
source : http://richgannon.net/projects/dellfanspeed/


