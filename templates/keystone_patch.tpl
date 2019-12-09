{{- define "tungsten.keystone_patch" }}
#!/bin/bash

set -e
set -o pipefail
set -o xtrace

check () {
    local COMPONENT=$1
    local RETURN=0

    POD_PHASES=(`kubectl get po -l application=opencontrail,component=$COMPONENT -o jsonpath="{.items[*].status.phase}"`)

    if [ ${#POD_PHASES[@]} -eq 0 ]; then
        RETURN=1
    fi

    for phase in "${POD_PHASES[@]}"
    do
      if [ $phase != "Running" ]; then
        RETURN=1
      fi
    done

    echo $RETURN
}

# wait until the contrail-config pod is running
RET=$(check "contrail-config")
until [ $RET -eq 0 ]; do
    sleep 5
    RET=$(check "contrail-config")
done

# wait until the contrail-webui pod is running
RET=$(check "contrail-webui" "contrail-webui")
until [ $RET -eq 0 ]; do
    sleep 5
    RET=$(check "contrail-webui" "contrail-webui")
done


CONFIG_POD_NAMES=(`kubectl get po -l application=opencontrail,component=contrail-config -o jsonpath="{.items[*].metadata.name}"`)
WEBUI_POD_NAME=(`kubectl get po -l application=opencontrail,component=contrail-webui -o jsonpath="{.items[*].metadata.name}"`)

VNC_OPENSTACK_PATH='/usr/lib/python2.7/site-packages/vnc_openstack'
VNC_CONFIG_API_PATH='/usr/lib/python2.7/site-packages/vnc_cfg_api_server'
WEBUI_UTILS_FILE='/usr/src/contrail/contrail-web-core/src/serverroot/utils/common.utils.js'

# patch contrail-config-api containers
for pod_name in "${CONFIG_POD_NAMES[@]}"
do
    kubectl exec -it $pod_name -c "contrail-config-api" -- bash -c "\
    sed -i \"s/replace('-', '')/replace('-', '-')/g\" ${VNC_OPENSTACK_PATH}/__init__.py && \
    sed -i \"s/replace('-', '')/replace('-', '-')/g\" ${VNC_OPENSTACK_PATH}/neutron_plugin_db.py && \
    sed -i \"s/replace('-','')/replace('-', '-')/g\"  ${VNC_OPENSTACK_PATH}/neutron_plugin_db.py && \
    sed -i \"s/env.get('HTTP_X_PROJECT_ID')/env.get('HTTP_X_PROJECT_ID').replace('-','')/g\" ${VNC_CONFIG_API_PATH}/vnc_perms.py "

    echo "Patched contrail-config-api on pod: ${pod_name}"

done

# patch contail-webui containers
for pod_name in "${WEBUI_POD_NAME[@]}"
do
    kubectl exec -it $WEBUI_POD_NAME -c contrail-webui -- bash -c "\
    sed -i 's/exports.convertUUIDToString = convertUUIDToString;/exports.convertUUIDToString = function(x){return x};/g' $WEBUI_UTILS_FILE && \
    sed -i 's/exports.convertApiServerUUIDtoKeystoneUUID = convertApiServerUUIDtoKeystoneUUID;/exports.convertApiServerUUIDtoKeystoneUUID = function(x){return x};/g' $WEBUI_UTILS_FILE"

    echo "Patched contrail-webui on pod: ${pod_name}"
done

CONFIG_NODE_CONTAINERID_MAP=(`kubectl get po -l application=opencontrail,component=contrail-config \
-o jsonpath='{range .items[*]}{.spec.nodeName},{.status.containerStatuses[?(@.name=="contrail-config-api")].containerID}{end}'`)

WEBUI_NODE_CONTAINERID_MAP=(`kubectl get po -l application=opencontrail,component=contrail-webui \
-o jsonpath='{range .items[*]}{.spec.nodeName},{.status.containerStatuses[?(@.name=="contrail-webui")].containerID}{end}'`)

NODE_CONTAINER_MAP=( "${CONFIG_NODE_CONTAINERID_MAP[@]}" "${WEBUI_NODE_CONTAINERID_MAP[@]}")

# restart containers
for item in "${NODE_CONTAINER_MAP[@]}"
do
    IFS=','
    ARR=($item)

    NODE_NAME=`echo ${ARR[0]}`

    # remove 'docker//' from containerID
    CONTAINER_ID=`echo ${ARR[1]} | awk -F'//' '{print $2}' 2> /dev/null`

    CONFIG_NODEMGR_POD_NAME=`kubectl get po -l application=opencontrail,component=contrail-config -o jsonpath="{.items[?(@.spec.nodeName==\"$NODE_NAME\")].metadata.name}"`

    kubectl exec -it $CONFIG_NODEMGR_POD_NAME -c "contrail-config-nodemgr" -- curl -X POST --unix-socket mnt/docker.sock http://localhost/containers/$CONTAINER_ID/restart
    echo "Container ${CONTAINER_ID} has been restarted on pod ${CONFIG_NODEMGR_POD_NAME}"
done

echo "All Done!"
{{- end -}}
