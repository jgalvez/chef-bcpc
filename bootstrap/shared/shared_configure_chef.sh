#!/bin/bash
# Exit immediately if anything goes wrong, instead of making things worse.
set -e

. "$REPO_ROOT/bootstrap/shared/shared_functions.sh"

REQUIRED_VARS=( BOOTSTRAP_CHEF_DO_CONVERGE BOOTSTRAP_CHEF_ENV BCPC_HYPERVISOR_DOMAIN FILECACHE_MOUNT_POINT REPO_MOUNT_POINT REPO_ROOT )
check_for_envvars "${REQUIRED_VARS[@]}"

# This script does a lot of stuff:
# - installs Chef Server on the bootstrap node
# - installs Chef client on all nodes

# It would be more efficient as something executed in one shot on each node, but
# doing it this way makes it easy to orchestrate operations between nodes. In some cases,
# commands can be &&'d together to avoid SSHing repeatedly to a node (SSH setup/teardown
# can add a fair amount of time to this script).

cd "$REPO_ROOT/bootstrap/vagrant_scripts"

# use Chef Server embedded knife instead of the one in /usr/bin
KNIFE=/opt/opscode/embedded/bin/knife

deploy_bootstrap_node(){
  # install and configure Chef Server 12 and Chef 12 client on the bootstrap node
  # move nginx insecure to 4000/TCP is so that Cobbler can run on the regular 80/TCP
  if [[ -n "$CHEF_SERVER_DEB" ]]; then
      debpath="$FILECACHE_MOUNT_POINT/$CHEF_SERVER_DEB"
      CHEF_SERVER_INSTALL_CMD="sudo dpkg -i $debpath"
  else
      CHEF_SERVER_INSTALL_CMD="sudo dpkg -i \$(find $FILECACHE_MOUNT_POINT/ -name chef-server\*deb -not -name \*downloaded | tail -1)"
  fi
  if [[ -n "$CHEF_CLIENT_DEB" ]]; then
      debpath="$FILECACHE_MOUNT_POINT/$CHEF_CLIENT_DEB"
      CHEF_CLIENT_INSTALL_CMD="sudo dpkg -i $debpath"
  else
      CHEF_CLIENT_INSTALL_CMD="sudo dpkg -i \$(find $FILECACHE_MOUNT_POINT/ -name chef_\*deb -not -name \*downloaded | tail -1)"
  fi
  unset debpath

  # Remove configuration management software that might be preinstalled in the box
  echo "Removing pre-installed Puppet and Chef..."

  do_on_node vm-bootstrap "sudo dpkg -P puppet chef"

  echo "Installing Chef server..."

  do_on_node vm-bootstrap "$CHEF_SERVER_INSTALL_CMD \
    && sudo sh -c \"echo nginx[\'non_ssl_port\'] = 4000 > /etc/opscode/chef-server.rb\" \
    && sudo chef-server-ctl reconfigure \
    && sudo chef-server-ctl user-create admin admin admin admin@localhost.com welcome --filename /etc/opscode/admin.pem \
    && sudo chef-server-ctl org-create bcpc BCPC --association admin --filename /etc/opscode/bcpc-validator.pem \
    && sudo chmod 0644 /etc/opscode/admin.pem /etc/opscode/bcpc-validator.pem \
    && $CHEF_CLIENT_INSTALL_CMD"

  # configure knife on the bootstrap node and perform a knife bootstrap to create the bootstrap node in Chef
  echo "Configuring Knife on bootstrap node..."

  do_on_node vm-bootstrap "mkdir -p \$HOME/.chef && echo -e \"chef_server_url 'https://bcpc-vm-bootstrap.$BCPC_HYPERVISOR_DOMAIN/organizations/bcpc'\\\nvalidation_client_name 'bcpc-validator'\\\nvalidation_key '/etc/opscode/bcpc-validator.pem'\\\nnode_name 'admin'\\\nclient_key '/etc/opscode/admin.pem'\\\nknife['editor'] = 'vim'\\\ncookbook_path [ \\\"#{ENV['HOME']}/chef-bcpc/cookbooks\\\" ]\" > \$HOME/.chef/knife.rb \
    && $KNIFE ssl fetch \
    && $KNIFE bootstrap -x vagrant -P vagrant --sudo 10.0.100.3"

# install the knife-acl plugin into embedded knife, rsync the Chef repository into the non-root user
# (vagrant)'s home directory, and add the dependency cookbooks from the file cache
echo "Installing knife-acl plugin..."

do_on_node vm-bootstrap "sudo /opt/opscode/embedded/bin/gem install -l $FILECACHE_MOUNT_POINT/knife-acl-1.0.2.gem \
  && rsync -a $REPO_MOUNT_POINT/* \$HOME/chef-bcpc \
  && cp $FILECACHE_MOUNT_POINT/cookbooks/*.tar.gz \$HOME/chef-bcpc/cookbooks \
  && cd \$HOME/chef-bcpc/cookbooks && ls -1 *.tar.gz | xargs -I% tar xvzf %"

# build binaries before uploading the bcpc cookbook
# (this step will change later but using the existing build_bins script for now)
echo "Building binaries..."

do_on_node vm-bootstrap "sudo apt-get update \
  && sudo apt-get -y autoremove \
  && cd \$HOME/chef-bcpc \
  && sudo bash -c 'export FILECACHE_MOUNT_POINT=$FILECACHE_MOUNT_POINT \
  && source \$HOME/proxy_config.sh && bootstrap/shared/shared_build_bins.sh'"

# upload all cookbooks, roles and our chosen environment to the Chef server
# (cookbook upload uses the cookbook_path set when configuring knife on the bootstrap node)
do_on_node vm-bootstrap "$KNIFE cookbook upload -a \
  && cd \$HOME/chef-bcpc/roles && $KNIFE role from file *.json \
  && cd \$HOME/chef-bcpc/environments && $KNIFE environment from file $BOOTSTRAP_CHEF_ENV.json"
}


bootstrap_chef_nodes(){
# install and bootstrap Chef on cluster nodes
  echo "Installing Chef client on cluster nodes..."
  local bootstrap_cmd=":"
  local i=1
  for vm in ${vms[@]} ${mon_vms[@]}; do
    # Remove configuration management software that might be preinstalled in the box
    do_on_node "$vm" "sudo dpkg -P puppet chef"
    # Try to install a specific version, or just the latest
    if [[ -z "$CHEF_CLIENT_DEB" ]]; then
      echo "Installing latest chef-client found in $vm:$FILECACHE_MOUNT_POINT"
    fi
    do_on_node "$vm" "$CHEF_CLIENT_INSTALL_CMD"
    bootstrap_cmd+=" && $KNIFE bootstrap -x vagrant -P vagrant --sudo 10.0.100.1${i}"
    ((i+=1))
  done
  do_on_node vm-bootstrap "$bootstrap_cmd"
}


apply_environments(){
  # augment the previously configured nodes with our newly uploaded environments and roles
  local ENVIRONMENT_SET=""
  for vm in vm-bootstrap "${vms[@]}" "${mon_vms[@]}"; do
    local name=bcpc-"$vm.$BCPC_HYPERVISOR_DOMAIN"
    ENVIRONMENT_SET="$ENVIRONMENT_SET $KNIFE node environment set $name $BOOTSTRAP_CHEF_ENV && "
  done
  ENVIRONMENT_SET="$ENVIRONMENT_SET :"

  echo "Setting Chef environment on cluster nodes..."
  do_on_node vm-bootstrap "$ENVIRONMENT_SET"
}


BOOTSTRAP_NODE_ROLES="role[BCPC-Hardware-Virtual],role[BCPC-Bootstrap],recipe[bcpc::bird-false-tor]"
WORKNODE_ROLES="role[BCPC-Hardware-Virtual],role[BCPC-Worknode]"
assign_roles(){
  local num_nodes=${CLUSTER_NODES:-3}
  local num_heads=${CLUSTER_HEADS:-1}
  if (( num_heads > num_nodes )); then
    echo "Cannot have more heads ($num_heads) than cluster nodes ($num_nodes)" >&2
    exit 2
  elif (( num_heads == num_nodes )); then
    echo "WARNING: all nodes are headnodes!"
  fi

  if [[ $CLUSTER_TYPE == 'converged' ]]; then
    i=1
    cmd="$KNIFE node run_list set bcpc-vm-bootstrap.$BCPC_HYPERVISOR_DOMAIN '$BOOTSTRAP_NODE_ROLES'"
    # Note that heads are explicitly SKIPPED here
    for(( i=num_heads+1; i<=num_nodes; i++ )); do
      vm_name="bcpc-vm${i}.$BCPC_HYPERVISOR_DOMAIN"
      cmd+=" && $KNIFE node run_list set '$vm_name' '$WORKNODE_ROLES'"
    done
    do_on_node vm-bootstrap "$cmd"
  elif [[ $CLUSTER_TYPE = 'storage' ]]; then
    do_on_node vm-bootstrap "$KNIFE node run_list set bcpc-vm-bootstrap.$BCPC_HYPERVISOR_DOMAIN 'role[BCPC-Hardware-Virtual],role[BCPC-Bootstrap]' \
      && $KNIFE node run_list set bcpc-vm1.$BCPC_HYPERVISOR_DOMAIN 'role[BCPC-Hardware-Virtual],role[BCPC-CephMonitorNode]' \
      && $KNIFE node run_list set bcpc-vm2.$BCPC_HYPERVISOR_DOMAIN 'role[BCPC-Hardware-Virtual],role[BCPC-CephOSDNode]' \
      && $KNIFE node run_list set bcpc-vm3.$BCPC_HYPERVISOR_DOMAIN 'role[BCPC-Hardware-Virtual],role[BCPC-CephOSDNode]'"
  fi
}

designate_admin_clients(){
  # set bootstrap, headnodes and mon vms (if any) as admins so that they can write into the data bag
  ADMIN_SET="true && "
  for vm in vm-bootstrap "${head_node_vms[@]}" "${mon_vms[@]}"; do
    ADMIN_SET="$ADMIN_SET $KNIFE group add client bcpc-$vm.$BCPC_HYPERVISOR_DOMAIN admins && "
  done
  ADMIN_SET="$ADMIN_SET :"

  echo "Setting admin privileges for head and monitoring nodes..."

  do_on_node vm-bootstrap "$ADMIN_SET"
}

#TODO(kamidzi): why are these named with underscores?

# $1: vmname - *vagrant name* of target node
# $2: role_list - comma-separated list of roles
_apply_roles(){
  # Apply roles to a node
  #
  # Registers the role for the node on the bootstrap server
  local vmname="$1"
  local role_list="$1"
  local node="bcpc-$vmname.$BCPC_HYPERVISOR_DOMAIN"
  local cmd="$KNIFE node run_list set $node '$role_list'"

  if [[ -z "$vmname" ]] || [[ -z "$role_list" ]] ; then
    return 1 ;
  fi
  do_on_node vm-bootstrap "$cmd"
}

# $1: vmname - *vagrant name* of target node
_converge_node(){
  # Converges a single node
  local vmname="$1"
  if [[ -z "$vmname" ]] ; then
    return 1 ;
  fi
  do_on_node "$vmname" "sudo chef-client"
}

HEADNODE_ROLES="role[BCPC-Hardware-Virtual],role[BCPC-Headnode]"
converge_nodes(){
  # Clustered monitoring setup (>1 mon VM) requires completely initialized node attributes for chef to run
  # on each node successfully. If we are not converging automatically, set run_list (for mon VMs) and exit.
  # Otherwise, each mon VM needs to complete chef run first before setting the next node's run_list.
  if [[ $BOOTSTRAP_CHEF_DO_CONVERGE -eq 0 ]]; then
    local name
    for vm in "${mon_vms[@]}"; do
      do_on_node vm-bootstrap "$KNIFE node run_list set bcpc-$vm.$BCPC_HYPERVISOR_DOMAIN 'role[BCPC-Monitoring]'"
    done
    echo "BOOTSTRAP_CHEF_DO_CONVERGE is set to 0, skipping automatic convergence."
    exit 0
  else
    echo "Cheffing cluster nodes..."
    echo "* Cheffing bootstrap node"
    do_on_node vm-bootstrap "sudo chef-client"
    echo "* Cheffing headnodes"
    # $1: idx - index of headnode
    function process_head_by_index(){
      # Processes head nodes with unwound recursion
      #
      # Given index N, process N, then process N-1. In case of N<--3, process:
      # {3, (3-1)} => {3, (2)} => {3, 2, (2-1)} => {3, 2, (1)} => {3, 2, 1}
      local idx=$1
      local _name

      if [[ -z "$idx" ]]; then
        return 1
      fi
      for (( i=idx; i>0 ; i-- )); do
        _name=${head_node_vms[i]}
        _converge_node $_name
      done
    }
    for ((head_idx=0 ; head_idx < CLUSTER_HEADS ; head_idx++)); do
      name=${head_node_vms[head_idx]}
      _apply_roles "$name" $HEADNODE_ROLES
      process_head_by_index $head_idx
    done

    echo "* Cheffing worknodes"
    # TODO(kamidzi): landmine w/assumed indexing ??
    # Use indexes as heads are all at front...
    for (( i=CLUSTER_HEADS-1; i<CLUSTER_NODES ; i++ )); do
        _converge_node "${vms[i]}" &
    done

    # run on head nodes one last time to update HAProxy with work node IPs
    for vm in ${head_node_vms[@]}; do
      _converge_node $vm &
    done
    # run on bootstrap node again if it needs to be configured as a false TOR for Neutron+Calico
    _converge_node vm-bootstrap
    # HUP OpenStack services on each node to ensure everything's in a working state if converged
    if [[ $CLUSTER_TYPE == 'converged' ]]; then
      for vm in ${vms[@]}; do
        do_on_node "$vm" "sudo hup_openstack || true"
      done
    fi
    # Run chef on each mon VM before assigning next node for monitoring.
    for vm in "${mon_vms[@]}"; do
      do_on_node vm-bootstrap "$KNIFE node run_list set bcpc-$vm.$BCPC_HYPERVISOR_DOMAIN 'role[BCPC-Monitoring]'"
      _converge_node "$vm"
    done
    # Run chef on each mon VM except the last node to update cluster components
    for vm in $(echo "${mon_vms[@]}" | awk '{$NF=""}1'); do
      _converge_node "$vm"
    done

    if [ "$VERIFY_CLUSTER" = "1" ]; then
      verify_cluster
    fi
  fi
}

verify_cluster(){
  # Do rally setup at the end without polluting the main run lists
  # also this will make sure the cluster is fully provisioned and ready for sanity checks
  do_on_node vm-bootstrap "sudo chef-client -o bcpc::rally,bcpc::rally-deployments"
  if [ -z "$RALLY_SCENARIOS_DIR" ]; then
    echo "Not copying RALLY scenario files, set RALLY_SCENARIOS_DIR pointing to your custom rally scenarios repo"
  else
    OPTIONS=$(vagrant ssh-config vm-bootstrap | awk -v ORS=' ' 'NF && !/Host / {print "-o " $1 "=" $2}')
    # Remove / at the end
    RALLY_SCENARIOS_DIR="${RALLY_SCENARIOS_DIR%/}"
    rsync -avz --delete --exclude=.git -e "ssh $OPTIONS" "$RALLY_SCENARIOS_DIR" vm-bootstrap:rally
    do_on_node vm-bootstrap "sudo chef-client -o bcpc::rally-run"
  fi
}

#### main ####

# Initialize VM lists
# Take a greedy approach and assign headnodes before worknodes
# - first N nodes will be headnodes
# - remaining are worknodes
vms=()
head_node_vms=()
mon_vms=()
i=1
for(( i; i <= num_heads; i++ )); do
  head_node_vms+=( vm${i} )
done
vms=( ${head_node_vms[@]} )
for (( i; i <= CLUSTER_NODES; i++)); do
  vms+=( vm${i} )
done

for (( j=0, m=i; j < MONITORING_NODES; m++, j++ )); do
  mon_vms+=( vm${m} )
done

deploy_bootstrap_node
bootstrap_chef_nodes
apply_environments
assign_roles
designate_admin_clients
converge_nodes

