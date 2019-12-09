{{- define "tungsten.rbac_install" }}
#!/bin/bash

set -o xtrace

DEFAULT_ACL="default-domain:default-api-access-list"

if [[ $# -eq 0 ]]; then
  echo "Please pass ruleset file path in arguments"
  exit -1
fi

RULESET_FILE=$1

if [[ ! -f $RULESET_FILE ]]; then
  echo "${RULESET_FILE} not found"
  exit -1
fi

CONFIG_POD_NAME=$(kubectl get po -l application=opencontrail,component=contrail-config -o jsonpath="{.items[0].metadata.name}")
USERNAME=$(kubectl exec -it $CONFIG_POD_NAME -c contrail-config-api -- printenv KEYSTONE_AUTH_ADMIN_USER | tr -d '\r')
PASSWORD=$(kubectl exec -it $CONFIG_POD_NAME -c contrail-config-api -- printenv KEYSTONE_AUTH_ADMIN_PASSWORD | tr -d '\r')
TENANT=$(kubectl exec -it $CONFIG_POD_NAME -c contrail-config-api -- printenv KEYSTONE_AUTH_ADMIN_TENANT | tr -d '\r')
SERVER_HOSTS=$(kubectl exec -it $CONFIG_POD_NAME -c contrail-config-api -- printenv CONFIG_NODES | tr -d '\r')
SERVER_PORT=$(kubectl exec -it $CONFIG_POD_NAME -c contrail-config-api -- printenv CONFIG_API_SERVER_SERVICE_PORT | tr -d '\r')

# select first config server in case of multiple servers
SERVER_HOST=$(echo "${SERVER_HOSTS%,*}")

check () {
    local RETURN=0

    STATUS_CODE=`curl -X GET -w "%{http_code}"  http://$SERVER_HOST:$SERVER_PORT -o /dev/null`

    if [ $STATUS_CODE -ne 200 ]; then
      RETURN=1
    fi

    echo $RETURN
}

# wait until the config api server starts serving requests
RET=$(check)
until [ $RET -eq 0 ]; do
    sleep 5
    RET=$(check)
done

# delete old ACL
echo "y" | kubectl exec -it $CONFIG_POD_NAME -c contrail-config-api -- python /opt/contrail/utils/rbacutil.py \
--os-username $USERNAME --os-password $PASSWORD --os-tenant-name $TENANT --server $SERVER_HOST:$SERVER_PORT \
--name $DEFAULT_ACL --op delete

# create new ACL
echo "y" |kubectl exec -it $CONFIG_POD_NAME -c contrail-config-api -- python /opt/contrail/utils/rbacutil.py \
--os-username $USERNAME --os-password $PASSWORD --os-tenant-name $TENANT --server $SERVER_HOST:$SERVER_PORT \
--name $DEFAULT_ACL --op create

# add rules
while read -r rule; do

  # skip lines starting with '#'
  if [[ $rule = \#* ]]; then
    continue
  fi

  echo "y" |kubectl exec -it $CONFIG_POD_NAME -c contrail-config-api -- python /opt/contrail/utils/rbacutil.py \
  --os-username $USERNAME --os-password $PASSWORD --os-tenant-name $TENANT --server \
  $SERVER_HOST:$SERVER_PORT --name $DEFAULT_ACL --op add-rule --rule "${rule}"
done < $RULESET_FILE

# print new ACL
echo "y" |kubectl exec -it $CONFIG_POD_NAME -c contrail-config-api -- python /opt/contrail/utils/rbacutil.py \
--os-username $USERNAME --os-password $PASSWORD --os-tenant-name $TENANT --server \
$SERVER_HOST:$SERVER_PORT --name $DEFAULT_ACL --op read

echo "All Done!"
{{- end -}}
