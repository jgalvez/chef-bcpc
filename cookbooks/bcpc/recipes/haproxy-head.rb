#
# Cookbook Name:: bcpc
# Recipe:: haproxy-head
#
# Copyright 2013, Bloomberg Finance L.P.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

include_recipe "bcpc::default"
# There is cyclical dependency upon some of checks - see /etc/xinetd.d/*chk
include_recipe "bcpc::xinetd"
include_recipe "bcpc::haproxy-common"

template "/etc/haproxy/haproxy.cfg" do
  # TODO: may need to move this def
  source "haproxy/haproxy-head.cfg.erb"
  variables(
    lazy {
      {
        :partials => {
          "haproxy/haproxy-head.mysql-galera.cfg.partial.erb" => {
            "cookbook" => "bcpc",
            "variables" => {
              :servers => get_head_nodes
            }
          },
          "haproxy/haproxy-head.keystone.cfg.partial.erb" => {
              "cookbook" => "bcpc",
              "variables" => {
                :servers => get_head_nodes
              }
          },
          "haproxy/haproxy-head.glance.cfg.partial.erb" => {
              "cookbook" => "bcpc",
              "variables" => {
                :servers => get_head_nodes
              }
          },
          "haproxy/haproxy-head.cinder.cfg.partial.erb" => {
              "cookbook" => "bcpc",
              "variables" => {
                :servers => get_head_nodes
              }
          },
          "haproxy/haproxy-head.nova.cfg.partial.erb" => {
              "cookbook" => "bcpc",
              "variables" => {
                :servers => get_head_nodes
              }
          },
          "haproxy/haproxy-head.heat.cfg.partial.erb" => {
              "cookbook" => "bcpc",
              "variables" => {
                :servers => get_head_nodes
              }
          },
          "haproxy/haproxy-head.novnc.cfg.partial.erb" => {
              "cookbook" => "bcpc",
              "variables" => {
                :servers => get_head_nodes
              }
          },
          "haproxy/haproxy-head.horizon.cfg.partial.erb" => {
              "cookbook" => "bcpc",
              "variables" => {
                :servers => get_head_nodes
              }
          },
          "haproxy/haproxy-head.rabbitmq.cfg.partial.erb" => {
              "cookbook" => "bcpc",
              "variables" => {
                :servers => get_head_nodes
              }
          },
          "haproxy/haproxy-head.radosgw.cfg.partial.erb" => {
              "cookbook" => "bcpc",
              "variables" => {
                :servers => get_head_nodes,
                :radosgw_servers => search_nodes('recipe', 'ceph-rgw')
              }
          }
        },
        :servers => get_head_nodes,
      }
    }
  )
  notifies :restart, "service[haproxy]", :immediately
  notifies :restart, "service[xinetd]", :immediately
end
