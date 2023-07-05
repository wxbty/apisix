#
# Licensed to the Apache Software Foundation (ASF) under one or more
# contributor license agreements.  See the NOTICE file distributed with
# this work for additional information regarding copyright ownership.
# The ASF licenses this file to You under the Apache License, Version 2.0
# (the "License"); you may not use this file except in compliance with
# the License.  You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
use t::APISIX;

my $nginx_binary = $ENV{'TEST_NGINX_BINARY'} || 'nginx';
my $version = eval { `$nginx_binary -V 2>&1` };

if ($version !~ m/\/apisix-nginx-module/) {
    plan(skip_all => "apisix-nginx-module not installed");
} else {
    plan('no_plan');
}
log_level("warn");
$ENV{TEST_NGINX_DUBBO_PORT} ||= 1985;

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!$block->extra_yaml_config) {
        my $extra_yaml_config = <<_EOC_;
xrpc:
  protocols:
    - name: dubbo
_EOC_
        $block->set_value("extra_yaml_config", $extra_yaml_config);
    }

    my $config = $block->config // <<_EOC_;
    location /t {
        content_by_lua_block {
            ngx.req.read_body()
            local sock = ngx.socket.tcp()
            sock:settimeout(1000)
            local ok, err = sock:connect("127.0.0.1", 20880)
            if not ok then
                ngx.log(ngx.ERR, "failed to connect: ", err)
                return ngx.exit(503)
            end

            local bytes, err = sock:send(ngx.req.get_body_data())
            if not bytes then
                ngx.log(ngx.ERR, "send stream request error: ", err)
                return ngx.exit(503)
            end
            while true do
                local data, err = sock:receiveany(4096)
                if not data then
                    sock:close()
                    break
                end
                ngx.print(data)
            end
        }
    }
_EOC_

    $block->set_value("config", $config);

    if ((!defined $block->error_log) && (!defined $block->no_error_log)) {
        $block->set_value("no_error_log", "[error]\nRPC is not finished");
    }

    if (!defined $block->request) {
        $block->set_value("request", "GET /t");
    }

    $block;
});

worker_connections(1024);
run_tests;

__DATA__

=== TEST 1: init
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/stream_routes/1',
                ngx.HTTP_PUT,
                {
                    protocol = {
                        name = "dubbo"
                    },
                    upstream = {
                        nodes = {
                            ["127.0.0.1:20880"] = 1
                        },
                        type = "roundrobin"
                    }
                }
            )
            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed
--- log_level: warn


=== TEST 2: sanity
--- request eval
"GET /t
\xda\xbb\xc2\x00\x00\x00\x00\x00\x00\x00\x01\x00\x00\x00\xef\x05\x32\x2e\x30\x2e\x32\x30\x24\x6f\x72\x67\x2e\x61\x70\x61\x63\x68\x65\x2e\x64\x75\x62\x62\x6f\x2e\x62\x61\x63\x6b\x65\x6e\x64\x2e\x44\x65\x6d\x6f\x53\x65\x72\x76\x69\x63\x65\x05\x31\x2e\x30\x2e\x30\x05\x68\x65\x6c\x6c\x6f\x0f\x4c\x6a\x61\x76\x61\x2f\x75\x74\x69\x6c\x2f\x4d\x61\x70\x3b\x48\x04\x6e\x61\x6d\x65\x08\x7a\x68\x61\x6e\x67\x73\x61\x6e\x5a\x48\x04\x70\x61\x74\x68\x30\x24\x6f\x72\x67\x2e\x61\x70\x61\x63\x68\x65\x2e\x64\x75\x62\x62\x6f\x2e\x62\x61\x63\x6b\x65\x6e\x64\x2e\x44\x65\x6d\x6f\x53\x65\x72\x76\x69\x63\x65\x12\x72\x65\x6d\x6f\x74\x65\x2e\x61\x70\x70\x6c\x69\x63\x61\x74\x69\x6f\x6e\x0b\x73\x70\x2d\x63\x6f\x6e\x73\x75\x6d\x65\x20\x09\x69\x6e\x74\x65\x72\x66\x61\x63\x65\x30\x24\x6f\x72\x67\x2e\x61\x70\x61\x63\x68\x65\x2e\x64\x75\x62\x62\x6f\x2e\x62\x61\x63\x6b\x65\x6e\x64\x2e\x44\x65\x6d\x6f\x53\x65\x72\x76\x69\x63\x65\x07\x76\x65\x72\x73\x69\x6f\x6e\x05\x31\x2e\x30\x2e\x30\x07\x74\x69\x6d\x65\x6f\x75\x74\x04\x31\x30\x30\x30\x5a"
--- response_body eval
"\xda\xbb\x02\x14\x00\x00\x00\x00\x00\x00\x00\x01\x00\x00\x43\x09\x44\x80\x46\x20\x64\x75\x62\x62\x6f\x0e\x64\x75\x62\x62\x6f\x20\x73\x75\x63\x63\x65\x73\x73\x0a\x73\x74\x61\x74\x75\x73\x03\x32\x30\x30\x5a\x48\x05\x64\x75\x62\x62\x6f\x05\x32\x2e\x30\x2e\x32\x5a"
--- stream_conf_enable
