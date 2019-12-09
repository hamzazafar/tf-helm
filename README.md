# Multi-node Tungsten Fabric Controller Deployment

## Node Types
- Config
- Control
- Analytics

## Deployment Diagram
```


                                        Pods running on minions


     +------------------------------+  +-----------------------+  +--------------------------------+
     |                              |  |                       |  |                                |
     |  * contrail-configdb         |  | * contrail-control    |  | * contrail-analytics           |
     |                              |  |                       |  |                                |
     |                              |  |                       |  |                                |
     |  * contrail-configdb-nodemgr |  | * contrail-rabbitmq   |  | * contrail-analytics-alarm     |
     |                              |  |                       |  |                                |
     |                              |  |                       |  |                                |
     |  * contrail-config           |  | * ntpd                |  | * contrail-analytics-snmp      |
     |                              |  |                       |  |                                |
     |                              |  +-----------------------+  |                                |
     |  * contrail-config-zookeeper |                             | * contrail-analyticsdb         |
     |                              |         Minion 1            |                                |
     |                              |                             |                                |
     |  * contrail-rabbitmq         |                             | * contrail-analyticsdb-nodemgr |
     |                              |                             |                                |
     |                              |                             |                                |
     |  * contrail-redis            |                             | * contrail-rabbitmq            |
     |                              |                             |                                |
     |                              |                             |                                |
     |  * contrail-webui            |                             | * contrail-kafka               |
     |                              |                             |                                |
     |                              |                             |                                |
     |  * ntpd                      |                             | * contrail-redis               |
     |                              |                             |                                |
     +------------------------------+                             |                                |
                                                                  | * ntpd                         |
        Minion 0                                                  |                                |
                                                                  +--------------------------------+

                                                                             Minion 2



```
## Label minions
- Label minions as config, control and analytics
  ```
  kubectl label no <minion-id-0> opencontrail.org/config=enabled
  kubectl label no <minion-id-1> opencontrail.org/control=enabled
  kubectl label no <minion-id-2> opencontrail.org/analytics=enabled
  ```

- Add Redis label to Config and Analytics nodes
  ```
  kubectl label no <minion-id-0> opencontrail.org/redis=enabled
  kubectl label no <minion-id-2> opencontrail.org/redis=enabled
  ```

- Atleast Rabbit labels
  ```
  kubectl label no <minion-id-0> opencontrail.org/rabbit=enabled
  kubectl label no <minion-id-1> opencontrail.org/rabbit=enabled
  kubectl label no <minion-id-2> opencontrail.org/rabbit=enabled
  ```

- Set the IP addresses for nodes in values.yaml file


## Ingress
- Start ingress-traefik container on config and analytics nodes
  ```
  kubectl label no <minion-id> role=ingress
  ```
  
- Apply lanDB aliases for Web UI and Config API on config node (CERN Specific)
  ```
  openstack server set --property landb-alias="<WEB-UI-ALIAS>--load-1-,<CONFIG-API-ALIAS>--load-1-" <config-minion-id>
  ```
  
- Apply lanDB aliases for Analytics API on analytics node
  ```
  openstack server set --property landb-alias="<ANALYTICS-API-ALIAS>--load-1-" <analytics-minion-id>
  ```

## Deploy Helm Charts

- Update dependencies
  ```
  helm dep update tungsten
  ```

- Install helm chart
  ```
  helm install -n tungsten -f tungsten/values.yaml -f tungsten/secrets.yaml ./tungsten
  ```

## Exposed Endpoints 
contrail-webui

`http://<WEB-UI-ALIAS>.cern.ch:6050`


contrail-config-api

`http://<CONFIG-API>.cern.ch:8082`


contrail-analytics-api

`http://<ANALYTICS-API>.cern.ch:8081`


## Additional information

### Helms Hooks
1. **keystone-patch-hook**: Applies the patch for UUIDs to contrail-config-api and contrail-webui containers.
2. **rbac-ruleset-hook**: Configures the RBAC rules in `default-domain:default-access-control-list` ACL

### Steps for adding new RBAC rules
1. If you don't want to reapply the keystone patch, set `keystone_patch_hook.enable` to false in `tungsten/values.yaml`

2. Add the rules to tungsten/templates/ruleset file. The format for specifying the rule is shown below

```
<resource>.<field> role1:<crud1>,role2:<crud2>

Examples:

* admin:CRUD
virtual-network admin:CRUD
virtual-network.subnet admin:CRUD,member:R
```

3. Run the helm upgrade command, it will trigger the RBAC hook to configure rules.

4. Important: container executing rbac install script should contain kubectl binary

```
helm secrets upgrade <release-name> -f tungsten/values.yaml -f tungsten/secrets.yaml <chart-path>
```

4. Two ways of reading the latest RBAC rules.
   * Check the logs of container `rbac-ruleset-job-XXXXX`
   * Use rbacutil.py in contrail-config-api container:
     ```
     kubectl exec -it <CONFIG-POD-NAME> -c contrail-config-api -- python /opt/contrail/utils/rbacutil.py \
     --os-username <KEYSTONE-AUTH-USERNAME> \
     --os-password <KEYSTONE-AUTH-PASSWORD> \
     --os-tenant-name <KEYSTONE-AUTH-TENANT> \
     --server config-api-sdn.cern.ch:8082 \
     --name 'default-domain:default-api-access-list' \
     --op read
     ```
