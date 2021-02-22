#! /bin/bash

# update all the things
yum update -y

# disable selinux
setenforce 0

# disable local firewall
systemctl disable firewalld
systemctl stop firewalld

# cfn-signal setup
yum install -y https://s3.amazonaws.com/cloudformation-examples/aws-cfn-bootstrap-latest.amzn1.noarch.rpm
export PYTHONPATH="${PYTHONPATH}:/usr/local/lib/python2.7/site-packages/"
yum install -y python-setuptools
mkdir aws-cfn-bootstrap-latest
curl https://s3.amazonaws.com/cloudformation-examples/aws-cfn-bootstrap-latest.tar.gz | tar xz -C aws-cfn-bootstrap-latest --strip-components 1
easy_install aws-cfn-bootstrap-latest

# install GPG key
rpm --import https://artifacts.elastic.co/GPG-KEY-elasticsearch

# download RPMs
curl -O https://artifacts.elastic.co/downloads/elasticsearch/elasticsearch-7.6.2-x86_64.rpm
curl -O https://artifacts.elastic.co/downloads/kibana/kibana-7.6.2-x86_64.rpm
curl -O https://artifacts.elastic.co/downloads/beats/filebeat/filebeat-7.6.2-x86_64.rpm
curl -O https://artifacts.elastic.co/downloads/beats/metricbeat/metricbeat-7.6.2-x86_64.rpm

# install RPMs
rpm --install elasticsearch-7.6.2-x86_64.rpm kibana-7.6.2-x86_64.rpm filebeat-7.6.2-x86_64.rpm metricbeat-7.6.2-x86_64.rpm

# configure elasticsearch
sed -i 's/#cluster.name: my-application/cluster.name: lab/' /etc/elasticsearch/elasticsearch.yml
echo "# --------------------------------- Security -----------------------------------" >> /etc/elasticsearch.yml
echo "#" >> /etc/elasticsearch/elasticsearch.yml
echo "xpack.security.enabled: true" >> /etc/elasticsearch/elasticsearch.yml
echo "xpack.security.transport.ssl.enabled: true" >> /etc/elasticsearch/elasticsearch.yml

# create the elasticsearch keystore and set bootstrap password
echo "temppass" | /usr/share/elasticsearch/bin/elasticsearch-keystore add --stdin bootstrap.password

# start elasticsearch
systemctl start elasticsearch

# set user passwords
until [ $(curl -s -o /dev/null -w '%{http_code}' -u elastic:temppass localhost:9200) -eq 200 > /dev/null 2>&1 ]; do sleep 1; done
curl -u elastic:temppass -X PUT -H 'Content-Type: application/json' http://localhost:9200/_xpack/security/user/elastic/_password -d '{"password":"elastic_acg"}'
curl -u elastic:elastic_acg -X PUT -H 'Content-Type: application/json' http://localhost:9200/_xpack/security/user/kibana/_password -d '{"password":"kibana_acg"}'
curl -u elastic:elastic_acg -X PUT -H 'Content-Type: application/json' http://localhost:9200/_xpack/security/user/beats_system/_password -d '{"password":"beats_acg"}'

# configure kibana
sed -i 's/#server.port: 5601/server.port: 8080/' /etc/kibana/kibana.yml
sed -i 's/#elasticsearch.username: "kibana"/elasticsearch.username: "kibana"/' /etc/kibana/kibana.yml
sed -i 's/#elasticsearch.password: "pass"/elasticsearch.password: "kibana_acg"/' /etc/kibana/kibana.yml
sed -i 's/ExecStart=\/usr\/share\/kibana\/bin\/kibana "-c \/etc\/kibana\/kibana.yml"/ExecStart=\/usr\/share\/kibana\/bin\/kibana "-c \/etc\/kibana\/kibana.yml -H %H"/' /etc/systemd/system/kibana.service

# configure filebeat
sed -i 's/  index.number_of_shards: 1/  index.number_of_shards: 1\n  index.number_of_replicas: 0/' /etc/filebeat/filebeat.yml
sed -i 's/  #username: "elastic"/  username: "elastic"/' /etc/filebeat/filebeat.yml
sed -i 's/  #password: "changeme"/  password: "elastic_acg"/' /etc/filebeat/filebeat.yml
filebeat modules enable system
filebeat setup

# configure metricbeat
sed -i 's/  index.number_of_shards: 1/  index.number_of_shards: 1\n  index.number_of_replicas: 0/' /etc/metricbeat/metricbeat.yml
sed -i 's/  #username: "elastic"/  username: "elastic"/' /etc/metricbeat/metricbeat.yml
sed -i 's/  #password: "changeme"/  password: "elastic_acg"/' /etc/metricbeat/metricbeat.yml
metricbeat setup

# start kibana, filebeat, and metricbeat
systemctl daemon-reload
systemctl start kibana filebeat metricbeat

# enable services
systemctl enable elasticsearch kibana filebeat metricbeat

# wait for kibana to start
until [ $(curl -s -o /dev/null -w '%{http_code}' -m 10 -u elastic:elastic_acg 10.0.1.101:8080/status) -eq 200 > /dev/null 2>&1 ]; do sleep 10; done;

# load ecommerce data
curl -X POST -u elastic:elastic_acg -H "kbn-xsrf:true" 10.0.1.101:8080/api/sample_data/ecommerce
curl -X POST -u elastic:elastic_acg -H 'Content-Type: application/json' http://localhost:9200/_aliases -d'{  "actions": [ { "add": { "index": "kibana_sample_data_ecommerce", "alias": "ecommerce" } } ]}'
curl -X DELETE -u elastic:elastic_acg -H "kbn-xsrf:true" 10.0.1.101:8080/api/saved_objects/canvas-workpad/workpad-e08b9bdb-ec14-4339-94c4-063bddfd610e
curl -X DELETE -u elastic:elastic_acg -H "kbn-xsrf:true" 10.0.1.101:8080/api/saved_objects/dashboard/722b74f0-b882-11e8-a6d9-e546fe2bba5f
curl -X DELETE -u elastic:elastic_acg -H "kbn-xsrf:true" 10.0.1.101:8080/api/saved_objects/index-pattern/ff959d40-b880-11e8-a6d9-e546fe2bba5f
curl -X DELETE -u elastic:elastic_acg -H "kbn-xsrf:true" 10.0.1.101:8080/api/saved_objects/map/2c9c1f60-1909-11e9-919b-ffe5949a18d2
curl -X DELETE -u elastic:elastic_acg -H "kbn-xsrf:true" 10.0.1.101:8080/api/saved_objects/search/3ba638e0-b894-11e8-a6d9-e546fe2bba5f
curl -X DELETE -u elastic:elastic_acg -H "kbn-xsrf:true" 10.0.1.101:8080/api/saved_objects/visualization/37cc8650-b882-11e8-a6d9-e546fe2bba5f
curl -X DELETE -u elastic:elastic_acg -H "kbn-xsrf:true" 10.0.1.101:8080/api/saved_objects/visualization/ed8436b0-b88b-11e8-a6d9-e546fe2bba5f
curl -X DELETE -u elastic:elastic_acg -H "kbn-xsrf:true" 10.0.1.101:8080/api/saved_objects/visualization/09ffee60-b88c-11e8-a6d9-e546fe2bba5f
curl -X DELETE -u elastic:elastic_acg -H "kbn-xsrf:true" 10.0.1.101:8080/api/saved_objects/visualization/1c389590-b88d-11e8-a6d9-e546fe2bba5f
curl -X DELETE -u elastic:elastic_acg -H "kbn-xsrf:true" 10.0.1.101:8080/api/saved_objects/visualization/45e07720-b890-11e8-a6d9-e546fe2bba5f
curl -X DELETE -u elastic:elastic_acg -H "kbn-xsrf:true" 10.0.1.101:8080/api/saved_objects/visualization/10f1a240-b891-11e8-a6d9-e546fe2bba5f
curl -X DELETE -u elastic:elastic_acg -H "kbn-xsrf:true" 10.0.1.101:8080/api/saved_objects/visualization/b80e6540-b891-11e8-a6d9-e546fe2bba5f
curl -X DELETE -u elastic:elastic_acg -H "kbn-xsrf:true" 10.0.1.101:8080/api/saved_objects/visualization/4b3ec120-b892-11e8-a6d9-e546fe2bba5f
curl -X DELETE -u elastic:elastic_acg -H "kbn-xsrf:true" 10.0.1.101:8080/api/saved_objects/visualization/9ca7aa90-b892-11e8-a6d9-e546fe2bba5f
curl -X DELETE -u elastic:elastic_acg -H "kbn-xsrf:true" 10.0.1.101:8080/api/saved_objects/visualization/9c6f83f0-bb4d-11e8-9c84-77068524bcab
curl -X DELETE -u elastic:elastic_acg -H "kbn-xsrf:true" 10.0.1.101:8080/api/saved_objects/visualization/b72dd430-bb4d-11e8-9c84-77068524bcab

# load flights data
curl -X POST -u elastic:elastic_acg -H "kbn-xsrf:true" 10.0.1.101:8080/api/sample_data/flights
curl -X POST -u elastic:elastic_acg -H 'Content-Type: application/json' http://localhost:9200/_aliases -d'{  "actions": [ { "add": { "index": "kibana_sample_data_flights", "alias": "flights" } } ]}'
curl -X DELETE -u elastic:elastic_acg -H "kbn-xsrf:true" 10.0.1.101:8080/api/saved_objects/canvas-workpad/workpad-a474e74b-aedc-47c3-894a-db77e62c41e0
curl -X DELETE -u elastic:elastic_acg -H "kbn-xsrf:true" 10.0.1.101:8080/api/saved_objects/dashboard/7adfa750-4c81-11e8-b3d7-01146121b73d
curl -X DELETE -u elastic:elastic_acg -H "kbn-xsrf:true" 10.0.1.101:8080/api/saved_objects/index-pattern/d3d7af60-4c81-11e8-b3d7-01146121b73d
curl -X DELETE -u elastic:elastic_acg -H "kbn-xsrf:true" 10.0.1.101:8080/api/saved_objects/map/5dd88580-1906-11e9-919b-ffe5949a18d2
curl -X DELETE -u elastic:elastic_acg -H "kbn-xsrf:true" 10.0.1.101:8080/api/saved_objects/search/571aaf70-4c88-11e8-b3d7-01146121b73d
curl -X DELETE -u elastic:elastic_acg -H "kbn-xsrf:true" 10.0.1.101:8080/api/saved_objects/visualization/aeb212e0-4c84-11e8-b3d7-01146121b73d
curl -X DELETE -u elastic:elastic_acg -H "kbn-xsrf:true" 10.0.1.101:8080/api/saved_objects/visualization/c8fc3d30-4c87-11e8-b3d7-01146121b73d
curl -X DELETE -u elastic:elastic_acg -H "kbn-xsrf:true" 10.0.1.101:8080/api/saved_objects/visualization/8f4d0c00-4c86-11e8-b3d7-01146121b73d
curl -X DELETE -u elastic:elastic_acg -H "kbn-xsrf:true" 10.0.1.101:8080/api/saved_objects/visualization/f8290060-4c88-11e8-b3d7-01146121b73d
curl -X DELETE -u elastic:elastic_acg -H "kbn-xsrf:true" 10.0.1.101:8080/api/saved_objects/visualization/bcb63b50-4c89-11e8-b3d7-01146121b73d
curl -X DELETE -u elastic:elastic_acg -H "kbn-xsrf:true" 10.0.1.101:8080/api/saved_objects/visualization/9886b410-4c8b-11e8-b3d7-01146121b73d
curl -X DELETE -u elastic:elastic_acg -H "kbn-xsrf:true" 10.0.1.101:8080/api/saved_objects/visualization/76e3c090-4c8c-11e8-b3d7-01146121b73d
curl -X DELETE -u elastic:elastic_acg -H "kbn-xsrf:true" 10.0.1.101:8080/api/saved_objects/visualization/707665a0-4c8c-11e8-b3d7-01146121b73d
curl -X DELETE -u elastic:elastic_acg -H "kbn-xsrf:true" 10.0.1.101:8080/api/saved_objects/visualization/293b5a30-4c8f-11e8-b3d7-01146121b73d
curl -X DELETE -u elastic:elastic_acg -H "kbn-xsrf:true" 10.0.1.101:8080/api/saved_objects/visualization/129be430-4c93-11e8-b3d7-01146121b73d
curl -X DELETE -u elastic:elastic_acg -H "kbn-xsrf:true" 10.0.1.101:8080/api/saved_objects/visualization/334084f0-52fd-11e8-a160-89cc2ad9e8e2
curl -X DELETE -u elastic:elastic_acg -H "kbn-xsrf:true" 10.0.1.101:8080/api/saved_objects/visualization/f8283bf0-52fd-11e8-a160-89cc2ad9e8e2
curl -X DELETE -u elastic:elastic_acg -H "kbn-xsrf:true" 10.0.1.101:8080/api/saved_objects/visualization/08884800-52fe-11e8-a160-89cc2ad9e8e2
curl -X DELETE -u elastic:elastic_acg -H "kbn-xsrf:true" 10.0.1.101:8080/api/saved_objects/visualization/e6944e50-52fe-11e8-a160-89cc2ad9e8e2
curl -X DELETE -u elastic:elastic_acg -H "kbn-xsrf:true" 10.0.1.101:8080/api/saved_objects/visualization/01c413e0-5395-11e8-99bf-1ba7b1bdaa61
curl -X DELETE -u elastic:elastic_acg -H "kbn-xsrf:true" 10.0.1.101:8080/api/saved_objects/visualization/2edf78b0-5395-11e8-99bf-1ba7b1bdaa61
curl -X DELETE -u elastic:elastic_acg -H "kbn-xsrf:true" 10.0.1.101:8080/api/saved_objects/visualization/ed78a660-53a0-11e8-acbd-0be0ad9d822b

# load logs data
curl -X POST -u elastic:elastic_acg -H "kbn-xsrf:true" 10.0.1.101:8080/api/sample_data/logs
curl -X POST -u elastic:elastic_acg -H 'Content-Type: application/json' http://localhost:9200/_aliases -d'{  "actions": [ { "add": { "index": "kibana_sample_data_logs", "alias": "logs" } } ]}'
curl -X DELETE -u elastic:elastic_acg -H "kbn-xsrf:true" 10.0.1.101:8080/api/saved_objects/canvas-workpad/workpad-ad72a4e9-b422-480c-be6d-a64a0b79541d
curl -X DELETE -u elastic:elastic_acg -H "kbn-xsrf:true" 10.0.1.101:8080/api/saved_objects/dashboard/edf84fe0-e1a0-11e7-b6d5-4dc382ef7f5b
curl -X DELETE -u elastic:elastic_acg -H "kbn-xsrf:true" 10.0.1.101:8080/api/saved_objects/index-pattern/90943e30-9a47-11e8-b64d-95841ca0b247
curl -X DELETE -u elastic:elastic_acg -H "kbn-xsrf:true" 10.0.1.101:8080/api/saved_objects/map/de71f4f0-1902-11e9-919b-ffe5949a18d2
curl -X DELETE -u elastic:elastic_acg -H "kbn-xsrf:true" 10.0.1.101:8080/api/saved_objects/visualization/06cf9c40-9ee8-11e7-8711-e7a007dcef99
curl -X DELETE -u elastic:elastic_acg -H "kbn-xsrf:true" 10.0.1.101:8080/api/saved_objects/visualization/e1d0f010-9ee7-11e7-8711-e7a007dcef99
curl -X DELETE -u elastic:elastic_acg -H "kbn-xsrf:true" 10.0.1.101:8080/api/saved_objects/visualization/935afa20-e0cd-11e7-9d07-1398ccfcefa3
curl -X DELETE -u elastic:elastic_acg -H "kbn-xsrf:true" 10.0.1.101:8080/api/saved_objects/visualization/4eb6e500-e1c7-11e7-b6d5-4dc382ef7f5b
curl -X DELETE -u elastic:elastic_acg -H "kbn-xsrf:true" 10.0.1.101:8080/api/saved_objects/visualization/69a34b00-9ee8-11e7-8711-e7a007dcef99
curl -X DELETE -u elastic:elastic_acg -H "kbn-xsrf:true" 10.0.1.101:8080/api/saved_objects/visualization/42b997f0-0c26-11e8-b0ec-3bb475f6b6ff
curl -X DELETE -u elastic:elastic_acg -H "kbn-xsrf:true" 10.0.1.101:8080/api/saved_objects/visualization/7cbd2350-2223-11e8-b802-5bcf64c2cfb4
curl -X DELETE -u elastic:elastic_acg -H "kbn-xsrf:true" 10.0.1.101:8080/api/saved_objects/visualization/314c6f60-2224-11e8-b802-5bcf64c2cfb4
curl -X DELETE -u elastic:elastic_acg -H "kbn-xsrf:true" 10.0.1.101:8080/api/saved_objects/visualization/24a3e970-4257-11e8-b3aa-73fdaf54bfc9
curl -X DELETE -u elastic:elastic_acg -H "kbn-xsrf:true" 10.0.1.101:8080/api/saved_objects/visualization/14e2e710-4258-11e8-b3aa-73fdaf54bfc9
curl -X DELETE -u elastic:elastic_acg -H "kbn-xsrf:true" 10.0.1.101:8080/api/saved_objects/visualization/47f2c680-a6e3-11e8-94b4-c30c0228351b
