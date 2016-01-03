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

install_java