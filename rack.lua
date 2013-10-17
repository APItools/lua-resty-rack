local rack = {}

local inspect = require 'inspect'

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

local function copy(src, dest)
  dest = dest or {}
  for k,v in pairs(src) do dest[k] = v end
  return dest
end

local function normalize(str)
  return str:gsub("_", "-"):gsub("^%l", string.upper):gsub("-%l", string.upper)
end

-- A metatable that, when applied to a table:
-- * It titleizes keys, so t.foo and t.Foo return the same
-- * It replaces underscores by dashes ant titleizes things, so t['Foo-Bar'] returns the same as t.foo_bar
-- Internally, the keys are stored in Titled-Names format, not in underscored_names format. This makes it easier
-- to go over the headers with a loop.
local headers_mt = {
  __index    = function(t, k) return rawget(t, normalize(k)) end,
  __newindex = function(t, k, v) rawset(t, normalize(k), v) end
}

-- This metatable will fill the request body with its value the first time
-- req.body is invoked. After that, it will be cached.
local bodybuilder_mt = {
  __index = function(t, k)
    if k == 'body' then
      ngx.req.read_body()
      local body = ngx.req.get_body_data()
      rawset(t, 'body', body)
      return body
    end
  end
}

local function create_initial_request()
  local query         = ngx.var.query_string or ""
  -- uri_relative = /test?arg=true
  local uri_relative  = ngx.var.uri .. ngx.var.is_args .. query
  -- uri_full = http://example.com/test?arg=true
  local uri_full      = ngx.var.scheme .. '://' .. ngx.var.host .. uri_relative

  local headers       = copy(ngx.req.get_headers(100, true))
  setmetatable(headers, headers_mt)

  return setmetatable({
  --body = (provided by the bodybuilder metatable below)
    query         = query,
    uri_full      = uri_full,
    uri_relative  = uri_relative,
    headers       = headers,
    method        = ngx.var.request_method,
    scheme        = ngx.var.scheme,
    uri           = ngx.var.uri,
    host          = ngx.var.host,
    args          = ngx.req.get_uri_args()
  }, bodybuilder_mt)
end

local function create_initial_response()
  return {
    body     = nil,
    status   = nil,
    headers  = setmetatable({}, headers_mt)
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

  local function next_middleware()
    local len = #middlewares
    if len == 0 then return res end

    local mw = table.remove(middlewares, 1)
    return mw.middleware(req, next_middleware, unpack(mw.args))
  end

  return next_middleware()
end

function rack.respond(res)
  if not ngx.headers_sent then
    check_response(res.status, res.body)

    copy(res.headers, ngx.header)
    ngx.status = res.status
    ngx.print(res.body)
    ngx.eof()
  end
end

function rack.reset()
  middlewares = {}
end

return rack
