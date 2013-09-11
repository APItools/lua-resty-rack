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
        rack.respond(rack.run())
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
        rack.use(function(req, res)
            res.status = 200
            res.body = "Hello"
        end)
        rack.respond(rack.run())
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
        rack.use(function(req, res)
            res.status = 304
        end)
        rack.respond(rack.run())
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

        rack.use(function(req, res)
            res.status = 200
        end)
        rack.use(function(req, res)
            res.body = "Hello"
        end)

        rack.respond(rack.run())
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

        rack.use(function(req, res)
            res.status = 200
            res.body = "Hello"
            return false
        end)
        rack.use(function(req, res)
            res.body = "Goodbye"
        end)

        rack.respond(rack.run())
    ';
}
--- request
GET /t
--- error_code: 200
--- response_body: Hello

=== TEST 6: Middleware arguments
--- http_config eval: $::HttpConfig
--- config
location /t {
    content_by_lua '
        local rack = require "rack"

        local replacer = function(req, res, from, to)
          res.body = (res.body or ""):gsub(from, to)
        end

        rack.use(function(req, res)
          res.status = 200
          res.body = "Hello World"
        end)

        rack.use(replacer, "Hello", "Bye")

        rack.respond(rack.run())
    ';
}
--- request
GET /t
--- error_code: 200
--- response_body: Bye World



