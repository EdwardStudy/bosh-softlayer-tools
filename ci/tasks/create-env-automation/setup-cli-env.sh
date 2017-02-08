#!/usr/bin/env bash
set -e
source bosh-softlayer-tools/ci/tasks/utils.sh

check_param SL_USERNAME
check_param SL_API_KEY

echo "Using $(python -V)"

echo "Downloading SoftLayer CLI..."

pip install SoftLayer 2>&1 >> /dev/null

echo "Using $(slcli --version)"

# echo "Install expect interpreter..."

# apt-get update && apt-get install -y expect >> /dev/null

cat > ~/.softlayer <<EOF
[softlayer]
username = $SL_USERNAME
api_key = $SL_API_KEY
endpoint_url = https://api.softlayer.com/xmlrpc/v3.1/
timeout = 0
EOF

slcli -y vs create -H bosh-cli-v2-env -D softlayer.com \
        -c 2 -m 2048 -d lon02 -o UBUNTU_LATEST > cli_vm_info

CLI_VM_ID=$(grep -w id cli_vm_info|awk '{print $2}')

echo "CLI vm id : $CLI_VM_ID"

slcli vs detail $CLI_VM_ID


while true
    do
        if [ -n $CLI_VM_ACTIVE_TRANSACTION ];then
            CLI_LAST_VM_ACTIVE_TRANSACTION=$CLI_VM_ACTIVE_TRANSACTION
        fi
        slcli vs detail ${CLI_VM_ID} > cli_vm_detail
        CLI_VM_STATE=$(grep -w state cli_vm_detail|awk '{print $2}')
        CLI_VM_ACTIVE_TRANSACTION=$(grep -w  active_transaction cli_vm_detail|awk '{print $2}')
        if [ "$CLI_LAST_VM_ACTIVE_TRANSACTION" != "$CLI_VM_ACTIVE_TRANSACTION" ];then
            echo "waiting vm to boot and setup ... last transaction:$CLI_VM_ACTIVE_TRANSACTION"
        fi
        if [ "$CLI_VM_STATE" == "RUNNING" -a "$CLI_VM_ACTIVE_TRANSACTION" == "NULL" ];then
            break
        fi
        sleep 20
    done
echo "showing full vm info"
slcli vs detail $CLI_VM_ID

CLI_VM_IP=$(grep -w public_ip cli_vm_detail|awk '{print $2}')

CLI_VM_PWD=$(slcli vs credentials $CLI_VM_ID|grep -w root|awk '{print $2}')

#Collect info of cli vm and send to s3
cat >CLI_VM_INFO<<EOF
ip $CLI_VM_IP
password $CLI_VM_PWD
EOF

cp ./CLI_VM_INFO cli-vm-info/












