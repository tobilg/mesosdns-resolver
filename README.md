# mesosdns-resolver.sh

A bash script to resolve Mesos DNS SRV record to actual host:port endpoints

## Prerequisites

`dig` has to be available on the system.

## Installation

Run `curl -cL https://raw.githubusercontent.com/tobilg/mesosdns-resolver/master/mesosdns-resolver.sh > /usr/bin/mesosdns-resolver.sh && chmod +x /usr/bin/mesosdns-resolver.sh` to install the script locally.

## Usage

`mesosdns-resolver.sh [options]`

A service name has to be supplied, all other options are non-mandatory.

Options:
--------
- `-sn <service name>` or `--serviceName <service name>` : (MANDATORY) The Mesos DNS service name (such as web.marathon.mesos).  
- `-s <server ip>` or `--server <server ip>` : Can be use to query a specify DNS server. Uses local server by default.  
- `-d` or `--drill` : Use drill instead of dig for name resolution, as dig is not available in Alpine Linux (and it has a smaller footprint).  
- `-m` or `--mesosSuffix` : To resolve service groups the name suffix is needed (defaults to marathon.mesos in mesos DNS), keep in mind that the script does NOT set a default for backwards compatibility reasons.  
- `-a` or `--all` : If specified, all endpoints of a service will be returned, with standard separator "comma".  
- `-pi <port index>` or `--portIndex <port index>` : By default, the first port (index 0) will be returned. If another port index shall be used, specify the index.  
- `-se <separator>` or `--separator <separator>` : The separator to be used then concatenating multiple endpoint results (only usable together with the --all parameter).  
