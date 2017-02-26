#!/usr/bin/env bash
set -e
source bosh-softlayer-tools/ci/tasks/utils.sh

check_param bluemix_env_domain
check_param bosh_dns
check_param deploy_name
check_param data_center_name
check_param private_vlan_id
check_param public_vlan_id
check_param stemcell
check_param stemcell_version
check_param cf_release
check_param cf_release_version
check_param cf_services_release
check_param cf_services_release_version
check_param cf_services_contrib_release
check_param cf_services_contrib_release_version

deployment_dir="${PWD}/deployment"
mkdir -p $deployment_dir

tar -zxvf director-artifacts/director_artifacts.tgz -C ${deployment_dir}
cat ${deployment_dir}/director-hosts >> /etc/hosts
${deployment_dir}/bosh-cli* -e $(cat ${deployment_dir}/director-hosts |awk '{print $2}') --ca-cert <(${deployment_dir}/bosh-cli* int ${deployment_dir}/credentials.yml --path /DIRECTOR_SSL/ca ) alias-env bosh-test 
echo "Trying to login to director..."
export BOSH_CLIENT=admin
export BOSH_CLIENT_SECRET=$(${deployment_dir}/bosh-cli* int ${deployment_dir}/credentials.yml --path /DI_ADMIN_PASSWORD)
${deployment_dir}/bosh-cli* -e bosh-test login


director_ip=$(grep private_ip ${deployment_dir}/director-detail|awk '{print $2}')
director_pub_ip=$(grep public_ip ${deployment_dir}/director-detail|awk '{print $2}')
director_uuid=$(grep -Po '(?<=director_id": ")[^"]*' ${deployment_dir}/director-deploy-state.json)

# generate cf deployment yml file
${deployment_dir}/bosh-cli* interpolate cf-template/cf-template.yml \
							-v bluemix_env_domain=${bluemix_env_domain}\
							-v director_ip=${director_ip}\
							-v director_pub_ip=${director_pub_ip}\
							-v bosh_dns=${bosh_dns}\
							-v director_uuid=${director_uuid}\
							-v deploy_name=${deploy_name}\
							-v data_center_name=${data_center_name}\
							-v private_vlan_id=${private_vlan_id}\
							-v public_vlan_id=${public_vlan_id}\
							-v stemcell=${stemcell}\
							-v stemcell_version=${stemcell_version}\
							-v cf_release=${cf_release}\
							-v cf_release_version=${cf_release_version}\
							-v cf_services_release=${cf_services_release}\
							-v cf_services_release_version=${cf_services_release_version}\
							-v cf_services_contrib_release=${cf_services_contrib_release}\
							-v cf_services_contrib_release_version=${cf_services_contrib_release_version}\
						    > ${deployment_dir}/cf-deploy.yml

releases=$(${deployment_dir}/bosh-cli* int ${deployment_dir}/cf-deploy.yml --path /releases |grep -Po '(?<=- location: ).*')

# upload releases
while IFS= read -r line; do
  ${deployment_dir}/bosh-cli* -e bosh-test upload-release $line 
done <<< "$releases"

# upload stemcell
stemcell=$(${deployment_dir}/bosh-cli* int ${deployment_dir}/cf-deploy.yml --path /stemcell_location)
while IFS= read -r line; do
  ${deployment_dir}/bosh-cli* -e bosh-test upload-stemcell $line 
done <<< "$stemcell"

/usr/bin/env expect<<EOF
spawn ${deployment_dir}/bosh-cli-2.0.5-linux-amd64 -e bosh-test -d ${deploy_name} deploy ${deployment_dir}/cf-deploy.yml 
expect "*Continue*"
send "y"; interact 
EOF

echo "done">cf-info/cf-info

