# LLM Gateways

Enterprise AgentGateway configuration for multiple AI providers.

## Structure

```
gateways/
├── gateway.yaml              # Main Gateway resource
├── kustomization.yaml        # Kustomize config
├── openai/
│   ├── secret.yaml          # OpenAI API key
│   ├── backend.yaml         # OpenAI backend config
│   └── route.yaml           # /openai route
├── anthropic/
│   ├── secret.yaml          # Anthropic API key
│   ├── backend.yaml         # Anthropic backend config
│   └── route.yaml           # /anthropic route
└── xai/
    ├── secret.yaml          # xAI API key
    ├── backend.yaml         # xAI backend config (Grok via OpenAI-compatible API)
    └── route.yaml           # /xai route
```

## Deployment

### Via ArgoCD (Recommended)
```bash
# Apply the main application
kubectl apply -f manifests/agentgateway/llm-gateways-application.yaml

# Or individual providers
kubectl apply -f manifests/agentgateway/openai-application.yaml
kubectl apply -f manifests/agentgateway/anthropic-application.yaml
kubectl apply -f manifests/agentgateway/xai-application.yaml
```

### Direct Application
```bash
# Via Kustomize
kubectl apply -k gateways/

# Or individual files
kubectl apply -f gateways/gateway.yaml
kubectl apply -f gateways/openai/
kubectl apply -f gateways/anthropic/
kubectl apply -f gateways/xai/
```

## Usage

Once deployed, the gateway will be available at:

- **OpenAI**: `http://gateway-ip:8080/openai/v1/chat/completions`
- **Anthropic**: `http://gateway-ip:8080/anthropic/v1/messages`
- **xAI (Grok)**: `http://gateway-ip:8080/xai/v1/chat/completions`

### Example Request
```bash
curl -X POST http://gateway-ip:8080/openai/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "gpt-4o-mini",
    "messages": [{"role": "user", "content": "Hello!"}]
  }'
```

## Configuration

### API Keys
Update the environment variables or secrets with your actual API keys:
- `$OPENAI_API_KEY`
- `$ANTHROPIC_API_KEY`
- `$XAI_API_KEY`

### Models
Default models are configured in the backend specs:
- **OpenAI**: `gpt-4o-mini`
- **Anthropic**: `claude-sonnet-4-5-20250929`
- **xAI**: `grok-4-1-fast-reasoning`

You can override models in requests or update the backend configs.