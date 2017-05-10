#!/bin/bash
#auto install openstack
#by Eric.Zhang 2017.4
############ base_Functions #############
end_install(){
if [ $? -eq 0 ];then
	echo -e "\033[32m $1 success!\033[0m"
else
	echo -e "\033[31m [ERROR] \033[0m Please cat log in $2"
	exit
fi
}
check_error(){
if [ $? -ne 0 ];then
	echo -e "\033[31m [ERROR] \033[0m Please cat log in $1"
	exit
fi
}

############ Install_Functions ##########
Init_system(){
#stop firewalld and selinux
setenforce 0 >> /tmp/init_system.log 2>&1
sed -i 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/sysconfig/selinux >> /tmp/init_system.log 2>&1
#
systemctl stop firewalld.service >> /tmp/init_system.log 2>&1
systemctl disable firewalld.service >> /tmp/init_system.log 2>&1
# dns resolve#
cat > /etc/resolv.conf <<EOF
nameserver 114.114.114.114
EOF
#add /etc/hosts
manage_ip=`ifconfig |awk 'NR==2{print $2}'`
echo "$manage_ip controller" >>/etc/hosts
#test network
ping -c 3 mirrors.aliyun.com >> /tmp/init_system.log 2>&1
check_error /tmp/init_system.log
#configure yum source
rpm -qa |grep wget &>>/tmp/init_system.log
if [ $? -ne 0 ];then
yum install wget -y &>>/tmp/init_system.log
fi
if [ ! -f /etc/yum.repos.d/Aliyun-Base.repo ];then
	mkdir -p /etc/yum.repos.d/backup
	mv /etc/yum.repos.d/*  /etc/yum.repos.d/backup >/dev/null 2>&1
	wget -O /etc/yum.repos.d/Aliyun-Base.repo http://mirrors.aliyun.com/repo/Centos-7.repo >> /tmp/init_system.log 2>&1
	check_error tmp/init_system.log
	sed -i '/extras/a enable=1' /etc/yum.repos.d/Aliyun-Base.repo &>>/tmp/init_system.log
fi
if [ ! -f /etc/yum.repos.d/CentOS-OpenStack-mitaka.repo ];then
	yum remove  centos-release-openstack-mitaka -y >> /tmp/init_system.log 2>&1
	yum install centos-release-openstack-mitaka -y >>/tmp/init_system.log 2>&1
	sed  "s/mirror\.centos\.org/mirrors.aliyun.com/g" -i /etc/yum.repos.d/*.repo
	yum clean all &>>/tmp/init_system.log 
	yum makecache  &>>/tmp/init_system.log 
fi
#install base packets
	yum install vim python-openstackclient perl net-tools wget bash-completion* -y  &>>/tmp/init_system.log
	check_error tmp/init_system.log
#

#install ntp service
yum install chrony -y &>>/tmp/init_system.log
sed -e 's/server /#&/g'  -e '/server 3.centos/aserver 202.120.2.101 iburst' -e '/#allow/aallow 0.0.0.0/0' /etc/chrony.conf -i
systemctl enable chronyd.service && systemctl start chronyd.service  &>>/tmp/init_system.log
chronyc sources  &>>/tmp/init_system.log
end_install Init_system  /tmp/init_system.log
}
######################################## Install_db_mq ######################################################################
Install_db_mq(){
#Install mariadb#
yum install mariadb mariadb-server python2-PyMySQL -y &>>/tmp/install_db_mq.log
check_error /tmp/install_db_mq.log

cat > /etc/my.cnf.d/openstack.cnf <<EOF
[mysqld]
bind-address = 0.0.0.0
default-storage-engine = innodb
innodb_file_per_table
max_connections = 4096
collation-server = utf8_general_ci
character-set-server = utf8
EOF
systemctl enable mariadb.service &>>/tmp/install_db_mq.log
systemctl start mariadb.service &>>/tmp/install_db_mq.log
sleep 3
check_error /tmp/install_db_mq.log
mysql -u root -padmin -e "show databases;"&>>/tmp/install_db_mq.log
if [ $? -ne 0 ];then
mysql -u root  -e "DELETE FROM mysql.user WHERE User='';UPDATE mysql.user SET Password=PASSWORD('admin') WHERE User='root';flush privileges;"
	check_error /tmp/install_db_mq.log
fi

systemctl restart mariadb.service &>>/tmp/install_db_mq.log
sleep 3
check_error  /tmp/install_db_mq.log

#Install rabbitMQ #
yum install rabbitmq-server -y &>>/tmp/install_db_mq.log
systemctl enable rabbitmq-server.service &>>/tmp/install_db_mq.log
systemctl start rabbitmq-server.service &>>/tmp/install_db_mq.log
sleep 3
rabbitmqctl add_user openstack admin &>>/tmp/install_db_mq.log
rabbitmqctl set_permissions openstack ".*" ".*" ".*" &>>/tmp/install_db_mq.log
check_error  /tmp/install_db_mq.log

#Install  memcache#
yum install memcached python-memcached -y &>>/tmp/install_db_mq.log
cat >/etc/sysconfig/memcached <<EOF
PORT="11211"
USER="memcached"
MAXCONN="1024"
HOST=0.0.0.0
CACHESIZE="64"
OPTIONS="-k"
EOF
systemctl enable memcached.service &>>/tmp/install_db_mq.log
systemctl start memcached.service &>>/tmp/install_db_mq.log
end_install Install_db_mq /tmp/install_db_mq.log

}

######################################## Install_keystone  ####################################################################
Install_keystone(){
mysql -ukeystone -padmin -e "use keystone;show tables;" &>>/tmp/install_keystone.log
if [ $? -ne 0 ];then
mysql -uroot  -padmin -e "CREATE DATABASE keystone;GRANT ALL PRIVILEGES ON keystone.* TO 'keystone'@'localhost' IDENTIFIED BY 'admin';GRANT ALL PRIVILEGES ON keystone.* TO 'keystone'@'%' IDENTIFIED BY 'admin';flush privileges;" &>>/tmp/install_keystone.log
check_error install_keystone.log
fi

yum install openstack-keystone httpd mod_wsgi -y &>>/tmp/install_keystone.log
check_error /tmp/install_keystone.log
mv /etc/keystone/keystone.conf /etc/keystone/keystone.conf.back &>>/tmp/install_keystone.log
cat >/etc/keystone/keystone.conf <<EOF
[DEFAULT]
admin_token = ADMIN_TOKEN

[database]
connection = mysql+pymysql://keystone:admin@controller/keystone

[token]
provider = fernet

EOF
su -s /bin/sh -c "keystone-manage db_sync" keystone &>>/tmp/install_keystone.log
check_error /tmp/install_keystone.log
keystone-manage fernet_setup --keystone-user keystone --keystone-group keystone &>>/tmp/install_keystone.log
check_error /tmp/install_keystone.log
##Configure the Apache HTTP server #
sed -e '/^ServerName /d'  -e '/# ServerName/aServerName controller' -i /etc/httpd/conf/httpd.conf &>>/tmp/install_keystone.log
check_error /tmp/install_keystone.log

cat > /etc/httpd/conf.d/wsgi-keystone.conf <<EOF
Listen 5000
Listen 35357

<VirtualHost 0.0.0.0:5000>
    WSGIDaemonProcess keystone-public processes=5 threads=1 user=keystone group=keystone display-name=%{GROUP}
    WSGIProcessGroup keystone-public
    WSGIScriptAlias / /usr/bin/keystone-wsgi-public
    WSGIApplicationGroup %{GLOBAL}
    WSGIPassAuthorization On
    ErrorLogFormat "%{cu}t %M"
    ErrorLog /var/log/httpd/keystone-error.log
    CustomLog /var/log/httpd/keystone-access.log combined

    <Directory /usr/bin>
	    Require all granted
    </Directory>
</VirtualHost>

<VirtualHost 0.0.0.0:35357>
    WSGIDaemonProcess keystone-admin processes=5 threads=1 user=keystone group=keystone display-name=%{GROUP}
    WSGIProcessGroup keystone-admin
    WSGIScriptAlias / /usr/bin/keystone-wsgi-admin
    WSGIApplicationGroup %{GLOBAL}
    WSGIPassAuthorization On
    ErrorLogFormat "%{cu}t %M"
    ErrorLog /var/log/httpd/keystone-error.log
    CustomLog /var/log/httpd/keystone-access.log combined

    <Directory /usr/bin>
        Require all granted
    </Directory>
</VirtualHost>
EOF
systemctl enable httpd.service &>>/tmp/install_keystone.log
systemctl start httpd.service &>>/tmp/install_keystone.log
check_error /tmp/install_keystone.log
#########Create a domain, projects, users, and roles#############
openstack --os-auth-url http://controller:35357/v3 --os-project-domain-name default --os-user-domain-name default \
--os-project-name admin --os-username admin --os-password admin token issue &>>/tmp/install_keystone.log
if [ $? -ne 0 ];then #### fi at line 243
cat > openstacrc <<EOF
export OS_TOKEN=ADMIN_TOKEN
export OS_URL=http://controller:35357/v3
export OS_IDENTITY_API_VERSION=3
export LC_CTYPE="en_US.UTF-8"
EOF
source openstacrc
systemctl restart httpd &>>/tmp/install_keystone.log
#### keystone service
openstack service list |grep keystone &>>/tmp/install_keystone.log
if [ $? -ne 0 ];then
	openstack service create --name keystone --description "OpenStack Identity" identity &>>/tmp/install_keystone.log
	check_error /tmp/install_keystone.log
fi
#### endpoint
openstack endpoint list |grep keystone &>>/tmp/install_keystone.log
if [ $? -ne 0 ];then
	openstack endpoint create --region RegionOne identity public http://controller:5000/v3 &>>/tmp/install_keystone.log
	check_error /tmp/install_keystone.log
	openstack endpoint create --region RegionOne identity internal http://controller:5000/v3 &>>/tmp/install_keystone.log
	openstack endpoint create --region RegionOne identity admin http://controller:35357/v3 &>>/tmp/install_keystone.log
fi
####domain
openstack domain list |grep default &>>/tmp/install_keystone.log
if [ $? -ne 0 ];then
	openstack domain create --description "Default Domain" default &>>/tmp/install_keystone.log
	check_error /tmp/install_keystone.log
fi
## admin tenant
openstack project create --domain default --description "Admin Project" admin &>>/tmp/install_keystone.log
openstack user create --domain default --password admin  admin &>>/tmp/install_keystone.log
openstack role create admin &>>/tmp/install_keystone.log
openstack role add --project admin --user admin admin &>>/tmp/install_keystone.log
## service tenant
openstack project create --domain default  --description "Service Project" service &>>/tmp/install_keystone.log
## demo tenant
openstack project create --domain default --description "Demo Project" demo &>>/tmp/install_keystone.log
openstack user create --domain default   --password admin  demo &>>/tmp/install_keystone.log
openstack role create user &>>/tmp/install_keystone.log
openstack role add --project demo --user demo user &>>/tmp/install_keystone.log

unset OS_TOKEN OS_URL
openstack --os-auth-url http://controller:35357/v3 --os-project-domain-name default --os-user-domain-name default --os-project-name admin --os-username admin --os-password admin token issue &>>/tmp/install_keystone.log
check_error /tmp/install_keystone.log
openstack --os-auth-url http://controller:5000/v3 --os-project-domain-name default --os-user-domain-name default  --os-project-name demo --os-username demo --os-password admin token issue &>>/tmp/install_keystone.log
check_error /tmp/install_keystone.log
cat >$PWD/admin-openrc <<EOF
export OS_PROJECT_DOMAIN_NAME=default
export OS_USER_DOMAIN_NAME=default
export OS_PROJECT_NAME=admin
export OS_USERNAME=admin
export OS_PASSWORD=admin
export OS_AUTH_URL=http://controller:35357/v3
export OS_IDENTITY_API_VERSION=3
export OS_IMAGE_API_VERSION=2
EOF
cp $PWD/admin-openrc /root
cat > $PWD/demo-openrc <<EOF
export OS_PROJECT_DOMAIN_NAME=default
export OS_USER_DOMAIN_NAME=default
export OS_PROJECT_NAME=demo
export OS_USERNAME=demo
export OS_PASSWORD=admin
export OS_AUTH_URL=http://controller:5000/v3
export OS_IDENTITY_API_VERSION=3
export OS_IMAGE_API_VERSION=2
EOF
cp $PWD/demo-openrc /root/demo-openrc
source  admin-openrc
openstack token issue &>>/tmp/install_keystone.log
check_error /tmp/install_keystone.log
fi ##### if at line 178
echo -e "\033[32m Install keystone success ! \n \033[0m"
}

install_glance(){
mysql -uroot -padmin -e "use glance;show tables;" &>>/tmp/install_glance.log
if [ $? -ne 0 ];then
mysql -uroot  -padmin -e "CREATE DATABASE glance;GRANT ALL PRIVILEGES ON glance.* TO 'glance'@'localhost' IDENTIFIED BY 'admin';GRANT ALL PRIVILEGES ON glance.* TO 'glance'@'%' IDENTIFIED BY 'admin';flush privileges;" &>>/tmp/install_keystone.log
check_error install_glance.log
fi
source admin-openrc
openstack endpoint list |grep image &>>/tmp/install_glance.log
if [ $? -ne 0 ];then
openstack user create --domain default --password admin  glance &>>/tmp/install_glance.log
openstack role add --project service --user glance admin &>>/tmp/install_glance.log
openstack service create --name glance --description "OpenStack Image" image &>>/tmp/install_glance.log
#### create endpoint
openstack endpoint create --region RegionOne image public http://controller:9292 &>>/tmp/install_glance.log
openstack endpoint create --region RegionOne image internal http://controller:9292 &>>/tmp/install_glance.log
openstack endpoint create --region RegionOne image admin http://controller:9292 &>>/tmp/install_glance.log
fi
yum install openstack-glance -y &>>/tmp/install_glance.log

mv /etc/glance/glance-api.conf /etc/glance/glance-api.conf.back
mv /etc/glance/glance-registry.conf /etc/glance/glance-registry.conf.back

cat > /etc/glance/glance-api.conf <<EOF
[database]
connection = mysql+pymysql://glance:admin@controller/glance
[keystone_authtoken]
auth_uri = http://controller:5000
auth_url = http://controller:35357
memcached_servers = controller:11211
auth_type = password
project_domain_name = default
user_domain_name = default
project_name = service
username = glance
password = admin

[paste_deploy]
flavor = keystone

[glance_store]
stores = file,http
default_store = file
filesystem_store_datadir = /var/lib/glance/images/
EOF
cat >/etc/glance/glance-registry.conf <<EOF

[database]
connection = mysql+pymysql://glance:admin@controller/glance

[keystone_authtoken]
auth_uri = http://controller:5000
auth_url = http://controller:35357
memcached_servers = controller:11211
auth_type = password
project_domain_name = default
user_domain_name = default
project_name = service
username = glance
password = admin

[paste_deploy]
flavor = keystone
EOF
#su -s /bin/sh/ -c 'export LC_CTYPE="en_US.UTF-8"'

su -s /bin/sh -c "glance-manage db_sync" glance &>>/tmp/install_glance.log
check_error /tmp/install_glance.log

systemctl enable openstack-glance-api.service openstack-glance-registry.service &>>/tmp/install_glance.log
check_error install_glance.log
systemctl start openstack-glance-api.service openstack-glance-registry.service &>>/tmp/install_glance.log
sleep 5
check_error install_glance.log

source admin-openrc
if [ ! -f ./cirros-0.3.4-x86_64-disk.img  ];then
	wget http://download.cirros-cloud.net/0.3.4/cirros-0.3.4-x86_64-disk.img &>>/tmp/install_glance.log
fi
openstack image create "cirros" \
  --file cirros-0.3.4-x86_64-disk.img \
  --disk-format qcow2 --container-format bare \
  --public &>>/tmp/install_glance.log 
end_install install_glance  /tmp/install_glance
}

Install_nova(){
mysql -unova -padmin -e "use nova;show tables;use nova_api;show tables;" &>>/tmp/install_nova.log
if [ $? -ne 0 ];then
mysql -uroot  -padmin -e "CREATE DATABASE nova;CREATE DATABASE nova_api;GRANT ALL PRIVILEGES ON nova.* TO 'nova'@'localhost' IDENTIFIED BY 'admin';GRANT ALL PRIVILEGES ON nova_api.* TO 'nova'@'localhost' IDENTIFIED BY 'admin';GRANT ALL PRIVILEGES ON nova.* TO 'nova'@'%' IDENTIFIED BY 'admin';flush privileges;GRANT ALL PRIVILEGES ON nova_api.* TO 'nova'@'%' IDENTIFIED BY 'admin';flush privileges;" &>>/tmp/install_nova.log
check_error install_nova.log
fi
source admin-openrc
openstack endpoint list |grep compute &>>/tmp/install_nova.log
if [ $? -ne 0 ];then
	openstack user create --domain default --password admin nova &>>/tmp/install_nova.log
	check_error /tmp/install_nova.log
	openstack role add --project service --user nova admin &>>/tmp/install_nova.log
#### create endpoint
	openstack service create --name nova --description "OpenStack Compute" compute &>>/tmp/install_nova.log
	openstack endpoint create --region RegionOne compute public http://controller:8774/v2.1/%\(tenant_id\)s &>>/tmp/install_nova.log
	openstack endpoint create --region RegionOne compute internal http://controller:8774/v2.1/%\(tenant_id\)s &>>/tmp/install_nova.log
	openstack endpoint create --region RegionOne compute admin http://controller:8774/v2.1/%\(tenant_id\)s &>>/tmp/install_nova.log
fi
yum install openstack-nova-api openstack-nova-compute openstack-nova-scheduler  openstack-nova-conductor openstack-nova-console openstack-nova-novncproxy -y &>>/tmp/install_nova.log
check_error /tmp/install_nova.log
#### backup config
mv /etc/nova/nova.conf  /etc/nova/nova.conf.back

#### write to confige
manage_ip=`ifconfig |awk 'NR==2{print $2}'`
cat >/etc/nova/nova.conf <<EOF
[DEFAULT]
enabled_apis = osapi_compute,metadata
my_ip = $manage_ip
rpc_backend = rabbit
auth_strategy = keystone
use_neutron = True
firewall_driver = nova.virt.firewall.NoopFirewallDriver
#######
#import! about inject keypair
force_config_drive = True
######

[api_database]
connection = mysql+pymysql://nova:admin@controller/nova_api

[database]
connection = mysql+pymysql://nova:admin@controller/nova

[vnc]
vncserver_listen = 0.0.0.0
enabled = True
vncserver_proxyclient_address = $manage_ip
novncproxy_base_url = http://$manage_ip:6080/vnc_auto.html

[glance]
api_servers = http://controller:9292

[oslo_concurrency]
lock_path = /var/lib/nova/tmp

[libvirt]
virt_type = kvm

[oslo_messaging_rabbit]
rabbit_host = controller
rabbit_userid = openstack
rabbit_password = admin

[keystone_authtoken]
auth_uri = http://controller:5000
auth_url = http://controller:35357
memcached_servers = controller:11211
auth_type = password
project_domain_name = default
user_domain_name = default
project_name = service
username = nova
password = admin

[neutron]
url = http://controller:9696
auth_url = http://controller:35357
auth_type = password
project_domain_name = default
user_domain_name = default
region_name = RegionOne
project_name = service
username = neutron
password = admin

service_metadata_proxy = True
metadata_proxy_shared_secret = METADATA_SECRET
EOF

#### sync database
su -s /bin/sh -c "nova-manage api_db sync" nova &>>/tmp/install_nova.log
check_error /tmp/install_nova.log
su -s /bin/sh -c "nova-manage db sync" nova &>>/tmp/install_nova.log
check_error /tmp/install_nova.log

#### check cpu
vmxnum=`egrep -c '(vmx|svm)' /proc/cpuinfo`
if [ $vmxnum -lt 1 ];then
	echo "you machine is not support KVM"
	exit
fi

###start and enable service
systemctl enable openstack-nova-api.service libvirtd.service openstack-nova-compute.service \
openstack-nova-consoleauth.service openstack-nova-scheduler.service \
openstack-nova-conductor.service openstack-nova-novncproxy.service &>>/tmp/install_nova.log
check_error /tmp/install_nova.log

systemctl start openstack-nova-api.service \
openstack-nova-consoleauth.service openstack-nova-scheduler.service libvirtd.service openstack-nova-compute.service \
openstack-nova-conductor.service openstack-nova-novncproxy.service &>>/tmp/install_nova.log
check_error /tmp/install_nova.log
sleep 5
end_install install_nova /tmp/install_nova.log
}
Install_neutron(){
mysql -uroot -padmin -e "use neutron;show tables;" &>>/tmp/install_nova.log 
if [ $? -ne 0 ];then
mysql -uroot  -padmin -e "CREATE DATABASE neutron;GRANT ALL PRIVILEGES ON neutron.* TO 'neutron'@'localhost' IDENTIFIED BY 'admin';GRANT ALL PRIVILEGES ON neutron.* TO 'neutron'@'%' IDENTIFIED BY 'admin';flush privileges;" &>>/tmp/install_neutron.log
check_error install_neutron.log
fi

source admin-openrc
openstack endpoint list |grep network &>>/tmp/install_glance.log
if [ $? -ne 0 ];then
openstack user create --domain default --password admin  neutron  &>>/tmp/install_network.log
openstack role add --project service --user neutron admin &>>/tmp/install_network.log
openstack service create --name neutron  --description "OpenStack Image" network &>>/tmp/install_glance.log
#### create endpoint
openstack endpoint create --region RegionOne network public http://controller:9696 &>>/tmp/install_neutron.log
openstack endpoint create --region RegionOne network internal http://controller:9696 &>>/tmp/install_neutron.log
openstack endpoint create --region RegionOne network admin http://controller:9696 &>>/tmp/install_neutron.log
fi
#### install neutron packects
yum install openstack-neutron openstack-neutron-ml2 openstack-neutron-openvswitch ebtables -y   &>>/tmp/install_neutron.log
check_error /tmp/install_neutron.log

#### backup configure file
mv /etc/neutron/neutron.conf /etc/neutron/neutron.conf.back  &>>/tmp/install_neutron.log
mv /etc/neutron/plugins/ml2/ml2_conf.ini /etc/neutron/plugins/ml2/ml2_conf.ini.back  &>>/tmp/install_neutron.log
mv /etc/neutron/plugins/ml2/openvswitch_agent.ini /etc/neutron/plugins/ml2/openvswitch_agent.ini.back  &>>/tmp/install_neutron.log
mv /etc/neutron/l3_agent.ini /etc/neutron/l3_agent.ini.back  &>>/tmp/install_neutron.log
mv /etc/neutron/dhcp_agent.ini /etc/neutron/dhcp_agent.ini.back  &>>/tmp/install_neutron.log
mv /etc/neutron/metadata_agent.ini /etc/neutron/metadata_agent.ini.back  &>>/tmp/install_neutron.log
#### write configure file
cat >/etc/neutron/neutron.conf <<EOF
[DEFAULT]
core_plugin = ml2
service_plugins = router
allow_overlapping_ips = True
rpc_backend = rabbit
auth_strategy = keystone
notify_nova_on_port_status_changes = True
notify_nova_on_port_data_changes = True

[database]
connection = mysql+pymysql://neutron:admin@controller/neutron

[oslo_messaging_rabbit]
rabbit_host = controller
rabbit_userid = openstack
rabbit_password = admin

[keystone_authtoken]
auth_uri = http://controller:5000
auth_url = http://controller:35357
memcached_servers = controller:11211
auth_type = password
project_domain_name = default
user_domain_name = default
project_name = service
username = neutron
password = admin

[oslo_concurrency]
lock_path = /var/lib/neutron/tmp

[nova]
auth_url = http://controller:35357
auth_type = password
project_domain_name = default
user_domain_name = default
region_name = RegionOne
project_name = service
username = nova
password = admin
EOF
####
cat >/etc/neutron/plugins/ml2/ml2_conf.ini <<EOF
[ml2]
type_drivers = flat,vlan,vxlan
tenant_network_types = vxlan
mechanism_drivers = openvswitch,l2population
extension_drivers = port_security

[ml2_type_flat]
flat_networks = provider
[ml2_type_vxlan]
vni_ranges = 1:1000

[securitygroup]
enable_ipset = True
EOF
####
manage_ip=`ifconfig |awk 'NR==2{print $2}'`
cat >/etc/neutron/plugins/ml2/openvswitch_agent.ini <<EOF
[ovs]
local_ip = $manage_ip
bridge_mappings = external:br-ex
# Example: bridge_mappings = physnet1:br-eth1

use_veth_interconnection = False

[agent]
tunnel_types = vxlan
# vxlan_udp_port =
# Example: vxlan_udp_port = 8472
l2_population = True
# arp_responder = False
# vxlan_udp_port =
# Example: vxlan_udp_port = 8472

# log_agent_heartbeats = False

polling_interval = 5
prevent_arp_spoofing = False

# minimize_polling = True

# When minimize_polling = True, the number of seconds to wait before
# respawning the ovsdb monitor after losing communication with it
# ovsdb_monitor_respawn_interval = 30

# enable_distributed_routing = False
# quitting_rpc_timeout = 10

# (ListOpt) Extensions list to use
# Example: extensions = qos
#
# extensions =
extensions = qos

# (BoolOpt) Set or un-set the checksum on outgoing IP packet
# carrying GRE/VXLAN tunnel. The default value is False.
#
# tunnel_csum = False

# Security groups
[securitygroup]
firewall_driver = neutron.agent.linux.iptables_firewall.OVSHybridIptablesFirewallDriver
enable_security_group = True
enable_ipset = True
EOF
####
cat >/etc/neutron/l3_agent.ini <<EOF
[DEFAULT]
#interface_driver = neutron.agent.linux.interface.BridgeInterfaceDriver
interface_driver = neutron.agent.linux.interface.OVSInterfaceDriver
external_network_bridge = br-ex
EOF
cat >/etc/neutron/dhcp_agent.ini <<EOF
[DEFAULT]
#interface_driver = neutron.agent.linux.interface.BridgeInterfaceDriver
interface_driver = neutron.agent.linux.interface.OVSInterfaceDriver
external_network_bridge =
dhcp_driver = neutron.agent.linux.dhcp.Dnsmasq
enable_isolated_metadata = True
EOF
####
cat >/etc/neutron/metadata_agent.ini <<EOF
[DEFAULT]
verbose = True
debug = False

# Neutron credentials for API access
auth_url = "http://controller:35357/v2.0"
auth_region = RegionOne
admin_tenant_name = service
admin_user = neutron
admin_password = neutron
endpoint_type = adminURL

# Nova metadata service IP and port
nova_metadata_ip = controller
nova_metadata_port = 8775

# Metadata proxy shared secret
metadata_proxy_shared_secret = secret

# Workers and backlog requests
metadata_workers = 2
metadata_backlog = 128

# Caching
cache_url = memory://?default_ttl=5
EOF
####
ln -s /etc/neutron/plugins/ml2/ml2_conf.ini /etc/neutron/plugin.ini  &>>/tmp/install_neutron.log
#### sync database
su -s /bin/sh -c "neutron-db-manage --config-file /etc/neutron/neutron.conf --config-file /etc/neutron/plugins/ml2/ml2_conf.ini upgrade head" neutron &>>/tmp/install_neutron.log
check_error /tmp/install_neutron.log
systemctl start  openvswitch.service  &>>/tmp/install_neutron.log
check_error /tmp/install_neutron.log
#### add br-ex ovs_bridge
ovs-vsctl show |grep br-ex &>>/tmp/install_neutron.log
if [ $? -ne 0 ];then
	ovs-vsctl add-br br-ex &>>/tmp/install_neutron.log
	check_error /tmp/install_neutron.log
fi
#### start and enable neutron service 
systemctl enable neutron-server.service openvswitch.service neutron-openvswitch-agent.service  neutron-dhcp-agent.service neutron-metadata-agent.service neutron-l3-agent.service &>>/tmp/install_neutron.log
systemctl start neutron-server.service neutron-openvswitch-agent.service  neutron-dhcp-agent.service neutron-metadata-agent.service neutron-l3-agent.service &>>/tmp/install_neutron.log
sleep 5
check_error /tmp/install_neutron.log
source admin-openrc
neutron agent-list
end_install install_neutron /tmp/install_neutron.log

}
Install_Dashboard(){
#### install dashboard packets
yum install openstack-dashboard -y &>>/tmp/install_dashboard.log
check_error /tmp/install_dashboard.log

#### copy configuare
cp  /etc/openstack-dashboard/local_settings /etc/openstack-dashboard/local_settings.back &>>/tmp/install_dashboard.log
check_error /tmp/install_dashboard.log
cat $PWD/local_settings> /etc/openstack-dashboard/local_settings
check_error /tmp/install_dashboard.log
##### restart service
systemctl restart httpd.service memcached.service &>>/tmp/install_dashboard.log
check_error /tmp/install_dashboard.log
echo -e "\033[32m dashboard install success! you can browser at http://controller/dashboard\033[0m"
}


Install_cinder(){
echo -e "\033[32m Init the system success ! \n \033[0m"
}

#while ((1))
#do
echo -e "\033[36m -----------Menu------------\033[0m"
echo -e "\033[31m 1) Init the system\033[0m"
echo -e "\033[31m 2) Install database and message mq\033[0m"
echo -e "\033[31m 3) Install keystone \033[0m"
echo -e "\033[31m 4) Install glance \033[0m"
echo -e "\033[31m 5) Install nova \033[0m"
echo -e "\033[31m 6) Install neutron \033[0m"
echo -e "\033[31m 7) Install Dashboard \033[0m"
echo -e "\033[31m 8) Install cinder  \033[0m"

#read -p "Plseae input a number as above:" MenuChoose
for MenuChoose in {1,2,3,4,5,6,7}
do
case $MenuChoose in
	1)
		echo -e "\033[32m Init_system...\033[0m"
		Init_system
echo -e "\033[36m -----------Menu------------\033[0m"
echo -e "\033[32m 1) Finish init the system \033[0m"
echo -e "\033[31m 2) Install database and message mq\033[0m"
echo -e "\033[31m 3) Install keystone \033[0m"
echo -e "\033[31m 4) Install glance \033[0m"
echo -e "\033[31m 5) Install nova \033[0m"
echo -e "\033[31m 6) Install neutron \033[0m"
echo -e "\033[31m 7) Install Dashboard \033[0m"
echo -e "\033[31m 8) Install cinder  \033[0m"
	;;
	2)
		echo -e "\033[32m Install_db_mq...\033[0m"
		Install_db_mq
echo -e "\033[36m -----------Menu------------\033[0m"
echo -e "\033[32m 1) Finish init the system \033[0m"
echo -e "\033[32m 2) Finish Install database and message mq\033[0m"
echo -e "\033[31m 3) Install keystone \033[0m"
echo -e "\033[31m 4) Install glance \033[0m"
echo -e "\033[31m 5) Install nova \033[0m"
echo -e "\033[31m 6) Install neutron \033[0m"
echo -e "\033[31m 7) Install Dashboard \033[0m"
echo -e "\033[31m 8) Install cinder  \033[0m"
	;;
	3)
		echo -e "\033[32m Install_keystone...\033[0m"
		Install_keystone
echo -e "\033[36m -----------Menu------------\033[0m"
echo -e "\033[32m 1) Finish init the system \033[0m"
echo -e "\033[32m 2) Finish Install database and message mq\033[0m"
echo -e "\033[32m 3) Finish Install keystone \033[0m"
echo -e "\033[31m 4) Install glance \033[0m"
echo -e "\033[31m 5) Install nova \033[0m"
echo -e "\033[31m 6) Install neutron \033[0m"
echo -e "\033[31m 7) Install Dashboard \033[0m"
echo -e "\033[31m 8) Install cinder  \033[0m"
	;;
	4)
		echo -e "\033[32m install_glance... \033[0m"
		install_glance
echo -e "\033[36m -----------Menu------------\033[0m"
echo -e "\033[32m 1) Finish init the system \033[0m"
echo -e "\033[32m 2) Finish Install database and message mq\033[0m"
echo -e "\033[32m 3) Finish Install keystone \033[0m"
echo -e "\033[32m 4) Finish Install glance \033[0m"
echo -e "\033[31m 5) Install nova \033[0m"
echo -e "\033[31m 6) Install neutron \033[0m"
echo -e "\033[31m 7) Install Dashboard \033[0m"
echo -e "\033[31m 8) Install cinder  \033[0m"
	;;
	5)
		echo -e "\033[32m Install_nova... \033[0m"
		Install_nova
echo -e "\033[36m -----------Menu------------\033[0m"
echo -e "\033[32m 1) Finish init the system \033[0m"
echo -e "\033[32m 2) Finish Install database and message mq\033[0m"
echo -e "\033[32m 3) Finish Install keystone \033[0m"
echo -e "\033[32m 4) Finish Install glance \033[0m"
echo -e "\033[32m 5) Install nova \033[0m"
echo -e "\033[31m 6) Install neutron \033[0m"
echo -e "\033[31m 7) Install Dashboard \033[0m"
echo -e "\033[31m 8) Install cinder  \033[0m"
	;;
	6)
		echo -e "\033[32m Install_neutron... \033[0m"
		Install_neutron
echo -e "\033[36m -----------Menu------------\033[0m"
echo -e "\033[32m 1) Finish init the system \033[0m"
echo -e "\033[32m 2) Finish Install database and message mq\033[0m"
echo -e "\033[32m 3) Finish Install keystone \033[0m"
echo -e "\033[32m 4) Finish Install glance \033[0m"
echo -e "\033[32m 5) Finish Install nova \033[0m"
echo -e "\033[32m 6) Finish Install neutron \033[0m"
echo -e "\033[31m 7) Install Dashboard \033[0m"
echo -e "\033[31m 8) Install cinder  \033[0m"
	;;
	7)
		echo -e "\033[32m Install_Dashboard... \033[0m"
		Install_Dashboard
echo -e "\033[36m -----------Menu------------\033[0m"
echo -e "\033[32m 1) Finish init the system \033[0m"
echo -e "\033[32m 2) Finish Install database and message mq\033[0m"
echo -e "\033[32m 3) Finish Install keystone \033[0m"
echo -e "\033[32m 4) Finish Install glance \033[0m"
echo -e "\033[32m 5) Finish Install nova \033[0m"
echo -e "\033[32m 6) Finish Install neutron \033[0m"
echo -e "\033[32m 7) Finish Install Dashboard \033[0m"
echo -e "\033[31m 8) Install cinder  \033[0m"
	;;
	8)
		Install_cinder
	;;
	*)
		echo "Usage: $0 [1|2|3|4|5|6|help]"
		exit
	;;

esac
done
#done
