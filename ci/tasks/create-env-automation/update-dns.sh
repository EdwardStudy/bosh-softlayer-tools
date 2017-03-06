
#!/usr/bin/env bash
set -e

source bosh-softlayer-tools/ci/tasks/utils.sh
source /etc/profile.d/chruby.sh


deployment_dir="${PWD}/deployment"
mkdir -p $deployment_dir


tar -zxvf director-artifacts/director_artifacts.tgz -C ${deployment_dir}
tar -zxvf cf-artifacts/cf_artifacts.tgz -C ${deployment_dir}

domain1="ttt.test.bluemix.com"
domain2="ttt.test.mybluemix.com"
ip_ha="1.2.3.4"

cat >update_dns.sql<<EOF
DO \$\$
DECLARE new_id INTEGER;
BEGIN
    INSERT INTO domains(name, type) VALUES('$domain1', 'NATIVE');
    SELECT domains.id INTO new_id from domains where domains.name = '$domain1' ;
    INSERT INTO records(name, type, content, ttl, domain_id) VALUES('$domain1','SOA','localhost hostmaster@localhost 0 10800 604800 30', 300, new_id );
    INSERT INTO records(name, type, content, ttl, domain_id) VALUES('*.$domain1', 'A', '$ip_ha', 300, new_id);
    INSERT INTO domains(name, type) VALUES('$domain2', 'NATIVE');
    SELECT domains.id INTO new_id from domains where domains.name = '$domain2' ;
    INSERT INTO records(name, type, content, ttl, domain_id) VALUES('$domain2','SOA','localhost hostmaster@localhost 0 10800 604800 30', 300, new_id);
    INSERT INTO records(name, type, content, ttl, domain_id) VALUES('*.$domain2', 'A', '$ip_ha', 300,new_id);
END\$\$;
EOF

export PGPASSWORD=80k3wt3ciojg12ud5q2u
/var/vcap/packages/postgres/bin/psql -U postgres -d bosh -a -f ./update_dns.sql



