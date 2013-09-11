local rack = {}

rack._VERSION = '0.2'

local function rack_assert(condition, message)
  if not condition then
    ngx.log(ngx.ERR, message)
    ngx.exit(500)
  end
end

local function check_response(status, body)
  rack_assert(status, "Rack returned with no status. Ensure that you set res.status to something in at least one of your middlewares.")

  -- If we have a 5xx or a 3/4xx and no body entity, exit allowing nginx config
  -- to generate a response.
  if status >= 500 or (status >= 300 and body == nil) then
    ngx.exit(status)
  end
end

local function normalize(str)
  return str:lower():gsub("-", "_")
end

local function copy(src, dest)
  dest = dest or {}
  for k,v in pairs(src) do dest[k] = v end
  return dest
end

-- creates a metatable that, when applied to a table, makes it normalized, which means:
-- * It lowercases keys, so t.foo and t.FOO return the same
-- * It replaces dashes by underscores, so t['foo-bar'] returns the same as t.foo_bar
-- * When fallback is provided, t['inexisting key'] will return fallback('inexisting key')
-- It is used for immunizing ngx's to browser changes on the headers of requests and responses
local function create_normalizer_mt(fallback)
  local normalized = {}

  return {
    __index = function(t, k)
      k = normalize(k)
      return normalized[k] or (fallback and fallback(k))
    end,

    __newindex = function(t, k, v)
      rawset(t, k, v)
      normalized[normalize(k)] = v
    end
  }
end

-- Fallback for the request's header, to be used on its normalizer mt
local req_fallback  = function(k) return ngx.var["http_" .. k] end

-- This metatable will fill the request body with its value the first time
-- req.body is invoked. After that, it will be cached.
local function create_bodybuilder_mt()
  return {
    __index = function(t, k)
      if k == 'body' then
        ngx.req.read_body()
        local body = ngx.req.get_body_data()
        rawset(t, 'body', body)
        return body
      end
    end
  }
end

local function create_initial_request()
  local query         = ngx.var.query_string or ""
  -- uri_relative = /test?arg=true
  local uri_relative  = ngx.var.uri .. ngx.var.is_args .. query
  -- uri_full = http://example.com/test?arg=true
  local uri_full      = ngx.var.scheme .. '://' .. ngx.var.host .. uri_relative

  local header       = copy(ngx.req.get_headers())
  setmetatable(header, create_normalizer_mt(req_fallback))

  return setmetatable({
  --body = (provided by the bodybuilder metatable below)
    query         = query,
    uri_full      = uri_full,
    uri_relative  = uri_relative,
    header        = header,
    method        = ngx.var.request_method,
    scheme        = ngx.var.scheme,
    uri           = ngx.var.uri,
    host          = ngx.var.host,
    args          = ngx.req.get_uri_args()
  }, create_bodybuilder_mt())
end

local function create_initial_response()
  return {
    body    = nil,
    status  = nil,
    header  = setmetatable({}, create_normalizer_mt())
  }
end

local middlewares = {}

----------------- PUBLIC INTERFACE ----------------------

function rack.use(middleware, ...)
  rack_assert(middleware, "Invalid middleware")
  middlewares[#middlewares + 1] = { middleware = middleware, args = {...} }
end

function rack.run()
  local req = create_initial_request()
  local res = create_initial_response()

  local mw, args
  for i=1, #middlewares do
    mw, args = middlewares[i].middleware, middlewares[i].args
    if mw(req, res, unpack(args)) == false then break end
  end

  return res
end

function rack.respond(res)
  if not ngx.headers_sent then
    check_response(res.status, res.body)

    copy(res.header, ngx.header)
    ngx.status = res.status
    ngx.print(res.body)
    ngx.eof()
  end
end

function rack.reset()
  middlewares = {}
end

return rack
