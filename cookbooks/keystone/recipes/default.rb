package "git" do
  action :install
end

bash 'download keystone' do
  user 'root'
  cwd '/opt'
  code 'git clone http://github.com/openstack/keystone.git'
  not_if {::File.exist?('/opt/keystone')}
end

['pip', 'pbr'].each do |pkg|
  easy_install_package pkg do
    action :install
  end
end

['python-devel', 'libxml2-devel', 'libxslt-devel', 'libyaml-devel'].each do |pkg|
  package pkg do
    action :install
  end
end

bash 'install keystone' do
  user 'root'
  cwd '/opt/keystone'
  code 'python setup.py install'
  not_if {::File.exist?('/usr/bin/keystone')}
end

['mariadb-server', 'mariadb', 'mariadb-devel'].each do |pkg|
  package pkg do
    action :install
  end
end

service 'mariadb.service' do
  action [:enable, :start]
end

bash 'setup database' do
  code <<-"EOH"
    /usr/bin/mysqladmin drop test -f
    /usr/bin/mysql -e "DELETE FROM User WHERE User = '';" -D mysql
    /usr/bin/mysql -e "DELETE FROM User WHERE User = 'root' and Host NOT IN ('localhost', '127.0.0.1', '::1');" -D mysql
    /usr/bin/mysql -e "SET PASSWORD FOR 'root'@'::1' = PASSWORD('#{node['mysql']['root_password']}');" -D mysql
    /usr/bin/mysql -e "SET PASSWORD FOR 'root'@'127.0.0.1' = PASSWORD('#{node['mysql']['root_password']}');" -D mysql
    /usr/bin/mysql -e "SET PASSWORD FOR 'root'@'localhost' = PASSWORD('#{node['mysql']['root_password']}');" -D mysql
    /usr/bin/mysqladmin flush-privileges -p#{node['mysql']['root_password']}
  EOH
  action :run
  only_if "/usr/bin/mysql -u root -e 'show databases;'"
end

bash 'install MySQL-python' do
  user 'root'
  code 'pip install MySQL-python'
  not_if 'pip list | grep MySQL-python'
end

user 'keystone' do
  shell '/bin/false'
  system true
  action :create
end

directory '/var/log/keystone' do
  user 'keystone'
  group 'keystone'
  mode 0755
  action :create
end

directory '/etc/keystone' do
  owner 'keystone'
  group 'keystone'
  mode 0755
  action :create
end

['keystone.conf', 'keystone-paste.ini'].each do |conf|
  template "/etc/keystone/#{conf}" do
    owner 'keystone'
    group 'keystone'
    mode 0440
    notifies :restart, 'service[openstack-keystone.service]'
  end
end

bash 'create keystone database' do
  code <<-"EOH"
    /usr/bin/mysql -e "CREATE DATABASE keystone;" -D mysql -u root -p#{node['mysql']['root_password']}
    /usr/bin/mysql -e "GRANT ALL PRIVILEGES ON keystone.* TO 'keystone'@'::1';" -D mysql -u root -p#{node['mysql']['root_password']}
    /usr/bin/mysql -e "GRANT ALL PRIVILEGES ON keystone.* TO 'keystone'@'127.0.0.1';" -D mysql -u root -p#{node['mysql']['root_password']}
    /usr/bin/mysql -e "GRANT ALL PRIVILEGES ON keystone.* TO 'keystone'@'localhost';" -D mysql -u root -p#{node['mysql']['root_password']}
    /usr/bin/mysql -e "SET PASSWORD FOR 'keystone'@'::1' = PASSWORD('#{node['mysql']['password']}');" -D mysql -u root -p#{node['mysql']['root_password']}
    /usr/bin/mysql -e "SET PASSWORD FOR 'keystone'@'127.0.0.1' = PASSWORD('#{node['mysql']['password']}');" -D mysql -u root -p#{node['mysql']['root_password']}
    /usr/bin/mysql -e "SET PASSWORD FOR 'keystone'@'localhost' = PASSWORD('#{node['mysql']['password']}');" -D mysql -u root -p#{node['mysql']['root_password']}
    /usr/bin/mysqladmin flush-privileges -p#{node['mysql']['root_password']}
  EOH
  not_if "/usr/bin/mysql -u root -p#{node['mysql']['root_password']} -e 'show databases;' | grep keystone"
end

bash 'keystone db_sync' do
  user 'root'
  code 'keystone-manage db_sync'
  not_if "/usr/bin/mysql -u root -p#{node['mysql']['root_password']} -e 'show tables;' -D mysql | grep user"
end

cookbook_file '/lib/systemd/system/openstack-keystone.service' do
  user 'root'
  group 'root'
  mode 0644
end

service 'openstack-keystone.service' do
  action [:enable, :start]
end
