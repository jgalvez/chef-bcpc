name             'bcpc-bootstrap'
maintainer       'Bloomberg Finance L.P.'
maintainer_email 'bcpc@bloomberg.net'
license          'Apache 2.0'
description      'Installs/Configures bcpc-bootstrap'
long_description IO.read(File.join(File.dirname(__FILE__), 'README.md'))
version          '6.0.0'

depends          'bcpc-binary-files', '>= 6.0.0'
depends          'bcpc-foundation', '>= 6.0.0'
depends          'bcpc-openstack-common', '>= 6.0.0'
depends          'bcpc-diamond', '>= 6.0.0'
depends          'bcpc-fluentd', '>= 6.0.0'
depends          'bcpc-zabbix', '>= 6.0.0'