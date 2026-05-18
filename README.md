# 🚀 Fast-Forward INFRA

> **코드 Push → 자동 배포 → 서비스 실행 → 모니터링 → 로그 분석**
> 개발자가 코드를 push하면 GitHub Actions가 인프라를 프로비저닝하고, Ansible이 서버를 구성하며, 서비스가 자동으로 실행되고 모니터링까지 연결되는 완전 자동화 파이프라인입니다.

---

## 📁 디렉토리 구조

```
Fast-forward-INFRA/
├── .github/
│   └── workflows/
│       ├── validate.yml        # PR 시 Terraform fmt/validate + Ansible lint
│       ├── plan.yml            # PR 시 Terraform plan 실행 및 결과 코멘트
│       ├── deploy.yml          # main 브랜치 merge 시 Terraform apply + Ansible 실행
│       └── destroy.yml         # 수동 실행: 인프라 전체 또는 부분 삭제
├── terraform_files/
│   ├── main.tf                 # VPC, Subnet, EC2, NAT, S3, Inventory 생성
│   ├── variables.tf            # 변수 정의 (리전, CIDR, 인스턴스 타입 등)
│   ├── outputs.tf              # Bastion/Private IP, SSH 명령어 출력
│   ├── provider.tf             # AWS Provider, S3 Remote Backend 설정
│   ├── security_group.tf       # 보안 그룹 및 인바운드/아웃바운드 규칙
│   ├── inventory.yml.tpl       # Ansible Inventory 템플릿
│   └── ansible.cfg.tpl         # Ansible 설정 템플릿 (ProxyCommand 포함)
└── ansible_files/
    ├── site.yml                # 전체 Playbook 진입점
    ├── requirements.yml        # Galaxy Role/Collection 목록
    ├── group_vars/
    │   ├── all.yml             # 공통 변수 (패키지, 로그 경로, Fluent-bit 설정)
    │   ├── web.yml             # Nginx 포트 설정
    │   ├── was.yml             # FastAPI 앱 경로 및 포트
    │   ├── db.yml              # PostgreSQL DB/User/Password
    │   └── bastion.yml         # Prometheus scrape target 설정
    └── roles/
        ├── common/             # 공통 패키지 설치 (curl, vim, unzip, git)
        ├── web/                # Nginx 설치 및 Reverse Proxy 설정
        ├── was/                # FastAPI + Gunicorn + venv 설치 및 서비스 등록
        ├── db/                 # PostgreSQL 설치, DB/User 생성 및 권한 설정
        ├── bastion/            # Nginx Reverse Proxy + Prometheus + Grafana 설치
        ├── monitoring/         # Node Exporter 설치 및 서비스 등록
        └── logging/            # Fluent-bit 설치 및 로그 수집 설정
```

---

## 🏗️ 인프라 아키텍처

```
Internet
    │
    ▼
[Bastion Server] ── Public Subnet (172.16.10.0/24)
  - Nginx Reverse Proxy (Port 80)
  - Prometheus (Port 9090)
  - Grafana (Port 3000)
    │
    │  ProxyCommand (SSH 터널)
    ▼
Private Subnet (172.16.20.0/24)
  ├── [nginx-fe-server]    172.16.20.10  ← Nginx + Node Exporter
  ├── [fastapi-be-server]  172.16.20.20  ← FastAPI + Gunicorn + Node Exporter
  └── [postgre-db-server]  172.16.20.30  ← PostgreSQL + Node Exporter
```

**트래픽 흐름:**
```
사용자 → Bastion(80) → nginx-fe(80) → fastapi-be(8000) → postgre-db(5432)
```

**모니터링 흐름:**
```
Node Exporter(:9100) ← Prometheus(Bastion) → Grafana(Bastion:3000)
```

**로그 흐름:**
```
각 서버 로그 → Fluent-bit → Elasticsearch(10.0.0.10:9200)
```

---

## ⚙️ CI/CD 파이프라인

### 전체 흐름

```
[개발자 Push]
     │
     ├─ PR 생성
     │   ├── validate.yml  → terraform fmt/validate, ansible-lint
     │   └── plan.yml      → terraform plan → PR 코멘트 등록 + tfplan artifact 저장
     │
     └─ main 브랜치 Merge
         └── deploy.yml
               ├── changed-files   : terraform / ansible 변경 감지
               ├── terraform-apply : Terraform apply → inventory.yml, ansible.cfg 생성 → S3 업로드
               └── ansible-configure : S3에서 파일 다운로드 → Galaxy 설치 → Ansible 실행
```

### GitHub Actions 워크플로우 상세

| 워크플로우 | 트리거 | 주요 동작 |
|---|---|---|
| `validate.yml` | PR to main | `terraform fmt -check`, `terraform validate`, `ansible-lint` |
| `plan.yml` | PR to main | `terraform plan -out=tfplan` → PR 코멘트 자동 등록, artifact 7일 보관 |
| `deploy.yml` | Push to main | Terraform apply + Ansible playbook 실행 (environment: production 승인 필요) |
| `destroy.yml` | 수동(workflow_dispatch) | `"destroy"` 문자열 확인 후 전체/EC2/SG 선택 삭제 |

### S3를 통한 파일 전달

Terraform apply 후 생성된 `inventory.yml`과 `ansible.cfg`는 GitHub Actions의 job 간 파일 공유를 위해 S3 버킷(`fastforward-tfstate`)에 업로드되며, Ansible job에서 다운로드하여 사용합니다.

---

## 🔧 Terraform

### 주요 리소스

- **VPC**: `172.16.0.0/16`, DNS 지원 활성화
- **Public Subnet**: `172.16.10.0/24` (Bastion)
- **Private Subnet**: `172.16.20.0/24` (Web/WAS/DB)
- **NAT Gateway**: Private 서버의 아웃바운드 인터넷 연결
- **EC2 인스턴스**: Ubuntu 24.04 LTS, t3.small
  - Bastion: `172.16.10.50` (Public IP 할당)
  - nginx-fe-server: `172.16.20.10`
  - fastapi-be-server: `172.16.20.20`
  - postgre-db-server: `172.16.20.30`
- **S3 Remote Backend**: `fastforward-tfstate` 버킷에 tfstate 저장
- **DynamoDB Lock**: tfstate 동시 수정 방지

### 보안 그룹 규칙 요약

| 방향 | 출발지 | 목적지 | 포트 | 설명 |
|---|---|---|---|---|
| Inbound | 0.0.0.0/0 | Bastion | 22, 80, 443 | SSH, HTTP, HTTPS |
| Inbound | 0.0.0.0/0 | Bastion | 9090, 3000 | Prometheus, Grafana |
| Inbound | Bastion SG | Private 전체 | 22 | SSH ProxyCommand |
| Inbound | Bastion SG | nginx-fe | 80 | Reverse Proxy |
| Inbound | nginx-fe SG | fastapi-be | 8000 | API 요청 |
| Inbound | fastapi-be SG | postgre-db | 5432 | DB 연결 |
| Inbound | Bastion SG | Private 전체 | 9100 | Node Exporter 수집 |

---

## 📦 Ansible

### Role 구성

#### `common`
모든 서버에 공통 패키지 설치: `curl`, `vim`, `unzip`, `git`

#### `web` (nginx-fe-server)
- `geerlingguy.nginx` Galaxy Role로 Nginx 설치
- Reverse Proxy 설정: `/api/` 경로 → FastAPI(`172.16.20.20:8000`) 프록시
- 커스텀 `index.html` 배포

#### `was` (fastapi-be-server)
- Python venv 생성 (`/var/www/fastapi_app/venv`)
- FastAPI, Uvicorn, Gunicorn, Pydantic, asyncpg 설치
- systemd 서비스 등록 (`fastapi.service`): Gunicorn + UvicornWorker, 2 workers

#### `db` (postgre-db-server)
- `geerlingguy.postgresql` Galaxy Role로 PostgreSQL 설치
- DB(`app_db`), User(`app_user`) 생성
- 권한 설정: CONNECT, CREATE, TEMPORARY, CRUD, Sequence
- `listen_addresses = '*'` 설정 및 FastAPI 서버 IP 접근 허용 (`pg_hba.conf`)

#### `bastion`
- Nginx Reverse Proxy 설정 (`172.16.20.10:80` 포워딩)
- Prometheus 설치 (`prometheus.prometheus` Collection, v2.47.0)
- Grafana 설치 (apt 저장소 등록, GPG 키 설정)

#### `monitoring` (전체 서버)
- Node Exporter v1.7.0 설치 및 systemd 서비스 등록
- `:9100` 포트에서 메트릭 제공

#### `logging` (전체 서버)
- Fluent-bit 설치 (GPG 키 등록, apt 저장소 추가)
- 수집 로그: `/var/log/syslog`, `/var/log/auth.log`, `/var/log/nginx/access.log`, `/var/log/nginx/error.log`
- Elasticsearch(`10.0.0.10:9200`)로 로그 전송

### Ansible 실행 구조 (site.yml)

```
all       → common, monitoring, logging
web       → web
was       → was
db        → db
bastion   → bastion
```
Ansible 부분 실행 (변경된 Role만 실행)
deploy.yml은 변경된 파일을 감지하여 수정된 Role만 선택적으로 실행합니다.
변경 파일 감지 (dorny/paths-filter)
    │
    ├── terraform 변경 or group_vars/site.yml/requirements.yml 변경
    │     └── 전체 실행: ansible-playbook site.yml
    │
    └── 특정 role만 변경
          └── 부분 실행: ansible-playbook site.yml --tags "web,was"

각 role은 site.yml에 태그로 정의되어 있으며, 변경된 role에 해당하는 태그만 추려서 실행합니다.

| 변경 경로 | 실행 태그 |
|---|---|
| `roles/common/**`, `group_vars/all.yml` | `common` |
| `roles/web/**`, `group_vars/web.yml` | `web` |
| `roles/was/**`, `group_vars/was.yml` | `was` |
| `roles/db/**`, `group_vars/db.yml` | `db` |
| `roles/bastion/**`, `group_vars/bastion.yml` | `bastion` |
| `roles/monitoring/**` | `monitoring` |
| `roles/logging/**` | `logging` |
| terraform 변경 or 공통 설정 변경 | 전체 실행 |

---

## 🔑 필요한 GitHub Secrets

| Secret 이름 | 설명 |
|---|---|
| `AWS_ACCESS_KEY_ID` | AWS IAM Access Key |
| `AWS_SECRET_ACCESS_KEY` | AWS IAM Secret Key |
| `SSH_PRIVATE_KEY` | EC2 접속용 SSH Private Key (id_ed25519) |

> EC2 Key Pair(`FF-test-key`)의 공개키는 AWS에 미리 등록되어 있어야 합니다.

---

## 🚀 배포 방법

### 신규 배포

1. `terraform_files/` 또는 `ansible_files/` 수정 후 `main` 브랜치에 PR 생성
2. `validate.yml` — 코드 검증 자동 실행
3. `plan.yml` — Terraform Plan 결과가 PR 코멘트에 자동 등록
4. PR Merge → `deploy.yml` 자동 실행
   - GitHub Environment `production` 승인 필요
   - Terraform apply → Ansible 실행 순으로 자동 처리

### 인프라 삭제

GitHub Actions → `Destroy` 워크플로우 수동 실행
- 확인 문자열 `destroy` 입력 필수
- 삭제 범위 선택: `all` / `ec2_only` / `security_group_only`

### 로컬에서 직접 실행 (개발/디버깅)

```bash
# Terraform
cd terraform_files
terraform init
terraform plan
terraform apply

# Ansible
cd ansible_files
ansible-galaxy install -r requirements.yml -p ~/.ansible/roles
ansible-galaxy collection install prometheus.prometheus
ansible-galaxy collection install grafana.grafana
ansible-playbook -i inventory.yml site.yml
```

---

## 📊 접속 정보 (배포 후)

| 서비스 | URL | 비고 |
|---|---|---|
| 웹 서비스 | `http://<Bastion Public IP>` | Nginx → nginx-fe → FastAPI |
| Prometheus | `http://<Bastion Public IP>:9090` | 메트릭 수집 |
| Grafana | `http://<Bastion Public IP>:3000` | 대시보드 (기본 admin/admin) |

```bash
# Terraform output에서 SSH 명령어 확인
terraform output ssh_bastion_command
terraform output ssh_private_server_commands
```

---

## 📝 주요 변수

| 파일 | 변수 | 기본값 |
|---|---|---|
| `variables.tf` | `aws_region` | `ap-northeast-2` |
| `variables.tf` | `instance_type` | `t3.small` |
| `variables.tf` | `vpc_cidr` | `172.16.0.0/16` |
| `group_vars/db.yml` | `postgres_db` | `app_db` |
| `group_vars/db.yml` | `postgres_user` | `app_user` |
| `group_vars/was.yml` | `fastapi_port` | `8000` |
| `group_vars/web.yml` | `nginx_listen_port` | `80` |

---

## 🛠️ 사용 기술 스택

| 분류 | 기술 |
|---|---|
| IaC | Terraform >= 1.6.0, AWS Provider ~> 6.0 |
| 구성 관리 | Ansible, geerlingguy.nginx, geerlingguy.postgresql |
| 모니터링 | Prometheus 2.47.0, Grafana, Node Exporter 1.7.0 |
| 로그 수집 | Fluent-bit → Elasticsearch |
| 애플리케이션 | FastAPI, Gunicorn, Uvicorn, Python venv |
| 데이터베이스 | PostgreSQL 16 |
| 웹 서버 | Nginx |
| CI/CD | GitHub Actions |
| 클라우드 | AWS (ap-northeast-2) |
| 상태 관리 | S3 (`fastforward-tfstate`) + DynamoDB Lock |