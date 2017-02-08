#!/usr/bin/env bash
set -e 

source bosh-softlayer-tools/ci/tasks/utils.sh
source /etc/profile.d/chruby.sh

chruby 2.2.4

check_param SL_VM_PREFIX
check_param SL_USERNAME
check_param SL_API_KEY
check_param SL_DATACENTER
check_param SL_VLAN_PUBLIC
check_param SL_VLAN_PRIVATE
check_param DI_USERNAME
check_param DI_PASSWORD
check_param HM_USERNAME
check_param HM_PASSWORD
check_param DI_HM_USERNAME
check_param DI_HM_PASSWORD
check_param PG_USERNAME
check_param PG_PASSWORD
check_param NATS_USERNAME
check_param NATS_PASSWORD
check_param BL_DIRECTOR_USERNAME
check_param BL_DIRECTOR_PASSWORD
check_param BL_AGENT_USERNAME
check_param BL_AGENT_PASSWORD

echo "Start generating certifications...."

deployment_dir="${PWD}/deployment"
mkdir -p $deployment_dir

certs_dir="${deployment_dir}/certs"
mkdir -p $certs_dir

manifest_filename="director-manifest.yml"

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

director_key=$(awk '{printf("          %s\n", $0)}' ${certs_dir}/director.key)
director_crt=$(awk '{printf("          %s\n", $0)}' ${certs_dir}/director.crt)
root_ca=$(awk '{printf("        %s\n", $0)}' ${certs_dir}/rootCA.pem)


cat > "${deployment_dir}/${manifest_filename}"<<EOF
---
name: bosh

releases:
- name: bosh
  url: https://bosh.io/d/github.com/cloudfoundry/bosh?v=260.6
  sha1: 22c79db2a785efa9cbc32c62b8094500e952e170
- name: bosh-softlayer-cpi
  url: https://bosh.io/d/github.com/cloudfoundry-incubator/bosh-softlayer-cpi-release?v=3.0.5
  sha1: e7eac102bf24b5c80574ffd287dff429bc8f0cd9

resource_pools:
- name: vms
  network: default
  stemcell:
    url: https://bosh.io/d/stemcells/bosh-softlayer-xen-ubuntu-trusty-go_agent?v=3312.17
    sha1: 8416bb3191065670e3220331333caecf7c23d884
  cloud_properties:
    Domain: softlayer.com
    VmNamePrefix: $VmNamePrefix
    EphemeralDiskSize: 100
    StartCpus: 4
    MaxMemory: 8192
    Datacenter:
      Name: $SL_DATACENTER
    HourlyBillingFlag: true
    PrimaryNetworkComponent:
      NetworkVlan:
        Id: $SL_VLAN_PUBLIC
    PrimaryBackendNetworkComponent:
      NetworkVlan:
        Id: $SL_VLAN_PRIVATE
    NetworkComponents:
    - MaxSpeed: 1000

disk_pools:
- name: disks
  disk_size: 40_000

networks:
- name: default
  type: dynamic
  dns: [8.8.8.8]

jobs:
- name: bosh
  instances: 1

  templates:
  - {name: nats, release: bosh}
  - {name: postgres, release: bosh}
  - {name: blobstore, release: bosh}
  - {name: director, release: bosh}
  - {name: health_monitor, release: bosh}
  - {name: powerdns, release: bosh}
  - {name: softlayer_cpi, release: bosh-softlayer-cpi}

  resource_pool: vms
  persistent_disk_pool: disks

  networks:
  - name: default

  properties:
    nats:
      address: 127.0.0.1
      user: $NATS_USERNAME
      password: $NATS_PASSWORD

    postgres: &db
      listen_address: 127.0.0.1
      host: 127.0.0.1
      user: $PG_USERNAME
      password: $PG_PASSWORD
      database: bosh
      adapter: postgres

    blobstore:
      address: 127.0.0.1
      port: 25250
      provider: dav
      director:
        user: $BL_DIRECTOR_USERNAME
        password: $BL_DIRECTOR_PASSWORD
      agent:
        user: $BL_AGENT_USERNAME
        password: $BL_AGENT_PASSWORD

    director:
      ssl:
        key: |
${director_key}
        cert: |
${director_crt}
      address: 127.0.0.1
      name: bosh
      cpi_job: softlayer_cpi
      db: *db
      user_management:
        provider: local
        local:
          users:
          - {name: $DI_USERNAME, password: $DI_PASSWORD}
          - {name: $DI_HM_USERNAME, password: $DI_HM_PASSWORD} 

    hm:
      ca_cert: |
${root_ca}
      director_account:
        user: $HM_USERNAME
        password: $HM_PASSWORD
      resurrector_enabled: true

    dns:
      address: 127.0.0.1
      domain_name: bosh
      db: *db
      webserver:
        port: 8081
        address: 0.0.0.0

    softlayer: &softlayer
      username: $SL_USERNAME
      apiKey: $SL_API_KEY

    agent: {mbus: "nats://$NATS_USERNAME:$NATS_PASSWORD@$SL_VM_DOMAIN:4222"}

    ntp: &ntp [0.pool.ntp.org, 1.pool.ntp.org]

cloud_provider:
  template: {name: softlayer_cpi, release: bosh-softlayer-cpi}

  mbus: https://$DI_USERNAME:$DI_PASSWORD@$SL_VM_DOMAIN:6868

  properties:
    softlayer: *softlayer
    agent: {mbus: "https://$DI_USERNAME:$DI_PASSWORD@SL_VM_DOMAIN:6868"}
    blobstore: {provider: local, path: /var/vcap/micro_bosh/data/cache}
    ntp: *ntp

EOF

echo "Successfully created director yaml config file!"


cat ${deployment_dir}/${manifest_filename}

chmod +x bosh-cli-v2/bosh-cli* 

echo "Using bosh-cli $(bosh-cli-v2/bosh-cli* -v)"
echo "Deploying director..."

bosh-cli-v2/bosh-cli* create-env ${deployment_dir}/${manifest_filename}

echo "showing hosts"
tee /etc/hosts ${deployment_dir}/director_hosts

echo "showing deployment status"
cat ${deployment_dir}/bosh-deploy-state.json

echo "trying to connecting director..."
bosh-cli-v2/bosh-cli*  --ca-cert ${certs_dir}/rootCA.pem alias-env ${SL_VM_DOMAIN}

echo "saving config..."

tar -jcvf ${deployment_dir} deploy-artifacts/director_artifacts.tgz

echo "All done!"





