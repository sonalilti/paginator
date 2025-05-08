#!/bin/sh
# This script is an example of short-cut Ansible invocation that allows
# to perform Admin source code upgrade only. With given options Ansible
# skips all OS setup steps and does Admin upgrade quickly.
# Not for first run.

if [ ! -f inventory.yml ] ; then
  echo "Inventory file inventory.yml not found!"
  echo "Please see docs on how to create one."
  exit 2
fi

ansible-playbook -i inventory.yml playbooks/standalone.yml --tags deploy
