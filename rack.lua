local rack = {}

rack._VERSION = '0.1'

local function get_ngx_middlewares()
  ngx.ctx.rack             = ngx.ctx.rack or {}
  ngx.ctx.rack.middlewares = ngx.ctx.rack.middlewares or {}
  return ngx.ctx.rack.middlewares
end

-- uri_relative = /test?arg=true
function get_ngx_uri_relative(query)
  return ngx.var.uri .. ngx.var.is_args .. query
end

-- uri_full = http://example.com/test?arg=true
function get_ngx_uri_full(uri_relative)
  return ngx.var.scheme .. '://' .. ngx.var.host .. uri_relative
end

local function get_middleware_function(mw, options)
  -- If we simply have a function, we can add that instead
  if type(mw) == "function" then return mw end
  -- If we have a 'call' function, then calling it with options should return a new function with the required params
  if type(mw) == "table" and type(mw.call) == "function" then return mw.call(options) end
  return nil
end

local function handle_ngx_response_errors(status, body)
  assert(status, "Middleware returned with no status. Perhaps you need to call next().")

  -- If we have a 5xx or a 3/4xx and no body entity, exit allowing nginx config
  -- to generate a response.
  if status >= 500 or (status >= 300 and body == nil) then
    ngx.exit(status)
  end
end

local function normalize(str)
  return str:lower():gsub("-", "_")
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

-- Runs the next middleware in the rack.
local function next_middleware()
  -- Pick each piece of middleware off in order
  local mwf = table.remove(ngx.ctx.rack.middlewares, 1)

  local req = ngx.ctx.rack.req
  local res = ngx.ctx.rack.res

  -- Call the middleware, which may itself call next().
  -- The first to return is handling the reponse.
  local post_function = mwf(req, res, next_middleware)

  if not ngx.headers_sent then
    handle_ngx_response_errors(res.status, res.body)

    for k,v in pairs(res.header) do ngx.header[k] = v end
    ngx.status = res.status
    ngx.print(res.body)
    ngx.eof()
  end

  -- Middleware may return a callable object to be called post-EOF.
  -- This code will only run for persistent connections, and is not really guaranteed
  -- to run, since browser behaviours differ. Also be aware that long running tasks
  -- may affect performance by hogging the connection.
  if post_function then post_function(req, res) end
end

-- Register some middleware to be used.
--
-- @param   string  route       Optional, dfaults to '/'.
-- @param   table   middleware  The middleware module
-- @param   table   options     Table of options for the middleware.
-- @return  void
function rack.use(middleware, options)
  local mwf = get_middleware_function(middleware, options)
  if not mwf then return nil, "Invalid middleware" end

  local middlewares = get_ngx_middlewares()
  table.insert(middlewares, mwf)
  return true
end

-- Start the rack.
function rack.run()
  -- We need a decent req / res environment to pass around middleware.
  if not ngx.ctx.rack or not ngx.ctx.rack.middlewares then
    ngx.log(ngx.ERR, "Attempted to run rack without any middleware.")
    return
  end

  local query         = ngx.var.query_string or ""
  local uri_relative  = get_ngx_uri_relative(query)
  local uri_full      = get_ngx_uri_full(uri_relative)
  local req_fallback  = function(k) return ngx.var["http_" .. k] end

  ngx.ctx.rack.req = {
    body          = "",
    query         = query,
    uri_full      = uri_full,
    uri_relative  = uri_relative,
    method        = ngx.var.request_method,
    args          = ngx.req.get_uri_args(),
    scheme        = ngx.var.scheme,
    uri           = ngx.var.uri,
    host          = ngx.var.host,
    header        = setmetatable({}, create_normalizer_mt(req_fallback))
  }

  ngx.ctx.rack.res = {
    status  = nil,
    body    = nil,
    header  = setmetatable({}, create_normalizer_mt())
  }

  next_middleware()
end

-- to prevent use of casual module global variables
setmetatable(rack, { __newindex = function (table, key, val)
  error('attempt to write to undeclared variable "' .. key .. '": ' .. debug.traceback())
end})

return rack
