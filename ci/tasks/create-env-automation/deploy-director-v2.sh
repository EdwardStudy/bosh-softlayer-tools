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
check_param DI_ADMIN_PASSWORD
check_param DI_HM_PASSWORD
check_param PG_PASSWORD
check_param NATS_PASSWORD
check_param BL_DIRECTOR_PASSWORD
check_param BL_AGENT_PASSWORD

echo "Start generating certifications...."

deployment_dir="${PWD}/deployment"
mkdir -p $deployment_dir

certs_dir="${deployment_dir}/certs"
mkdir -p $certs_dir

manifest_filename="director-manifest"

SL_VM_DOMAIN=${SL_VM_PREFIX}.softlayer.com

pushd $certs_dir

  echo "Generating root CA..."
  openssl genrsa -out rootCA.key 2048 yes ""  >/dev/null 2>&1

  openssl req -x509 -new -nodes -key rootCA.key -out rootCA.pem -days 99999 -subj "/C=US/O=BOSH/CN=${SL_VM_DOMAIN}" >/dev/null 2>&1

  cat rootCA.pem

  function generateCert {
    name=$1
    domain=$2
    cat >openssl-exts.conf <<-EOL
  extensions = san

  [ alternate_names ]
  DNS.1        = ${domain}

  [san]
  subjectAltName    = @alternate_names
EOL

    echo "Generating private key for ${domain}... "
    openssl genrsa -out ${name}.key 2048  >/dev/null 2>&1

    echo "Generating certificate signing request for ${domain}..."
    # golang requires to have SAN for the IP
    openssl req -new -nodes -key ${name}.key \
      -out ${name}.csr \
      -subj "/C=US/O=BOSH/CN=${domain}" >/dev/null 2>&1

    echo "Generating certificate for ${domain}..."
    openssl x509 -req -in ${name}.csr \
      -CA rootCA.pem -CAkey rootCA.key -CAcreateserial \
      -out ${name}.crt -days 99999 \
      -extfile ./openssl-exts.conf  >/dev/null 2>&1

    echo "Deleting certificate signing request and config..."
    rm ${name}.csr
    rm ./openssl-exts.conf
  }

  generateCert director ${SL_VM_DOMAIN}

popd 


chmod +x bosh-cli-v2/bosh-cli* 

  function finish {
    echo "Final state of director deployment:"
    echo "====================================================================="
    # cat ${deployment_dir}/${manifest_filename}-state.json
    echo "====================================================================="

    echo "Director:"
    echo "====================================================================="
    cat /etc/hosts | grep "$SL_VM_DOMAIN" | tee ${deployment_dir}/director-info
    echo "====================================================================="
  
    echo "Saving config..."
    cp bosh-cli-v2/bosh-cli* ${deployment_dir}/
    pushd ${deployment_dir}
    tar -zcvf  /tmp/director_artifacts.tgz ./ >/dev/null 2>&1
    popd
    mv /tmp/director_artifacts.tgz deploy-artifacts/
  }

trap finish ERR

echo "Using bosh-cli $(bosh-cli-v2/bosh-cli* -v)"
echo "Generating director manifest file..."

bosh-cli-v2/bosh-cli* create-env bosh-softlayer-tools/ci/templates/director-template.yml \
                      --vars-store ${deployment_dir}/credentials.yml \
                      -v SL_VM_PREFIX=${SL_VM_PREFIX} \
                      -v SL_VM_DOMAIN=${SL_VM_DOMAIN} \
                      -v SL_USERNAME=${SL_USERNAME} \
                      -v SL_API_KEY=${SL_API_KEY} \
                      -v SL_DATACENTER=${SL_DATACENTER} \
                      -v SL_VLAN_PUBLIC=${SL_VLAN_PUBLIC} \
                      -v SL_VLAN_PRIVATE=${SL_VLAN_PRIVATE} \
                      -v DI_ADMIN_PASSWORD=${DI_PASSWORD} \
                      -v DI_HM_PASSWORD=${DI_HM_PASSWORD} \
                      -v PG_PASSWORD=${PG_PASSWORD} \
                      -v NATS_PASSWORD=${NATS_PASSWORD} \
                      -v BL_DIRECTOR_PASSWORD=${BL_DIRECTOR_PASSWORD} \
                      -v BL_AGENT_PASSWORD=${BL_AGENT_PASSWORD} \
                      --var-file ROOT_CERT=${certs_dir}/rootCA.pem \
                      --var-file DIRECTOR_KEY=${certs_dir}/director.key \
                      --var-file DIRECTOR_CERT=${certs_dir}/director.crt 
                      
# echo "Deploying director..."
# bosh-cli-v2/bosh-cli* create-env ${deployment_dir}/director-manifest.yml                

echo "Trying to set target to director..."
bosh-cli-v2/bosh-cli*  --ca-cert ${certs_dir}/rootCA.pem alias-env ${SL_VM_PREFIX} -e ${SL_VM_DOMAIN}

trap - ERR

finish






