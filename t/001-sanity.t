use Test::Nginx::Socket;
use Cwd qw(cwd);

plan tests => 10;

my $pwd = cwd();

our $HttpConfig = qq{
	lua_package_path "$pwd/?.lua;;";
};

run_tests();

__DATA__
=== TEST 1: No middleware.
--- http_config eval: $::HttpConfig
--- config
location /t {
    content_by_lua '
        local rack = require "rack"
        local r    = rack.new()
        r:respond(r:run({}))
    ';
}
--- request
GET /t
--- error_code: 500

=== TEST 2: Simple response as a function
--- http_config eval: $::HttpConfig
--- config
location /t {
    content_by_lua '
        local rack = require "rack"
        local r    = rack.new()
        r:use(function(req, next_middleware)
            local res = next_middleware()
            res.status = 200
            res.body = "Hello"
            return res
        end)
        r:respond(r:run({}))
    ';
}
--- request
GET /t
--- error_code: 200
--- response_body: Hello

=== TEST 3: Status code
--- http_config eval: $::HttpConfig
--- config
location /t {
    content_by_lua '
        local rack = require "rack"
        local r    = rack.new()
        r:use(function(req, next_middleware)
            local res = next_middleware()
            res.status = 304
            return res
        end)
        r:respond(r:run({}))
    ';
}
--- request
GET /t
--- error_code: 304

=== TEST 4: Middleware chaining
--- http_config eval: $::HttpConfig
--- config
location /t {
    content_by_lua '
        local rack = require "rack"
        local r    = rack.new()

        r:use(function(req, next_middleware)
            local res = next_middleware()
            res.status = 200
            return res
        end)
        r:use(function(req, next_middleware)
            local res = next_middleware()
            res.body = "Hello"
            return res
        end)

        r:respond(r:run({}))
    ';
}
--- request
GET /t
--- error_code: 200
--- response_body: Hello

=== TEST 5: Interruption
--- http_config eval: $::HttpConfig
--- config
location /t {
    content_by_lua '
        local rack = require "rack"
        local r    = rack.new()

        r:use(function(req, next_middleware)
            -- interrupt by not calling next_middleware
            return {
              status  = 200,
              body    = "Hello"
            }
        end)
        r:use(function(req, next_middleware)
            local res = next_middleware()
            res.body = "Goodbye"
            return res
        end)

        r:respond(r:run({}))
    ';
}
--- request
GET /t
--- response_body: Hello
--- error_code: 200

=== TEST 6: Middleware arguments
--- http_config eval: $::HttpConfig
--- config
location /t {
    content_by_lua '
        local rack = require "rack"
        local r    = rack.new()

        local replacer = function(req, next_middleware, from, to)
          local res = next_middleware()
          res.body = (res.body or ""):gsub(from, to)
          return res
        end

        r:use(replacer, "Hello", "Bye")

        r:use(function(req, next_middleware)
          local res = next_middleware()
          res.status = 200
          res.body = "Hello World"
          return res
        end)

        r:respond(r:run({}))
    ';
}
--- request
GET /t
--- error_code: 200
--- response_body: Bye World



