OPENRESTY_PREFIX=/usr/local/openresty

all: test;

test:
		PATH=$(OPENRESTY_PREFIX)/nginx/sbin:$$PATH prove -r t

