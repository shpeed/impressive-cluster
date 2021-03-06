#!/bin/bash -ex
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

# Parameters
readonly NODE_ID=$1
readonly HOSTNAME_PREFIX=$2
readonly IS_MASTER=$3

# Provision Config
readonly MY_IP=$(ifconfig eth1 | grep 'inet addr' | cut -d' ' -f12 | cut -d: -f2)
readonly MASTER_IP_1=192.168.33.11
readonly MASTER_IP_2=192.168.33.12
readonly MASTER_IP_3=192.168.33.13
readonly MASTERS=($MASTER_IP_1 $MASTER_IP_2 $MASTER_IP_3)

readonly MESOS_DNS_VERSION="v0.5.1"

echo "Setting up impressive node $(echo $NODE_ID)"
echo "Node IP:"
echo $MY_IP
echo "Master Node IP's:"
echo ${MASTERS[@]}

function install_master_utilities {
  # So we can talk to the other vagrant masters
  apt-get -y install sshpass
}

function install_hosts {
  # Hostname look up is used fro networking
  cat > /etc/hosts <<EOF
127.0.0.1 localhost
$(echo $MASTER_IP_1 $HOSTNAME_PREFIX\1)
$(echo $MASTER_IP_2 $HOSTNAME_PREFIX\2)
$(echo $MASTER_IP_3 $HOSTNAME_PREFIX\3)
EOF
}

function install_ssh_config {
  cat >> /etc/ssh/ssh_config <<EOF
# Allow local ssh w/out strict host checking
Host *
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
EOF
}

function install_java {
  echo "Installing Oracle Java"
  add-apt-repository -y ppa:webupd8team/java
  apt-get update
  apt-get -y upgrade
  echo debconf shared/accepted-oracle-license-v1-1 select true | sudo debconf-set-selections 
  echo debconf shared/accepted-oracle-license-v1-1 seen true | sudo debconf-set-selections
  apt-get -y install oracle-java8-installer
  apt-get -y install oracle-java8-set-default
}

function install_mesos {
  # Setup
  apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv E56151BF
  DISTRO=$(lsb_release -is | tr '[:upper:]' '[:lower:]')
  CODENAME=$(lsb_release -cs)

  # Add the repository
  echo "deb http://repos.mesosphere.com/${DISTRO} ${CODENAME} main" | \
  tee /etc/apt/sources.list.d/mesosphere.list
  apt-get -y update
  apt-get -y install mesos
}

function configure_mesos {
  cat > /etc/mesos/zk <<EOF
zk://$(echo $MASTER_IP_1):2181,$(echo $MASTER_IP_2):2181,$(echo $MASTER_IP_3):2181/mesos
EOF
  cat > /etc/mesos/hostname <<EOF
$(echo $HOSTNAME)
EOF
}

function configure_mesos_master {
  cat > /etc/mesos-master/quorum <<EOF
2
EOF
  cat > /etc/mesos-master/ip <<EOF
$(echo $MY_IP)
EOF
}

function configure_mesos_slave {
  # Adding docker here before installing docker will cause slave process to fail
  cat > /etc/mesos-slave/containerizers <<EOF
mesos,docker
EOF
  cat > /etc/mesos-slave/ip <<EOF
$(echo $MY_IP)
EOF
}

function disable_master {
  service mesos-master stop || true
  echo manual > /etc/init/mesos-master.override
  update-rc.d -f mesos-master remove
}

function configure_zookeeper {
  cat > /etc/zookeeper/conf/myid <<EOF
$(echo $NODE_ID)
EOF
  cat > /etc/zookeeper/conf/zoo.cfg <<EOF
tickTime=2000
initLimit=10
syncLimit=5
dataDir=/var/lib/zookeeper
clientPort=2181
server.1=$(echo $MASTER_IP_1):2888:3888
server.2=$(echo $MASTER_IP_2):2888:3888
server.3=$(echo $MASTER_IP_3):2888:3888
EOF
}

function start_zookeeper {
  if [[ $(masters_up_count) -eq 3 ]]; then
    echo "STARTING ZOOKEEPER"
    echo ${MASTERS[@]} | xargs -n 1 echo | xargs -n 1 -I {} sshpass -p vagrant ssh vagrant@{} sudo service zookeeper restart || true
  else
    echo "Skipping Zookeeper start up, waiting for our quorum.."
  fi
}

function start_mesos_master {
  if [[ $(masters_up_count) -eq 3 ]]; then
    echo "STARTING MESOS MASTER"
    echo ${MASTERS[@]} | xargs -n 1 echo | xargs -n 1 -I {} sshpass -p vagrant ssh vagrant@{} sudo service mesos-master restart || true
    sleep 10
  else
    echo "Skipping Mesos masters start up, waiting for our quorum.."
  fi
}

function start_mesos_slave {
  service mesos-slave restart || true
}

function disable_zookeeper {
  service zookeeper stop || true
  echo manual > /etc/init/zookeeper.override
  update-rc.d -f zookeeper remove
}

function install_marathon {
  apt-get -y install marathon
}

function start_marathon {
  if [[ $(masters_up_count) -eq 3 ]]; then
    echo "STARTING MARATHON"
    echo ${MASTERS[@]} | xargs -n 1 echo | xargs -n 1 -I {} sshpass -p vagrant ssh vagrant@{} sudo service marathon restart || true
    sleep 15
  else
    echo "Skipping marathon start up, waiting for our quorum.."
  fi
}

function install_mesos_dns {
  mkdir /usr/local/mesos-dns
  wget https://github.com/mesosphere/mesos-dns/releases/download/$MESOS_DNS_VERSION/mesos-dns-$MESOS_DNS_VERSION-linux-amd64
  mv ./mesos-dns-$MESOS_DNS_VERSION-linux-amd64 /usr/local/mesos-dns/mesos-dns
  chmod +x /usr/local/mesos-dns/mesos-dns
  cat > /usr/local/mesos-dns/config.json <<EOF
{
  "zk": "zk://$(echo $MASTER_IP_1):2181,$(echo $MASTER_IP_2):2181,$(echo $MASTER_IP_3):2181/mesos",
  "refreshSeconds": 60,
  "ttl": 60,
  "domain": "mesos",
  "port": 53,
  "resolvers": ["10.0.2.3"],
  "timeout": 5,
  "httpon": true,
  "dnson": true,
  "httpport": 8123,
  "externalon": true,
  "listener": "$(echo $MY_IP)",
  "SOAMname": "ns1.mesos",
  "SOARname": "root.ns1.mesos",
  "SOARefresh": 60,
  "SOARetry":   600,
  "SOAExpire":  86400,
  "SOAMinttl": 60,
  "IPSources": ["netinfo", "host"]
}
EOF
}

function configure_mesos_dns {
  # resolv.conf should be a symlink to /run/resolvconf/resolv.conf
  cat > /etc/resolvconf/resolv.conf.d/head <<EOF
nameserver $(echo $MASTER_IP_1)
nameserver $(echo $MASTER_IP_2)
nameserver $(echo $MASTER_IP_3)
EOF
  resolvconf -u
}

function deploy_mesos_dns {
  if [[ $(masters_up_count) -eq 3 ]]; then
    echo "DEPLOYING MESOS-DNS"
    curl -H "Content-Type: application/json" -X POST -d \
    '{
    "cmd": "sudo  /usr/local/mesos-dns/mesos-dns -config=/usr/local/mesos-dns/config.json",
    "cpus": 0.2,
    "mem": 64,
    "id": "mesos-dns",
    "instances": 3,
    "constraints": [["hostname", "UNIQUE"]]
    }' \
    http://localhost:8080/v2/apps
  else
    echo "Skipping mesos-dns start up, waiting for our quorum.."
  fi
}

function install_chronos {
  apt-get -y install chronos
}

function deploy_chronos {
  if [[ $(masters_up_count) -eq 3 ]]; then
    echo "DEPLOYING CHRONOS"
    curl -H "Content-Type: application/json" -X POST -d \
    '{
    "cmd": "sudo /usr/bin/chronos",
    "cpus": 0.2,
    "mem": 64,
    "id": "chronos",
    "instances": 3,
    "constraints": [["hostname", "UNIQUE"]]
    }' \
    http://localhost:8080/v2/apps
  else
    echo "Skipping chronos start up, waiting for our quorum.."
  fi
}

function install_docker {
  apt-key adv --keyserver hkp://p80.pool.sks-keyservers.net:80 \
  --recv-keys 58118E89F3A912897C070ADBF76221572C52609D
  cat > /etc/apt/sources.list.d/docker.list <<EOF
deb https://apt.dockerproject.org/repo ubuntu-trusty main
EOF
  apt-get update
  apt-get purge lxc-docker
  apt-get -y install linux-image-extra-$(uname -r)
  apt-get -y install docker-engine
  service docker restart

  # Check docker is set up right
  docker run hello-world
  docker rmi -f hello-world
}

function setup_master {
  echo "Setting up a master node.."
  install_ssh_config
  install_hosts
  install_master_utilities
  install_java
  install_mesos
  install_marathon
  install_mesos_dns
  install_chronos
  install_docker
  configure_zookeeper
  configure_mesos
  configure_mesos_master
  configure_mesos_slave
  start_zookeeper
  start_mesos_master
  start_mesos_slave
  start_marathon
  deploy_mesos_dns
  deploy_chronos

  # Configure mesos-dns last so dns can resolve before we have it set up
  configure_mesos_dns
}

function setup_slave {
  echo "Setting up a slave node.."
  install_ssh_config
  install_hosts
  install_java
  install_mesos
  install_docker
  disable_zookeeper
  disable_master
  configure_mesos
  configure_mesos_slave
  start_mesos_slave

  # Configure mesos-dns last so dns can resolve before we have it set up
  configure_mesos_dns
}

function masters_up_count {
  echo ${MASTERS[@]} | xargs -n 1 ping -c 1 | grep "time=" | wc -l
}

if [[ $IS_MASTER -eq 1 ]]; then
  setup_master
else
  setup_slave
fi