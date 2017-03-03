#!/usr/bin/env bash
set -e
source bosh-softlayer-tools/ci/tasks/utils.sh


check_param deploy_name
check_param data_center_name
check_param private_vlan_id
check_param public_vlan_id

deployment_dir="${PWD}/deployment"
mkdir -p $deployment_dir

tar -zxvf director-artifacts/director_artifacts.tgz -C ${deployment_dir}
cat ${deployment_dir}/director-hosts >> /etc/hosts
${deployment_dir}/bosh-cli* -e $(cat ${deployment_dir}/director-hosts |awk '{print $2}') --ca-cert <(${deployment_dir}/bosh-cli* int ${deployment_dir}/credentials.yml --path /DIRECTOR_SSL/ca ) alias-env bosh-test 

director_password=$(${deployment_dir}/bosh-cli* int ${deployment_dir}/credentials.yml --path /DI_ADMIN_PASSWORD)
echo "Trying to login to director..."
export BOSH_CLIENT=admin
export BOSH_CLIENT_SECRET=${director_password}
${deployment_dir}/bosh-cli* -e bosh-test login


director_ip=$(grep private_ip ${deployment_dir}/director-detail|awk '{print $2}')
director_pub_ip=$(grep public_ip ${deployment_dir}/director-detail|awk '{print $2}')
director_uuid=$(grep -Po '(?<=director_id": ")[^"]*' ${deployment_dir}/director-deploy-state.json)

# generate cf deployment yml file
${deployment_dir}/bosh-cli* interpolate cf-template/cf-template.yml \
							-v director_password=${director_password} \
							-v director_ip=${director_ip}\
							-v director_pub_ip=${director_pub_ip}\
							-v director_uuid=${director_uuid}\
							-v deploy_name=${deploy_name}\
							-v data_center_name=${data_center_name}\
							-v private_vlan_id=${private_vlan_id}\
							-v public_vlan_id=${public_vlan_id}\
							-v cf-release=${cf_release}\
							-v cf-release-version=${cf_release_version}\
							-v cf-services-release=${cf_services_release}\
							-v cf-services-release-version=${cf_services_release_version}\
							-v cf-services-contrib-release=${cf_services_contrib_release}\
							-v cf-services-contrib-release-version=${cf_services_contrib_release_version}\
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

${deployment_dir}/bosh-cli* -n -e bosh-test -d ${deploy_name} deploy ${deployment_dir}/cf-deploy.yml --no-redact

echo "done">cf-info/cf-info

