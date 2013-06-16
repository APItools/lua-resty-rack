# lua-resty-rack

A simple and extensible HTTP server framework for [OpenResty](http://openresty.org), providing a clean method for loading Lua HTTP applications ("resty" modules) into [Nginx](http://nginx.org).

Drawing inspiration from [Rack](http://rack.github.com/) and also [Connect](https://github.com/senchalabs/connect), **lua-resty-rack** allows you to load your application as a piece of middleware, alongside other middleware. Your application can either; ignore the current request, modify the request or response in some way and pass on to other middleware, or take responsibiliy for the request by generating a response.

## Status

This library is considered experimental and the API may change without notice. Please feel free to offer suggestions or raise issues here on Github.

## Installation

Copy the `rack.lua` file inside your nginx's `lib` folder and make sure it is included in the `lua_package_path` variable in `nginx.conf`.

## Using Middleware

To install middleware for a given `location`, you simply call `rack.use(middleware)` in the order you wish the modules to run, and then finally call `rack.run()`.

```nginx
server {
  location / {
    content_by_lua '
      local rack = require "rack"

      rack.use(require "my.module")
      rack.run()
    ';
  }
}
```

### `rack.use(middleware, options)`

**Syntax:** `rack.use(middleware, options?)`

The `middleware` parameter must be a callable object (like a function).
The function should accept `req`, `res`, and `options` as parameters.
See below for instructions on writing middleware.

```lua
rack.use(function(req, res)
  res.header["X-Homer"] = "Doh!"
end)
```

It's possible to chain more than one middleware by calling `rack.use` several times.


### `rack.run()`

Runs each of the middlewares in order, until the list is finished or one of the middlewares stops the pipeline (see below).

Middlewares will be executed in the same order as they were included by `rack.use()`.

Each middleware can make modifications to `req` and `res`, and the next middleware will receive them. The `options` parameter
is optional and will be the same one provided in `rack.use`.

The middleware pipeline can be halted by any middleware who whishes to do so, by returning `false`. At that moment, nginx will
just use the current contents of `res` as the final result.

Note that `res.status` is mandatory. Attempting to halt the pipeline without setting it will result in an error. If `res.status`
is "valid" (for example, 200), then `res.body` must be set to a non-empty string.

## Creating Middleware

Middleware applications are simply Lua functions (or callable objects).

```lua
-- /lib/method_override.lua

return function(req, res, options)
  local key = options['key'] or '_method'
  req.method = string.upper(req.args[key] or req.method)
end
```

## API

### `req.method`

The HTTP method, e.g. `GET`, set from `ngx.var.request_method`.

### `req.scheme`

The protocol scheme `http|https`, set from `ngx.var.scheme`.

### `req.uri`

e.g. `/my/uri`, set from `ngx.var.uri`.

### `req.host`

The hostname, e.g. `example.com`, set from `ngx.var.host`.

### `req.query`

The querystring, e.g. `var1=1&var2=2`, set from `ngx.var.query_string`.

### `req.args`

The query args, as a `table`, set from `ngx.req.get_uri_args()`.

### `req.header`

A table containing the request headers. Keys are matched case insensitvely, and optionally with underscores instead of hyphens. e.g.

```lua
req.header["X-Foo"] = "bar"
res.body = req.header.x_foo --> "bar"
```

### `req.body`

The request body. It's loaded automatically (via metatables) the first time it's requested, since it's an expensive operation. Then it is
cached. It can also be set to anything else by any middleware.

### `res.status`

The HTTP status code to return. There are [constants defined](http://wiki.nginx.org/HttpLuaModule#HTTP_status_constants) for common statuses.

### `res.header`

A table of response headers, which can be matched case insensitively and optionally with underscores instead of hyphens (see `req.header` above).

### `res.body`

The response body.

### Enhancing req / res

Your application can add new fields or even functions to the req / res tables where appropriate, which could be used by other middleware so long as the dependencies are clear (and one calls `use()` in the correct order).

## Authors

James Hurst (james@pintsized.co.uk)
Raimon Grau (raimonster@gmail.com)
Enrique García (kikito@gmail.com)

## Licence

This module is licensed under the 2-clause BSD license.

Copyright (c) 2012, James Hurst (james@pintsized.co.uk)
Copyright (c) 2013, Raimon Grau (raimonster@gmail.com)
Copyright (c) 2013, Enrique García (kikito@gmail.com)

All rights reserved.

Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

* Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
* Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
