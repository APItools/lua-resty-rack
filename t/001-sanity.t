use Test::Nginx::Socket;
use Cwd qw(cwd);

plan tests => 8;

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
        rack.run()
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
        rack.run()
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
        rack.run()
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

        rack.run()
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

        rack.run()
    ';
}
--- request
GET /t
--- error_code: 200
--- response_body: Hello


