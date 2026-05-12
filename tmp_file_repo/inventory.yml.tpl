# inventory.yml.tpl
all:
  children:
    bastion:
      hosts:
        bastion-server:
          ansible_host: "${bastion_public_ip}"
          ansible_user: ubuntu
          ansible_ssh_private_key_file: "../terraform_files/${key_name}.pem"
    web:
      hosts:
        nginx-fe-server:
          ansible_host: "${nginx_private_ip}"
          ansible_user: ubuntu
          ansible_ssh_private_key_file: "../terraform_files/${key_name}.pem"
          ansible_ssh_common_args: "-o ProxyCommand=\"ssh -W %h:%p -i ${key_path}/${key_name}.pem
          -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ubuntu@${bastion_public_ip}\"
          -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
    was:
      hosts:
        fastapi-be-server:
          ansible_host: "${fastapi_private_ip}"
          ansible_user: ubuntu
          ansible_ssh_private_key_file: "../terraform_files/${key_name}.pem"
          ansible_ssh_common_args: "-o ProxyCommand=\"ssh -W %h:%p -i ${key_path}/${key_name}.pem
          -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ubuntu@${bastion_public_ip}\"
          -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
    db:
      hosts:
        postgre-db-server:
          ansible_host: "${postgre_private_ip}"
          ansible_user: ubuntu
          ansible_ssh_private_key_file: "../terraform_files/${key_name}.pem"
          ansible_ssh_common_args: "-o ProxyCommand=\"ssh -W %h:%p -i ${key_path}/${key_name}.pem
          -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ubuntu@${bastion_public_ip}\"
          -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"