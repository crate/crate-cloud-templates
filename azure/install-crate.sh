#!/bin/bash

export DEBIAN_FRONTEND=noninteractive

vmName=$1
clusterSize=$2
adminUsername=$3
adminPassword=$4
certificateFileName=$5
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
apt-get install -y apt-transport-https curl openssl

httpSql () {
  curl \
    -sS \
    -H 'Content-Type: application/json' \
    -k \
    -X POST "${1}://127.0.0.1:4200/_sql" \
    -d "{ \"stmt\": \"${2}\" }"
}

totalMem=$(awk '/MemTotal/ {print $2}' /proc/meminfo)
heap=$((totalMem/2000))
echo "CRATE_HEAP_SIZE=${heap}M" | sudo tee /etc/default/crate

mkdir -p /etc/crate

crateConfig=$(cat << CONFIG
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
)

if [ -n "$certificateFileName" ]
then
  protocol="https"
  crateConfig=$(cat << CONFIG
${crateConfig}

ssl.http.enabled: true
ssl.psql.enabled: true
ssl.keystore_filepath: /etc/crate/certificate
ssl.keystore_password: ""
ssl.keystore_key_password: ""
CONFIG
  )
else
  protocol="http"
fi

echo "$crateConfig" > /etc/crate/crate.yml

openssl pkcs12 \
  -export \
  -out /etc/crate/certificate \
  -inkey "/etc/keyVaultCertificates/${certificateFileName}" \
  -in "/etc/keyVaultCertificates/${certificateFileName}" \
  -password pass:""
chmod 644 /etc/crate/certificate

apt-get -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" install -y crate

sleep 30
httpSql "$protocol" "CREATE USER ${adminUsername} WITH (password = '${adminPassword}');"
httpSql "$protocol" "GRANT ALL PRIVILEGES TO ${adminUsername};"

chown crate:crate /etc/crate/certificate
chmod 640 /etc/crate/certificate
