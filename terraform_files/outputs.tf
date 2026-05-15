output "bastion_public_ip" {
  value = aws_instance.bastion_server.public_ip
}

output "bastion_private_ip" {
  value = aws_instance.bastion_server.private_ip
}

output "private_server_ips" {
  value = {
    for name, instance in aws_instance.private_servers :
    name => instance.private_ip
  }
}

output "ssh_private_server_commands" {
  description = "Bastion을 통해 Private 서버에 접속하는 명령어"
  value = {
    for name, instance in aws_instance.private_servers :
    name => "ssh -i ${var.key_name}.pem -A -J ubuntu@${aws_instance.bastion_server.public_ip} ubuntu@${instance.private_ip}"
  }
}

output "ssh_bastion_command" {
  value = "ssh -i ~/.ssh/${var.key_name}.pem ubuntu@${aws_instance.bastion_server.public_ip}"
}

output "ssh_nginx_via_bastion_example" {
  value = "ssh -i ~/.ssh/${var.key_name}.pem -J ubuntu@${aws_instance.bastion_server.public_ip} ubuntu@172.16.20.10"
}

output "inventory_yml" {
  value = templatefile("${path.module}/inventory.yml.tpl", {
    bastion_public_ip = aws_instance.bastion.public_ip
    bastion_private_ip = aws_instance.bastion.private_ip

    private_server_ips = {
      for name, instance in aws_instance.private_server :
      name => instance.private_ip
    }
  })
}

output "ansible_cfg" {
  value = templatefile("${path.module}/ansible.cfg.tpl", {
    inventory_path = "../terraform_files/inventory.yml"
  })
}