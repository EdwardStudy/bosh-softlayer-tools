#!/usr/bin/env bash
set -e -x

source bosh-softlayer-tools/ci/tasks/utils.sh
source /etc/profile.d/chruby.sh
apt-get install expect >/dev/null 2&>1
deployment_dir="${PWD}/deployment"
mkdir -p $deployment_dir

tar -zxvf director-artifacts/director_artifacts.tgz -C ${deployment_dir}
tar -zxvf cf-artifacts/cf_artifacts.tgz -C ${deployment_dir}
tar -zxvf run-utils/run-utils.tgz -C run-utils/
di_password=$(grep -w root ${deployment_dir}/director-detail|awk '{print $4}')
deploy_name=$(${deployment_dir}/bosh-cli* int ${deployment_dir}/cf-deploy.yml --path /name)
director_ip=$(awk '{print $1}' deployment/director-hosts)
domain1="${deploy_name}.bluemix.net"
domain2="${deploy_name}.mybluemix.net"
pg_password=$(${deployment_dir}/bosh-cli* int ${deployment_dir}/credentials.yml --path /PG_PASSWORD)
ip_ha=$(grep ha_proxy ${deployment_dir}/deployed-vms|awk '{print $4}')

cat >$deployment_dir/update_dns.sh<<EOF
cat >/tmp/update_dns.sql<<ENDSQL
DO \$\$
DECLARE new_id INTEGER;
BEGIN
    INSERT INTO domains(name, type) VALUES('${domain1}', 'NATIVE');
    SELECT domains.id INTO new_id from domains where domains.name = '$domain1' ;
    INSERT INTO records(name, type, content, ttl, domain_id) VALUES('$domain1','SOA','localhost hostmaster@localhost 0 10800 604800 30', 300, new_id );
    INSERT INTO records(name, type, content, ttl, domain_id) VALUES('*.$domain1', 'A', '$ip_ha', 300, new_id);
    INSERT INTO domains(name, type) VALUES('$domain2', 'NATIVE');
    SELECT domains.id INTO new_id from domains where domains.name = '$domain2' ;
    INSERT INTO records(name, type, content, ttl, domain_id) VALUES('$domain2','SOA','localhost hostmaster@localhost 0 10800 604800 30', 300, new_id);
    INSERT INTO records(name, type, content, ttl, domain_id) VALUES('*.$domain2', 'A', '$ip_ha', 300,new_id);
END\$\$;
ENDSQL
/var/vcap/packages/postgres/bin/psql -U postgres -d bosh -a -f /tmp/update_dns.sql
EOF
pushd run-utils
echo "$director_ip" >ip_list
./run.sh -s $deployment_dir/update_dns.sh -i ip_list -p c1oudc0w -a | tee update_dns.log
popd


