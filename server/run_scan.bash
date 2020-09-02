#!/bin/bash

if [[ $# -eq 1 ]]; then
	ip_addr=${1}
else
	die "Invalid number of arguments"
fi

cd /root/tsunami

java -cp 'tsunami-main-0.0.2-SNAPSHOT-cli.jar:/root/tsunami/plugins/*' \
  -Dtsunami-config.location=/root/tsunami/tsunami.yaml \
  com.google.tsunami.main.cli.TsunamiCli \
  --ip-v4-target=${ip_addr} \
  --scan-results-local-output-format=JSON \
  --scan-results-local-output-filename=/tmp/tsunami-output.json
