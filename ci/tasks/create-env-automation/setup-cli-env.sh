#!/usr/bin/env bash
set -e
source bosh-softlayer-tools/ci/tasks/utils.sh

check_param SL_USERNAME
check_param SL_API_KEY
check_param SL_DATACENTER

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
        -c 2 -m 2048 -d ${SL_DATACENTER} -o UBUNTU_LATEST > cli_vm_info

CLI_VM_ID=$(grep -w id cli_vm_info|awk '{print $2}')

echo "SoftLayer VM ID: $CLI_VM_ID"

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


function finish {
    echo "howing full vm info"
    slcli vs detail $CLI_VM_ID --passwords
}

trap finish ERR

CLI_VM_IP=$(grep -w public_ip cli_vm_detail|awk '{print $2}')
CLI_VM_PWD=$(slcli vs credentials $CLI_VM_ID|grep -w root|awk '{print $2}')

#Collect info of cli vm and send to s3
cat >CLI_VM_INFO<<EOF
ip $CLI_VM_IP
password $CLI_VM_PWD
EOF

echo "Generating ssh private key..."

ssh-keygen -f key.rsa -t rsa -N ''

tar zcvf CLI_VM_INFO.tgz CLI_VM_INFO key.rsa

cp CLI_VM_INFO.tgz cli-vm-info/

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

ssh -i key.rsa root@$CLI_VM_IP <<EOF
mkdir ~/deployment
tar zxvf /tmp/director_artifacts.tgz -C ~/deployment
cat ~/deployment/director-info >> /etc/hosts
chmod +X ~/deployment/bosh-cli*
echo "Trying to set target to director..."
~/deployment/bosh-cli*  -e ${SL_VM_DOMAIN} --ca-cert <(~/deployment/bosh-cli* int ~/deployment/credentials.yml --path /DIRECTOR_SSL/ca ) alias-env bosh-test 
echo "Trying to login to director..."
export BOSH_CLIENT=admin
export BOSH_CLIENT_SECRET=$(b~/deployment/bosh-cli* int ~/deployment/credentials.yml --path /DI_ADMIN_PASSWORD
bosh-cli-v2/bosh-cli* -e bosh-test login
EOF

trap - ERR

finish











