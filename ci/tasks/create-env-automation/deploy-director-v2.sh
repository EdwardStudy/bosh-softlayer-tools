#!/usr/bin/env bash
set -e -x

source bosh-softlayer-tools/ci/tasks/utils.sh
source /etc/profile.d/chruby.sh

chruby 2.2.4

check_param SL_VM_PREFIX
check_param SL_USERNAME
check_param SL_API_KEY
check_param SL_DATACENTER
check_param SL_VLAN_PUBLIC
check_param SL_VLAN_PRIVATE

apt-get update > /dev/null 2>&1  
apt-get install -y python-pip python-dev> /dev/null 2>&1  

echo "Downloading SoftLayer CLI..."

pip install SoftLayer  >/dev/null 2>&1

echo "Using $(slcli --version)"

cat > ~/.softlayer <<EOF
[softlayer]
username = $SL_USERNAME
api_key = $SL_API_KEY
endpoint_url = https://api.softlayer.com/xmlrpc/v3.1/
timeout = 0
EOF

deployment_dir="${PWD}/deployment"
mkdir -p $deployment_dir

SL_VM_DOMAIN=${SL_VM_PREFIX}.softlayer.com

chmod +x bosh-cli-v2/bosh-cli* 

  function finish {
    echo "Final state of director deployment:"
    echo "====================================================================="
    cat ${deployment_dir}/director-deploy-state.json
    echo "====================================================================="
    echo "Director:"
    echo "====================================================================="
    cat /etc/hosts | grep "$SL_VM_DOMAIN" | tee ${deployment_dir}/director-hosts
    echo "====================================================================="
    echo "Saving config..."
    DIRECTOR_VM_ID=grep -Po '(?<=current_vm_cid": ")[^"]*' ${deployment_dir}/director-deploy-state.json
    slcli vs detail ${DIRECTOR_VM_ID} > ${deployment_dir}/director-detail
    cp bosh-cli-v2/bosh-cli* ${deployment_dir}/
    pushd ${deployment_dir}
    tar -zcvf  /tmp/director_artifacts.tgz ./ >/dev/null 2>&1
    popd
    mv /tmp/director_artifacts.tgz deploy-artifacts/
  }

trap finish ERR

echo "Using bosh-cli $(bosh-cli-v2/bosh-cli* -v)"
echo "Deploying director..."

bosh-cli-v2/bosh-cli* create-env bosh-softlayer-tools/ci/templates/director-template.yml \
                      --state=${deployment_dir}/director-deploy-state.json\
                      --vars-store ${deployment_dir}/credentials.yml \
                      -v SL_VM_PREFIX=${SL_VM_PREFIX} \
                      -v SL_VM_DOMAIN=${SL_VM_DOMAIN} \
                      -v SL_USERNAME=${SL_USERNAME} \
                      -v SL_API_KEY=${SL_API_KEY} \
                      -v SL_DATACENTER=${SL_DATACENTER} \
                      -v SL_VLAN_PUBLIC=${SL_VLAN_PUBLIC} \
                      -v SL_VLAN_PRIVATE=${SL_VLAN_PRIVATE}

echo "Trying to set target to director..."

bosh-cli-v2/bosh-cli*  -e ${SL_VM_DOMAIN} --ca-cert <(bosh-cli-v2/bosh-cli* int ${deployment_dir}/credentials.yml --path /DIRECTOR_SSL/ca ) alias-env bosh-test 

echo "Trying to login to director..."

export BOSH_CLIENT=admin
export BOSH_CLIENT_SECRET=$(bosh-cli-v2/bosh-cli* int ${deployment_dir}/credentials.yml --path /DI_ADMIN_PASSWORD

bosh-cli-v2/bosh-cli* -e bosh-test login

trap - ERR

finish







