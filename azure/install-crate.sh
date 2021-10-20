#!/bin/bash

export DEBIAN_FRONTEND=noninteractive

vmName=$1
clusterSize=$2
adminUsername=$3
adminPassword=$4
hostname=$(hostname)

vmNames=()
for ((i = 0; i < clusterSize; i++))
do
    vmNames[i]=$(printf '"%s-%i"' "$vmName" "$i")
done
hosts=$(IFS=, ; echo "${vmNames[*]}")

wget https://cdn.crate.io/downloads/deb/DEB-GPG-KEY-crate
apt-key add DEB-GPG-KEY-crate
add-apt-repository "deb https://cdn.crate.io/downloads/deb/stable/ $(lsb_release -cs) main"
apt-get update -y
apt-get install -y apt-transport-https curl

totalMem=$(awk '/MemTotal/ {print $2}' /proc/meminfo)
heap=$((totalMem/2000))
echo "CRATE_HEAP_SIZE=${heap}M" | sudo tee /etc/default/crate

mkdir -p /etc/crate
cat << CONFIG > /etc/crate/crate.yml
node.name: "${hostname}"
auth.host_based.enabled: true
auth:
  host_based:
    config:
      0:
        user: crate
        address: _local_
        method: trust
      99:
        method: password
network.host: _site_, _local_
discovery.seed_hosts: [${hosts}]
cluster.initial_master_nodes: [${hosts}]
gateway.expected_nodes: ${clusterSize}
gateway.recover_after_nodes: ${clusterSize}
CONFIG

apt-get -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" install -y crate

sleep 30
curl -sS -H 'Content-Type: application/json' -k -X POST 'http://127.0.0.1:4200/_sql' -d "{ \"stmt\": \"CREATE USER ${adminUsername} WITH (password = '${adminPassword}');\" }"
curl -sS -H 'Content-Type: application/json' -k -X POST 'http://127.0.0.1:4200/_sql' -d "{ \"stmt\": \"GRANT ALL PRIVILEGES TO ${adminUsername};\" }"
