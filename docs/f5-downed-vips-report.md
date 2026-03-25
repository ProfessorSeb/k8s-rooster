# Downed VIPs Report

## Summary
All F5 BIG-IP virtual servers are effectively downed because their associated pools have either no members or all members in 'down' state.

## List of VIPs
- agentgateway-oss (pool: agentgetway-oss)
- argo.rooster.maniak.io 
- dashboard-oss
- goose.maniak.com (pool: solo.maniak.com)
- k8s_iceman_argocd_vs
- k8s_iceman_kagent_vs
- k8s_iceman_vault_vs
- kagent-oss
- vs_argo_rooster_http
- vs_argo_rooster_https
- vs_github_gateway
- vs_kagent_controller
- vs_kiali
- vs_mcp_gateway
- vs_model_priority_gateway
- vs_solo_rooster
- vs_ui_rooster
- vs_vault_ui
- vs_xai_gateway
- webui-https (pool: webui-oss - members down)
- webui-oss

## Details from BIG-IP
- All VIPs have 'enabled': true
- Pools have members in 'state': 'down' or zero members
- Example from webui-oss pool: members 172.16.10.144:30694 and 172.16.10.148:30694 are down

This needs immediate attention to restore service.