# azure-terraformer

## info
This deploys a webhost (vm1) and a ansible control node (vm2) in azure via terraform.

## steps
1. create service-principal user via az cli
2. set required pws $env:TF_VAR_
3. terraform init, plan, apply, refresh
4. use ssh_command_2 (known after apply) to connect to the ansible control node
5. run: ansible-playbook ansible/playbooks/connection_test.yml -i ansible/hosts
6. run: ansible-playbook nodejsapp-demo/deploy.yml -i ansible/hosts
7. Check webapp http://ipvm2:8080

## todo
- disable port 22 on vm1
- open port 8080 on vm1
