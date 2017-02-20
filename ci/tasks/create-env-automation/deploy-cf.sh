#!/usr/bin/env bash
set -e -x
source bosh-softlayer-tools/ci/tasks/utils.sh

check_param  bluemix_env_name
check_param  boshdns
check_param  bluemix_env_geo
check_param  bluemix_env_domain
check_param  bmapps_domain
check_param  router_ip
check_param  router_dal09_ip
check_param  data_center_name
check_param  private_vlan_id
check_param  public_vlan_id
check_param  stemcell
check_param  stemcell_version
check_param  main_user_name
check_param  password
check_param  ccng_pkg_os_api_key
check_param  ccng_pkg_os_temp_url_key
check_param  ccng_pkg_os_username
check_param  ccng_pkg_os_auth_url
check_param  wal_nfs_evault_pwd
check_param  wal_nfs_evault_user
check_param  cf_release
check_param  cf_release_version
check_param  cf_services_release
check_param  cf_services_release_version
check_param  cf_services_contrib_release
check_param  cf_services_contrib_release_version

deployment_dir="${PWD}/deployment"
mkdir -p $deployment_dir

tar -zxvf director-artifacts/director_artifacts.tgz -C ${deployment_dir}
cat ${deployment_dir}/director-info >> /etc/hosts
${deployment_dir}/bosh-cli* -e $(cat ${deployment_dir}/director-info |awk '{print $2}') --ca-cert <(${deployment_dir}/bosh-cli* int ${deployment_dir}/credentials.yml --path /DIRECTOR_SSL/ca ) alias-env bosh-test 
echo "Trying to login to director..."
export BOSH_CLIENT=admin
export BOSH_CLIENT_SECRET=$(${deployment_dir}/bosh-cli* int ${deployment_dir}/credentials.yml --path /DI_ADMIN_PASSWORD)
${deployment_dir}/bosh-cli* -e bosh-test login

# generate cf deployment yml file

${deployment_dir}/bosh-cli* interpolate cf-template/cf-template.yml \
                     	-v bluemix_env_name=${bluemix_env_name}\
						-v boshdns=${boshdns}\
						-v bluemix_env_geo=${bluemix_env_geo}\
						-v bluemix_env_domain=${bluemix_env_domain}\
						-v bmapps_domain=${bmapps_domain}\
						-v router_ip=${router_ip}\
						-v router_dal09_ip=${router_dal09_ip}\
						-v data_center_name=${data_center_name}\
						-v private_vlan_id=${private_vlan_id}\
						-v public_vlan_id=${public_vlan_id}\
						-v stemcell=${stemcell}\
						-v stemcell_version=${stemcell_version}\
						-v main_user_name=${main_user_name}\
						-v password=${password}\
						-v ccng_pkg_os_api_key=${ccng_pkg_os_api_key}\
						-v ccng_pkg_os_temp_url_key=${ccng_pkg_os_temp_url_key}\
						-v ccng_pkg_os_username=${ccng_pkg_os_username}\
						-v ccng_pkg_os_auth_url=${ccng_pkg_os_auth_url}\
						-v wal_nfs_evault_pwd=${wal_nfs_evault_pwd}\
						-v wal_nfs_evault_user=${wal_nfs_evault_user}\
						-v cf_release=${cf_release}\
						-v cf_release_version=${cf_release_version}\
						-v cf_services_release=${cf_services_release}\
						-v cf_services_release_version=${cf_services_release_version}\
						-v cf_services_contrib_release=${cf_services_contrib_release}\
						-v cf_services_contrib_release_version=${cf_services_contrib_release_version}\
						> ${deployment_dir}/cf-deploy.yml
						



echo "done">cf-info/cf-info

