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
echo "172.16.214.138 controller-1" >>/etc/hosts
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
######################################## Install_nova_compute  ######################################################################

Install_nova(){
yum install  openstack-nova-compute  -y &>>/tmp/install_nova.log
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
connection = mysql+pymysql://nova:admin@controller-1/nova_api

[database]
connection = mysql+pymysql://nova:admin@controller-1/nova

[vnc]
vncserver_listen = 0.0.0.0
enabled = True
vncserver_proxyclient_address = $manage_ip
novncproxy_base_url = http://controller-1:6080/vnc_auto.html

[glance]
api_servers = http://controller-1:9292

[oslo_concurrency]
lock_path = /var/lib/nova/tmp

[libvirt]
virt_type = kvm

[oslo_messaging_rabbit]
rabbit_host = controller-1
rabbit_userid = openstack
rabbit_password = admin

[keystone_authtoken]
auth_uri = http://controller-1:5000
auth_url = http://controller-1:35357
memcached_servers = controller-1:11211
auth_type = password
project_domain_name = default
user_domain_name = default
project_name = service
username = nova
password = admin

[neutron]
url = http://controller-1:9696
auth_url = http://controller-1:35357
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

#### check cpu
vmxnum=`egrep -c '(vmx|svm)' /proc/cpuinfo`
if [ $vmxnum -lt 1 ];then
	echo "you machine is not support KVM"
	exit
fi

###start and enable service
systemctl enable libvirtd.service openstack-nova-compute.service  &>>/tmp/install_nova.log
check_error /tmp/install_nova.log

systemctl start libvirtd.service openstack-nova-compute.service  &>>/tmp/install_nova.log
check_error /tmp/install_nova.log
sleep 5
end_install install_nova /tmp/install_nova.log
}
######################################## Install_neutron_openvswitch  ######################################################################
Install_neutron(){
#### install neutron packects
yum install openstack-neutron-ml2 openstack-neutron-openvswitch ebtables -y   &>>/tmp/install_neutron.log
check_error /tmp/install_neutron.log

#### backup configure file
mv /etc/neutron/neutron.conf /etc/neutron/neutron.conf.back  &>>/tmp/install_neutron.log
mv /etc/neutron/plugins/ml2/ml2_conf.ini /etc/neutron/plugins/ml2/ml2_conf.ini.back  &>>/tmp/install_neutron.log
mv /etc/neutron/plugins/ml2/openvswitch_agent.ini /etc/neutron/plugins/ml2/openvswitch_agent.ini.back  &>>/tmp/install_neutron.log
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
connection = mysql+pymysql://neutron:admin@controller-1/neutron

[oslo_messaging_rabbit]
rabbit_host = controller-1
rabbit_userid = openstack
rabbit_password = admin

[keystone_authtoken]
auth_uri = http://controller-1:5000
auth_url = http://controller-1:35357
memcached_servers = controller-1:11211
auth_type = password
project_domain_name = default
user_domain_name = default
project_name = service
username = neutron
password = admin

[oslo_concurrency]
lock_path = /var/lib/neutron/tmp

[nova]
auth_url = http://controller-1:35357
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
#### add br-ex ovs_bridge
systemctl start openvswitch.service &>>/tmp/install_neutron.log
ovs-vsctl show |grep br-ex &>>/tmp/install_neutron.log
if [ $? -ne 0 ];then
	ovs-vsctl add-br br-ex &>>/tmp/install_neutron.log
	check_error /tmp/install_neutron.log
fi
#### start and enable neutron service 
systemctl enable openvswitch.service neutron-openvswitch-agent.service  &>>/tmp/install_neutron.log
systemctl start openvswitch.service  neutron-openvswitch-agent.service  &>>/tmp/install_neutron.log
sleep 5
check_error /tmp/install_neutron.log

}

#while ((1))
#do
#read -p "Plseae input a number as above:" MenuChoose
for MenuChoose in {1,2,3}
do
case $MenuChoose in
	1)
		echo -e "\033[32m Init_system...\033[0m"
		Init_system
echo -e "\033[36m -----------Menu------------\033[0m"
echo -e "\033[32m 1) Finish init the system \033[0m"
echo -e "\033[31m 2) Install nova \033[0m"
echo -e "\033[31m 3) Install neutron \033[0m"
	;;
	2)
		echo -e "\033[32m Install_nova... \033[0m"
		Install_nova
echo -e "\033[36m -----------Menu------------\033[0m"
echo -e "\033[32m 1) Finish init the system \033[0m"
echo -e "\033[32m 2) Finish install  nova \033[0m"
echo -e "\033[31m 3) Install neutron \033[0m"
	;;
	3)
		echo -e "\033[32m Install_neutron... \033[0m"
		Install_neutron
echo -e "\033[36m -----------Menu------------\033[0m"
echo -e "\033[32m 1) Finish init the system \033[0m"
echo -e "\033[32m 2) Finish Install nova \033[0m"
echo -e "\033[32m 3) Finish Install neutron \033[0m"
	;;
	*)
		echo "Usage: $0 [1|2|3|4|5|6|help]"
		exit
	;;

esac
done
#done
