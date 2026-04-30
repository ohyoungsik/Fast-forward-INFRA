output "bastion_public_ip" {
  value = aws_instance.bastion.public_ip
}

output "bastion_private_ip" {
  value = aws_instance.bastion.private_ip
}

output "private_server_ips" {
  value = {
    for name, instance in aws_instance.private_servers :
    name => instance.private_ip
  }
}

output "ssh_bastion_command" {
  value = "ssh -i ~/.ssh/your-key.pem ubuntu@${aws_instance.bastion.public_ip}"
}

output "ssh_nginx_via_bastion_example" {
  value = "ssh -i ~/.ssh/your-key.pem -J ubuntu@${aws_instance.bastion.public_ip} ubuntu@172.16.20.10"
}