#!/usr/bin/env bash
set -e -x

source bosh-softlayer-tools/ci/tasks/utils.sh

check_param CF-API
check_param CF-USERNAME
check_param CF-PASSWORD
check_param APP-API
check_param NAME_SERVER

echo CF-API
echo CF-USERNAME
echo CF-PASSWORD
echo APP-API
echo NAME_SERVER

function install_cf_cli () {
  print_title "INSTALL CF CLI..."
  curl -L "https://cli.run.pivotal.io/stable?release=linux64-binary&source=github" | tar -zx
  mv cf /usr/local/bin
  echo "cf version..."
  cf --version
}

function cf_push_cpp () {
  print_title "CF PUSH APP..."
  name_server=${NAME_SERVER}
  sed -i '1 i\nameserver '"${name_server}"'' /etc/resolv.conf
  app="cf-app/IICVisit.war"

  CF_TRACE=true cf api ${CF-API}
  CF_TRACE=true cf login -u ${CF-USERNAME} -p ${CF-PASSWORD}
  base=`dirname "$0"`
  cf push IICVisit -p ${base}/${app}
  curl iicvisit.${APP-API}/GetEnv|grep "DEA IP"
  if [ $? -eq 0 ]; then
   echo "cf push app successful!"
  else
   echo "cf push app failed!"
  fi
}

install_cf_cli

cf_push_cpp