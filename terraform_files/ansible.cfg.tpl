# terraform_files/ansible_cfg.tpl

[defaults]
inventory         = inventory.yml
remote_user       = ubuntu
host_key_checking = False
private_key_file  = ~/.ssh/id_ed25519

[ssh_connection]
ssh_args = -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ProxyCommand="ssh -W %h:%p -i ~/.ssh/id_ed25519 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ubuntu@${bastion_ip}"