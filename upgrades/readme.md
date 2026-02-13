# Manual upgrade 


helm upgrade -i management oci://us-docker.pkg.dev/solo-public/solo-enterprise-helm/charts/management \
--namespace agentgateway-system \
--create-namespace \
--version 0.3.4 \
--set cluster="maniak-rooster" \
--set products.agentgateway.enabled=true




## kagent

helm upgrade -i kagent-mgmt \
oci://us-docker.pkg.dev/solo-public/solo-enterprise-helm/charts/management \
-n kagent --create-namespace \
--version 0.3.4 \
-f - <<EOF
imagePullSecrets: []
cluster: kind-kagent-ent-fake-idp
global:
  imagePullPolicy: IfNotPresent
products:
  kagent:
    enabled: true
  agentregistry:
    enabled: true
service:
  type: LoadBalancer
  clusterIP: ""
clickhouse:
  enabled: true
tracing:
  verbose: true
EOF