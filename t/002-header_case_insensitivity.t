use Test::Nginx::Socket;
use Cwd qw(cwd);

plan tests => 6;

my $pwd = cwd();

our $HttpConfig = qq{
	lua_package_path "$pwd/?.lua;;";
};

run_tests();


__DATA__
=== TEST 1: Req headers from HTTP, all cases.
--- http_config eval: $::HttpConfig
--- config
location /t {
    content_by_lua '
        local rack  = require "rack"
        local cjson = require "cjson"
        local r     = rack.new()
        r:use(function(req, next_middleware)
            local res = next_middleware()

            res.status = 200
            local r = {
                req.headers["X-Foo"],
                req.headers["x-foo"],
                req.headers["x-fOo"],
                req.headers["x_fOo"],
                req.headers.x_fOo,
                req.headers.X_Foo,
            }
            res.body = cjson.encode(r)
            return res
        end)
        r:respond(r:run())
    ';
}
--- more_headers
X-Foo: bar
--- request
GET /t
--- response_body: ["bar","bar","bar","bar","bar","bar"]

=== TEST 2: Res headers, defined in code.
--- http_config eval: $::HttpConfig
--- config
location /t {
    content_by_lua '
        local rack  = require "rack"
        local cjson = require "cjson"
        local r     = rack.new()
        r:use(function(req, next_middleware)
            local res = next_middleware()
            res.status = 200
            res.headers["X-Foo"] = "bar"
            local r = {
                res.headers["X-Foo"],
                res.headers["x-foo"],
                res.headers["x-fOo"],
                res.headers["x_fOo"],
                res.headers.x_fOo,
                res.headers.X_Foo,
            }
            res.body = cjson.encode(r)
            return res
        end)
        r:respond(r:run())
    ';
}
--- request
GET /t
--- response_body: ["bar","bar","bar","bar","bar","bar"]

=== TEST 3: Change res headers (tests metatables)
--- http_config eval: $::HttpConfig
--- config
location /t {
    content_by_lua '
        local rack  = require "rack"
        local cjson = require "cjson"
        local r     = rack.new()
        r:use(function(req, next_middleware)
            local res = next_middleware()
            res.status = 200
            res.headers["X-Foo"] = "bar"
            res.headers.x_foo = "bars"
            return res
        end)
        r:respond(r:run())
    ';
}
--- request
GET /t
--- response_headers
X-Foo: bars
