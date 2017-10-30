def openstack_cli
  environ = user_context('admin')
  env_cmd_args = cmdline_env_args(environ)
  args =  env_cmd_args + ["openstack"]
  return args
end

def nova_cli
  environ = user_context('nova')
  env_cmd_args = cmdline_env_args(environ)
  args =  env_cmd_args + ["nova"]
  return args
end
