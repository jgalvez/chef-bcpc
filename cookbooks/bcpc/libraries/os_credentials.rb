# simple mapping of usernames to *local* credential files
# for overrides ; see adminrc vs admin-openrc files...
USER_CRED_FILES = {
  'admin' => '/root/admin-openrc'
}

def _get_cred_filename(username)
  basedir = '/root'
  name = File.join(basedir, username + '-openrc')
  USER_CRED_FILES[username] || name
end

def user_context_from_file(filename)
  cmd = "env - /bin/bash -c '. #{filename} && printenv'"
  res = %x( #{cmd} )
  return {} if res.empty?
  # split by '=' and create the hash
  Hash[ *(res.split("\n").collect {|stmt| var,name = stmt.split('=') }.flatten) ]
end

def user_context(username)
  filename = _get_cred_filename(username)
  environ = user_context_from_file(filename)
  if block_given?
    env(environ) do
      return yield
    end
  end
  environ
end

# For that admin context. For other admin users, can call
# user_context(admin_name) { commands }
def admin_context(&block)
  username='admin'
  user_context(username) do
    yield
  end
end
