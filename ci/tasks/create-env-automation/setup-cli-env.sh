#!/usr/bin/env bash
set -e -x
source bosh-softlayer-tools/ci/tasks/utils.sh

check_param SL_USERNAME
check_param SL_API_KEY

apt-get update && apt-get install -y  python-pip python-dev build-essential expect >> /dev/null

echo "Using $(python -V)"

echo "Downloading SoftLayer CLI..."

pip install SoftLayer 2>&1 >> /dev/null

echo "Using $(slcli --version)"


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

while true
    do
        if [ -n $CLI_VM_ACTIVE_TRANSACTION ];then
            CLI_LAST_VM_ACTIVE_TRANSACTION=$CLI_VM_ACTIVE_TRANSACTION
        fi
        echo "$(slcli vs detail ${CLI_VM_ID} || true)" > cli_vm_detail
        CLI_VM_STATE=$(grep -w state cli_vm_detail|awk '{print $2}')
        CLI_VM_ACTIVE_TRANSACTION=$(grep -w  active_transaction cli_vm_detail|awk '{print $2}')
        if [ "$CLI_LAST_VM_ACTIVE_TRANSACTION" != "$CLI_VM_ACTIVE_TRANSACTION" ];then
            echo "waiting vm to boot and setup ... last transaction:$CLI_VM_ACTIVE_TRANSACTION"
        fi
        CLI_VM_READY=$(slcli vs ready ${CLI_VM_ID} || true) 
        if [ "$CLI_VM_READY" == "READY" ];then
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

echo "Generating ssh private key..."

ssh-keygen -f key.rsa -t rsa -N ''

cat >add-private-key.sh<<EOF
#!/usr/bin/expect -f
#
# Install RSA SSH KEY with no passphrase
#
set user [lindex \$argv 0]
set host [lindex \$argv 1]
set password [lindex \$argv 2]
spawn ssh-copy-id -i key.rsa.pub \$user@\$host

expect {
    "continue" { send "yes\n"; exp_continue }
    "assword:" { send "\$password\n"; interact }
}
EOF

chmod +x ./add-private-key.sh

./add-private-key.sh root $CLI_VM_IP $CLI_VM_PWD

scp -i key.rsa director-artifacts/director_artifacts.tgz root@$CLI_VM_IP:/tmp/director_artifacts.tgz
scp -i key.rsa bosh-cli-v2/bosh-cli* root@$CLI_VM_IP:/tmp/

ssh -i key.rsa root@$CLI_VM_IP <<EOF
uname -a
mkdir deployment
tar zxvf /tmp/director_artifacts.tgz -C ./deployment
cp /tmp/bosh-cli* ./deployment
EOF














