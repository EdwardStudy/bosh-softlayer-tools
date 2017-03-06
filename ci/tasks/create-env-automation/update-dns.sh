#!/usr/bin/env bash
set -e -x

source bosh-softlayer-tools/ci/tasks/utils.sh
source /etc/profile.d/chruby.sh


deployment_dir="${PWD}/deployment"
mkdir -p $deployment_dir

tar -zxvf director-artifacts/director_artifacts.tgz -C ${deployment_dir}
tar -zxvf cf-artifacts/cf_artifacts.tgz -C ${deployment_dir}

deploy_name=$(${deployment_dir}/bosh-cli* int ${deployment_dir}/cf-deploy.yml --path /name)
director_ip=$(awk '{print $1}' deployment/director-hosts)
domain1="${deploy_name}.bluemix.net"
domain2="${deploy_name}.mybluemix.net"

di_password=$(grep -w root ${deployment_dir}/director-detail|awk '{print $4}')
pg_password=$(${deployment_dir}/bosh-cli* int ${deployment_dir}/credentials.yml --path /PG_PASSWORD)
ip_ha=grep ha_proxy ${deployment_dir}/vm-info|awk '{print $4}'

cat >update_dns.sql<<EOF
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
EOF

/usr/bin/env expect<<EOF
spawn scp -o StrictHostKeyChecking=no ./update_dns.sql root@$director_ip:/tmp
expect "*?assword:*"
exp_send "$di_password\r"
expect eof
EOF

/usr/bin/env expect<<EOF
spawn ssh root@root@$director_ip <<ENDSSH
export PGPASSWORD=${pg_password}
/var/vcap/packages/postgres/bin/psql -U postgres -d bosh -a -f /tmp/update_dns.sql
ENDSSH
expect {
    "continue" { send "yes\r"; exp_continue }
    "assword:" { send "$di_password\r"; }
}



