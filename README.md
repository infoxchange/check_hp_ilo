check_hp_ilo.pl
================

This is a Nagios plugin, for reporting and checking the normal operation of the ILO port of a HP Server

HP (brand) Servers are typically equipped with a management processor, branded 'ILO' (Integrated Lights Out).
This provides remote access and allows the server to the remotely powered on and off.

The server is (usually) unaffected if the ILO processor is faulty, hence the need to check it separately

### Prerequisites
* If you have a HP Server with an ILO Management processor,
    and
* If you have installed the HP SNMP Agents for reporting on the server health

Then this plugin is for you

### What it does

This script:
* connects to the server using SNMP version 2c using the snmpget command, and fetches the IP address of the ILO network port.
* connects to this ILO IP address using HTTPS, and checks the Title and Server headers of the HTTP response, to ensure an ILO device is present.

For the script to work properly, the HP SNMP Agents must be install and working on the server OS,
and the ILO Network port must be accessible (ie. not blocked by a firewall or VLAN access rules or IP routing rules)

The correct SNMP community string must be provided to the script (default: public)

#### Sample Output (normal)

```
OK: ILO=10.11.12.13, iLO 4, HP ILO found: HP-iLO-Server/1.30|time=0.3165
```

#### Sample Output (ILO Port not accessible)

```
CRITICAL: ILO=10.11.12.13, HTTP Error: 500 Can't connect to 10.11.12.13:443 (timeout), (!) HTTP reponse took 10.1s (> 10.0s)|time=10.1294
```
Note that the IP above is for the ILO, not the server specified by -H

#### Sample Output (SNMP not responding / wrong community string)

```
CRITICAL: ILO=not available, Timeout: No Response from 10.1.2.3:161.|time=U
```

Note that the Hostname/IP above is for the server, not the ILO

### Sample config

```
define command {
  command_name                   check-hp-ilo
  command_line                   $USER1$/check_hp_ilo.pl -H $HOSTADDRESS$ $ARG1$
}

define service {
  use                            generic-service          ; template name
  service_description            hp-ilo
  hostgroup_name                 hp-servers
  check_command                  check-hp-ilo!-c not_so_public
  stalking_options               o,w,c         ; Retain latest ILO IP address (output rarely changes)
}

define hostgroup {
  hostgroup_name                 hp-servers
}

define host {
  use                            generic-host
  name                           hp-server-0001
  hostgroups                     hp-servers
  address                        10.1.2.3
}
```


### Performance Data

This plugin measures the response time of the ILO HTTPS Response (excluding the time taken for the SNMP response).
This is the only performance data generated, and works with the default PNP4Nagios template.
