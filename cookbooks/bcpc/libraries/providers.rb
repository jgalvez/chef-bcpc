
def openstack_cli
_proto = node['bcpc']['protocol']['keystone']
_dnsdomain = node['bcpc']['cluster_domain']
_port = node['bcpc']['catalog']['identity']['ports']['admin']
_uri = node['bcpc']['catalog']['identity']['uris']['admin']
admin_project_name = node['bcpc']['keystone']['admin']['project_name']
admin_role_name = node['bcpc']['keystone']['admin_role']
admin_username = node['bcpc']['keystone']['admin']['username']
admin_project_domain = node['bcpc']['keystone']['admin']['project_domain']
admin_user_domain = node['bcpc']['keystone']['admin']['user_domain']
admin_pass = get_config('keystone-local-admin-password')
auth_url = "#{_proto}://openstack.#{_dnsdomain}:#{_port}/#{_uri}/"
region = node['bcpc']['region_name']

  args =  [
    "openstack",
    "--os-compute-api-version", "2",
    "--os-username", admin_username,
    "--os-user-domain-name", admin_project_domain,
    "--os-project-name", admin_project_name,
    "--os-project-domain-name", admin_project_domain,
    "--os-auth-url", auth_url,
    "--os-region-name", region,
    "--os-password", admin_pass
  ]
  return args
end

def nova_cli
_proto = node['bcpc']['protocol']['keystone']
_dnsdomain = node['bcpc']['cluster_domain']
_port = node['bcpc']['catalog']['identity']['ports']['admin']
_uri = node['bcpc']['catalog']['identity']['uris']['admin']
admin_project_name = node['bcpc']['keystone']['admin']['project_name']
admin_role_name = node['bcpc']['keystone']['admin_role']
admin_username = node['bcpc']['keystone']['admin']['username']
admin_project_domain = node['bcpc']['keystone']['admin']['project_domain']
admin_user_domain = node['bcpc']['keystone']['admin']['user_domain']
admin_pass = get_config('keystone-local-admin-password')
auth_url = "#{_proto}://openstack.#{_dnsdomain}:#{_port}/#{_uri}/"
region = node['bcpc']['region_name']
#
  # Note the amazing lack of consistency between openstack CLI and nova CLI when it
  # comes to args e.g. "--os-user-name" vs "--os-username".
  args = [
    "nova",
    "--os-compute-api-version", "2",
    "--os-user-name", admin_username,
    "--os-user-domain-name", admin_project_domain,
    "--os-project-name", admin_project_name,
    "--os-project-domain-name", admin_project_domain,
    "--os-auth-url", auth_url,
    "--os-region-name", region,
    "--os-password", admin_pass
  ]
  return args
end
