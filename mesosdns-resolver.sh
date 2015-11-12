#!/bin/bash

# Defaults
_portIndex=0
_separator=","
_server=""

# Alias for echo to stderr
errcho(){ >&2 echo $@; }

# Help
read -d '' _help <<- HELPEND
mesosdns-resolver.sh
--------------------
A bash script to resolve Mesos DNS SRV records to actual host:port endpoints

Options:
--------
-sn <service name> or --serviceName <service name> : (MANDATORY) The Mesos DNS service name (such as web.marathon.mesos).
-s <server ip> or --server <server ip>             : Can be use to query a specify DNS server. Uses local server by default.
-a or --all                                        : If specified, all endpoints of a service will be returned,
                                                     (with standard separator "comma").
-pi <port index> or --portIndex <port index>       : By default, the first port (index 0) will be returned.
                                                     If another port index shall be used, specify the index.
-se <separator> or --separator <separator>         : The separator to be used then concatenating multiple endpoint results
                                                     (only usable together with the --all parameter).
HELPEND

# Parse command line arguments
while [[ $# > 0 ]]
do
key="$1"

case $key in
  -h|--help)
  echo "$_help"
  exit 0
  ;;
  -sn|--serviceName)
  _serviceName="$2"
  shift # past argument
  ;;
  -s|--server)
  _server="@$2"
  shift # past argument
  ;;
  -pi|--portIndex)
  _portIndex="$2"
  shift # past argument
  ;;
  -se|--separator)
  _separator="$2"
  shift # past argument
  ;;
  -a|--all)
  _all=YES
  ;;
  *)
            # unknown option
  ;;
esac
shift # past argument or value
done

# Evaluation for the service name
if [[ ! -z "${_serviceName}" ]]; then
  IFS="."
  nameArray=( $_serviceName )
  queryServiceName="_"
  for index in "${!nameArray[@]}"
  do
    if [ "${index}" -eq "0" ]; then
      queryServiceName="${queryServiceName}${nameArray[0]}._tcp"
    else
      queryServiceName="${queryServiceName}.${nameArray[index]}"
    fi
  done
else
  errcho "Please supply a service name"
  exit 2
fi

# Set IFS to newline
IFS=$'\n'

# Use dig to get the answer section of the service name
_digResult=`dig +nocmd ${queryServiceName} SRV +noall +answer ${_server}`

# If result from above is empty, the service name cannot be resolved. Exit script.
if [[ -z "${_digResult}" ]]; then
  errcho "Service not found"
  exit 1
fi

# If dig gave us a result, service name exists. Continue.
dnshosts=($_digResult)

# Set IFS to space
IFS=' '

# Iterate dnshosts and extract node info as new array
for index in "${!dnshosts[@]}"
do
  linearray=(${dnshosts[index]})
  nodes+=("${linearray[7]}|${linearray[6]}")
done

# Sort nodes
IFS=$'\n' read -d '' -r -a sorted_nodes < <(printf '%s\n' "${nodes[@]}" | sort)

# Set to newline
IFS=$'\n'

# Read response as array
dnsips=($(dig +nocmd ${queryServiceName} SRV +noall +additional ${_server}))

# Set to space
IFS=' '

#associative array
declare -A serviceNodes

# Iterate dnsips and extract node info as new array
for index in "${!dnsips[@]}"
do
  iplinearray=(${dnsips[index]})

  if [ "${#iplinearray[@]}" -eq "4" ]; then
    serviceNodes["${iplinearray[0]}"]="${iplinearray[3]}"
  else
    serviceNodes["${iplinearray[0]}"]="${iplinearray[4]}"
  fi
done

# Keep the state
lastPortIndex=0
lastNodeName=""

# Store the endpoints in an associative array (hostname|port as key)
# and the IP address as value
declare -A endpoints

# Loop through nodes array and assign port indices and IP addresses
for index in "${!sorted_nodes[@]}"
do
  _hostname=$(echo "${sorted_nodes[index]}" | cut -d "|" -f 1)
  _port=$(echo "${sorted_nodes[index]}" | cut -d "|" -f 2)
  _ip=${serviceNodes[$_hostname]}

  if [ "${_hostname}" = "${lastNodeName}" ]; then
    lastPortIndex=$[lastPortIndex + 1]
  else
    lastPortIndex=0
    lastNodeName=${_hostname}
  fi
  endpoints["${_hostname}"|"${lastPortIndex}"]="${_ip}:${_port}"
done

# Final output
_output=""
_counter=0

# Iterate over endpoints
for key in "${!endpoints[@]}"
do

  # Determine values
  _hostname=$(echo "${key}" | cut -d "|" -f 1)
  _localPortIndex=$(echo "${key}" | cut -d "|" -f 2)

  # Check for portIndex match
  if [ "${_localPortIndex}" -eq "${_portIndex}" ]; then

    # Increase counter
    _counter=$[_counter + 1]

    # Check if --all parameter was set
    if [[ "${_all}" = "YES" ]]; then

      # First entry need no separator prefix
      if [[ "${_counter}" -eq "1" ]]; then
        _output="${endpoints[$key]}"
      else
        _output="${_output}${_separator}${endpoints[$key]}"
      fi

    else
      # Return first entry and exit
      echo "${endpoints[$key]}"
      exit 0
    fi

  fi

done

# Output for --all
echo "${_output}"
exit 0
