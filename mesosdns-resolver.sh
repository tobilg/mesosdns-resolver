#!/bin/bash

# Defaults
_portIndex=0
_separator=","
_server=""

# Alias for echo to stderr
errcho(){ >&2 echo $@; }

# Help
#read _help << HELPEND

# Parse command line arguments
while [[ $# > 0 ]]
do
key="$1"

case $key in
  -h|--help)
  cat << HELPEND
mesosdns-resolver.sh
--------------------
A bash script to resolve Mesos DNS SRV records to actual host:port endpoints

Options:
--------
-sn <service name> or --serviceName <service name> : (MANDATORY) The Mesos DNS service name (such as web.marathon.mesos).
-s <server ip> or --server <server ip>             : Can be use to query a specify DNS server.
-d or --drill                                      : Use drill instead of dig (for Alpine Linux)
-m or --mesosSuffix                                : The mesos DNS suffix (support for service groups).
-a or --all                                        : If specified, all endpoints of a service will be returned,
                                                     (with standard separator "comma").
-pi <port index> or --portIndex <port index>       : By default, the first port (index 0) will be returned.
                                                     If another port index shall be used, specify the index.
-se <separator> or --separator <separator>         : The separator to be used then concatenating multiple endpoint results
                                                     (only usable together with the --all parameter).
HELPEND
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
  -d|--drill)
  _drill=YES
  ;;
  -m|--mesosSuffix)
  _suffix="$2"
  shift # past argument
  ;;
  *)
        # unknown option
  ;;
esac
shift # past argument or value
done

# Evaluation for the service name
if [[ ! -z "${_serviceName}" && ! -z "${_suffix}" ]]; then
  IFS="."
  nameArray=( $_serviceName )
  suffixArray=( $_suffix )
  queryServiceName="_"
  nameSections=${#nameArray[@]}
  suffixSections=${#suffixArray[@]}
  significantSections=$(( nameSections - suffixSections - 1 ))
  for index in "${!nameArray[@]}"
  do
    if [ "${index}" -eq "${significantSections}" ]; then
      queryServiceName="${queryServiceName}${nameArray[index]}._tcp"
    elif [ "${index}" -lt "${significantSections}" ]; then
      queryServiceName="${queryServiceName}${nameArray[index]}."
    else
      queryServiceName="${queryServiceName}.${nameArray[index]}"
    fi
  done
elif [[ ! -z "${_serviceName}" ]]; then
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
  echo "Please supply a service name"
  exit 1
fi

# Set IFS to newline
IFS=$'\n'

if [[ -z "${_drill}" ]]; then
  # Use dig to get the answer section of the service name
  _digResult=`dig +nocmd +tcp ${queryServiceName} SRV +noall +answer ${_server}`
else
  _digResult=`drill -t ${queryServiceName} SRV ${_server} | grep "^_" | grep SRV`
fi

# If result from above is empty, the service name cannot be resolved. Exit script.
if [[ -z "${_digResult}" ]]; then
  errcho "Service not found"
  exit 1
fi

# If dig gave us a result, service name exists. Continue.
dnsHosts=($_digResult)

# Set IFS to space
IFS=" "

# Iterate dnsHosts and extract node info as new array
for index in "${!dnsHosts[@]}"
do
  # Filter tabs characters (Mesos DNS bug?)
  lineArray=($(echo "${dnsHosts[index]}" | tr "\t" " " | tr -s " "))
  nodes+=("${lineArray[7]}|${lineArray[6]}")
done

# Sort nodes
IFS=$'\n' read -d '' -r -a sortedNodes < <(printf '%s\n' "${nodes[@]}" | sort)

# Set to newline
IFS=$'\n'

# Read response as array
if [[ -z "${_drill}" ]]; then
  dnsIps=($(dig +nocmd +tcp ${queryServiceName} SRV +noall +additional ${_server}))
else
  dnsIps=($(drill -t ${queryServiceName} SRV ${_server} | grep "^[a-zA-Z0-9_]" | grep -v SRV))
fi

# Set to space
IFS=' '

#associative array
declare -A serviceNodes

# Iterate dnsIps and extract node info as new array
for index in "${!dnsIps[@]}"
do
  # Filter tabs characters (Mesos DNS bug?)
  iplineArray=($(echo "${dnsIps[index]}" | tr "\t" " " | tr -s " "))
  # Assign endpoint to serviceNode
  serviceNodes["${iplineArray[0]}"]="${iplineArray[4]}"
done

# Keep the state
lastPortIndex=0
lastNodeName=""

# Store the endpoints in an associative array (hostname|port as key)
# and the IP address as value
declare -A endpoints

# Loop through nodes array and assign port indices and IP addresses
for index in "${!sortedNodes[@]}"
do
  _hostname=$(echo "${sortedNodes[index]}" | cut -d "|" -f 1)
  _port=$(echo "${sortedNodes[index]}" | cut -d "|" -f 2)
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
