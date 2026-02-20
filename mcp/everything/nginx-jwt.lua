-- Lua middleware for nginx: JWT validate + scope RBAC
local jwt = require "resty.jwt"
local cjson = require "cjson"

local SECRET = "demo-shared-secret-123"  -- Fallback if no JWT
local JWKS_URL = "https://integrator-7147223.okta.com/oauth2/default/v1/keys"
local AUDIENCE = "api://mcp-everything"

-- /tools/list: mcp:read
-- /tools/call: check tool.name vs scopes

local jwt_obj = jwt:load_jwks(JWKS_URL)

local header = ngx.req.get_headers()["Authorization"]
if not header or not header:match("^Bearer%s+(.*)$") then
  ngx.log(ngx.ERR, "No JWT")
  ngx.status = 401
  ngx.say("Unauthorized: Missing Bearer token")
  ngx.exit(401)
end

local token = header:match("^Bearer%s+(.*)$")
local jwt_token, err = jwt_obj:verify(token)
if not jwt_token then
  ngx.log(ngx.ERR, "JWT verify failed: " .. err)
  ngx.status = 401
  ngx.say("Unauthorized: Invalid token")
  ngx.exit(401)
end

local claims = jwt_token.payload
if claims.aud ~= AUDIENCE then
  ngx.status = 401
  ngx.say("Unauthorized: Wrong audience")
  ngx.exit(401)
end

-- RBAC by path/tool
local path = ngx.var.uri
if path == "/mcp/tools/list" then
  if not claims.scp or not table.contains(claims.scp, "mcp:read") then
    ngx.status = 403
    ngx.say("Forbidden: mcp:read required")
    ngx.exit(403)
  end
elseif path == "/mcp/tools/call" then
  ngx.req.read_body()
  local body = cjson.decode(ngx.req.get_body_data())
  local tool_name = body.params.name
  local scopes = claims.scp or {}
  if table.contains(scopes, "mcp:write") or table.contains(scopes, "mcp:admin") then
    -- Allowed
  elseif tool_name:match("^list_") or tool_name:match("^get_") then
    if not table.contains(scopes, "mcp:read") then
      ngx.status = 403
      ngx.say("Forbidden: mcp:read for " .. tool_name)
      ngx.exit(403)
    end
  else
    ngx.status = 403
    ngx.say("Forbidden: No scope for " .. tool_name)
    ngx.exit(403)
  end
end

-- Pass to upstream
ngx.log(ngx.INFO, "JWT OK scopes=" .. table.concat(claims.scp, ","))
EOF