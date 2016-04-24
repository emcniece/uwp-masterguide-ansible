#!/bin/bash

if [ "$(uname)" == "Darwin" ]; then
    echo "Not currently implemented for OSX"
elif [ "$(expr substr $(uname -s) 1 10)" == "MINGW32_NT" ]; then
    echo "Not currently implemented for Windows"
elif [ "$(expr substr $(uname -s) 1 5)" == "Linux" ]; then
    sudo apt-get install -y software-properties-common
    sudo apt-add-repository -y ppa:ansible/ansible
    sudo apt-get update
    sudo apt-get install -y ansible

    touch /etc/ansible/hosts
    if grep -Fxq "localhost ansible_connection=local" /etc/ansible/hosts
    then
        echo "/etc/ansible/hosts localhost present"
    else
        echo "localhost ansible_connection=local" >> /etc/ansible/hosts
    fi
fi
