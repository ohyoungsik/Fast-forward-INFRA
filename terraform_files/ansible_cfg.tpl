# terraform_files/ansible_cfg.tpl

[defaults]
inventory         = ${gen_path}/../ansible_files/inventory.yml
private_key_file  = ~/.ssh/id_ed25519
remote_user       = ec2-user
host_key_checking = False

[ssh_connection]
ssh_args = -o StrictHostKeyChecking=no -o ProxyCommand="ssh -W %h:%p -i ~/.ssh/id_ed25519 ec2-user@${bastion_ip}"