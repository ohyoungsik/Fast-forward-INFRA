all:
  children:
    bastion:
      hosts:
        bastion-server:
          ansible_host: "${bastion_public_ip}"
    web:
      hosts:
        %{~ for ip in nginx_private_ips ~}
        nginx-fe-server-${ip}:
          ansible_host: "${ip}"
        %{~ endfor ~}
    was:
      hosts:
        %{~ for ip in fastapi_private_ips ~}
        fastapi-be-server-${ip}:
          ansible_host: "${ip}"
        %{~ endfor ~}
    db:
      hosts:
        %{~ for ip in postgre_private_ips ~}
        postgre-db-server-${ip}:
          ansible_host: "${ip}"
        %{~ endfor ~}