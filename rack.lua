local rack = {}

local inspect = require 'inspect'

rack._VERSION = '0.2'

function rack.new()
  return setmetatable({middlewares = {}}, { __index = rack })
end

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
  return str:gsub("_", "-"):lower():gsub("^%l", string.upper):gsub("-%l", string.upper)
end

-- Metatable functions that, when used as metamethods:
-- * They titleize keys, so t.foo and t.Foo return the same
-- * They replace underscores by dashes ant titleizes things, so t['Foo-Bar'] returns the same as t.foo_bar
-- Internally, the keys are stored in Titled-Names format, not in underscored_names format. This makes it easier
-- to go over the headers with a loop.
local headers_index    = function(t, k) return rawget(t, normalize(k)) end
local headers_newindex = function(t, k, v) rawset(t, normalize(k), v) end

local create_headers_mt = function()
  return { __index = headers_index, __newindex = headers_newindex }
end

local function create_initial_response()
  return {
    body     = nil,
    status   = nil,
    headers  = setmetatable({}, create_headers_mt())
  }
end

----------------- PUBLIC INTERFACE ----------------------

function rack:use(f, ...)
  rack_assert(f, "Invalid middleware")
  self.middlewares[#(self.middlewares) + 1] = { f = f, args = {...} }
end

function rack:run(req)
  req = req or self:create_initial_request()
  local res = create_initial_response()

  local function next_middleware()
    local len = #(self.middlewares)
    if len == 0 then return res end

    local mw = table.remove(self.middlewares, 1)
    local res = mw.f(req, next_middleware, unpack(mw.args))
    if type(res) ~= 'table' then
      error("A middleware did not return a valid response. Check that all your middlewares return a response of type 'table'")
    end
    return res
  end

  return next_middleware()
end

function rack:respond(res)
  if not ngx.headers_sent then
    check_response(res.status, res.body)

    copy(res.headers or {}, ngx.header)
    ngx.status = res.status
    ngx.print(res.body)
    ngx.eof()
  end
end

function rack:create_initial_request()
  local query  = ngx.var.query_string or ""
  local scheme = ngx.var.scheme
  local host   = ngx.var.host

  local uri = ngx.var.request_uri:gsub('%?.*', '')
  -- uri_relative = /test?arg=true
  local uri_relative  = uri .. ngx.var.is_args .. query
  -- uri_full = http://example.com/test?arg=true
  local uri_full      =  scheme .. '://' ..  host .. uri_relative

  local headers = copy(ngx.req.get_headers(100, true))
  setmetatable(headers, create_headers_mt())

  return {
    query         = query,
    headers       = headers,
    uri_full      = uri_full,
    uri_relative  = uri_relative,
    args          = ngx.req.get_uri_args(),
    method        = ngx.var.request_method,
    scheme        = scheme,
    uri           = uri,
    host          = host
  }
end

function rack.reset()
  self.middlewares = {}
end

return rack
