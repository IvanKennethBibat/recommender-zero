# Recommender-zero

- **App**: FastAPI + PostgreSQL (SQLAlchemy, Alembic), argon2 password hashing, JWT auth, input limits, rate-limited login.
- **Runtime**: one Docker Compose stack for dev and prod (Traefik, Prometheus, Grafana, scheduled backups), with environment differences kept in small overlays.
- **Infrastructure**: Terraform for an ARM EC2 server, S3 backups bucket and least-privilege IAM, with no SSH and no secrets in state.
- **Delivery**: GitHub Actions runs lint, tests, an image build and Terraform checks, then deploys `main` through SSM using OIDC, with a health check and one-run rollbacks.

### Architecture
Runtime, on one EC2 instance:
```mermaid
flowchart LR
    client([Client]) -->|"HTTPS :443<br/>(DNS on Cloudflare)"| traefik
    subgraph ec2 ["EC2 t4g.small: Docker Compose (prod overlay)"]
        traefik["Traefik<br/>TLS, HTTP→HTTPS, rate limits"] --> api["FastAPI"]
        api --> db[("PostgreSQL")]
        migrate["migrate<br/>alembic upgrade, one-off"] --> db
        backup["backup<br/>daily pg_dump"] --> db
        prometheus["Prometheus"] -->|"scrapes /metrics"| api
        grafana["Grafana"] --> prometheus
    end
    backup -->|upload| s3[("S3 backups<br/>30-day expiry")]
    traefik -.->|"DNS-01 challenge"| cfapi["Cloudflare API"]
    you([You]) -.->|"SSM port forward"| grafana
```

Delivery, from merge to running:
```mermaid
flowchart LR
    merge([Merge to main]) --> ci["CI<br/>lint, tests, image build,<br/>terraform checks"]
    ci -->|passes| deploy["Deploy workflow"]
    deploy -->|"OIDC, no stored keys"| role["IAM deploy role"]
    role -->|"ssm:SendCommand<br/>(deploy document only)"| server["EC2<br/>checkout SHA from main,<br/>render .env, compose up --wait"]
    params[("SSM Parameter Store<br/>secrets")] --> server
    deploy -->|"GET /ready"| health{"healthy?"}
    health -->|no| rollback["Re-run Deploy with<br/>the previous SHA"]
```
`terraform apply`, run from your machine, creates the instance, bucket, IAM roles, deploy document and GitHub OIDC provider.

### Design decisions
- **One instance running Compose, not ECS/EKS and RDS.** A `t4g.small` with a 20 GiB volume and a public IPv4 address costs roughly $20 a month on demand, and dev and prod run the same stack, so what works locally works on the server. The trade-offs are deliberate: one instance is a single point of failure, a deploy restarts containers (a few seconds of downtime), and the database lives on the instance's disk.
- **What I'd change at scale**: move Postgres to RDS (managed backups, point-in-time recovery, Multi-AZ), build images once in CI and push them to ECR, run the API on ECS Fargate or several instances behind a load balancer for zero-downtime deploys, and add alerting.
- **No SSH, no long-lived keys.** Port 22 is closed; shell access and deploys go through SSM. GitHub gets short-lived credentials through OIDC for a role that can only run one deploy document on one instance, and that document only accepts a commit already on `main`.
- **Secrets only in SSM Parameter Store.** Terraform knows the parameter path, never the values, so neither state nor the repo holds secrets; the server writes `.env` from SSM on every deploy.
- **Server settings come from Terraform too.** Domain, ACME email, backup bucket and the docs flag are Terraform-managed SSM parameters under `/<project_name>/config/`, read on every deploy, so the server holds no hand-edited configuration.
- **Shared, versioned Terraform state.** State lives in a versioned, encrypted S3 bucket with S3-native locking, created by a small bootstrap config, so anyone with access can run Terraform and a bad apply can be rolled back to an earlier state version.
- **Failure budget.** Backups run daily, so losing the instance loses up to 24 hours of writes (shorten `BACKUP_INTERVAL_SECONDS` for less). Recovery means `terraform apply` for a new server, then restoring the latest dump from S3; this is manual.

### Known limitations
Kept here deliberately, in the order I'd tackle them:
- **The deployed image isn't the tested one.** CI builds an x86 image and discards it; the ARM server builds its own from the same commit. Next step: build arm64 in CI, push to ECR, deploy by digest.
- **Metrics without alerts.** Prometheus and Grafana show what happened, but nothing pages anyone. Next step: Grafana alerting to email or Slack.
- **Rollbacks don't undo migrations.** Write migrations that the previous release can still run against (add columns before using them, drop them a release later), or restore a backup.

## Map
```text
task-api
├── .github/
│   ├── workflows/
│   │   ├── deploy.yml            # deploys main to the AWS server via SSM after CI passes
│   │   └── pull_requests.yml     # CI lint, migrations, tests and image build
│   └── dependabot.yml            # weekly dependency, image and action updates
├── alembic/
│   ├── versions/
│   │   └── e30f5768187a_initial_schema.py # initial database schema
│   ├── env.py                    # Alembic environment configuration
│   ├── README                    # Alembic migration notes
│   └── script.py.mako            # migration revision template
├── backup/
│   ├── backup.sh                 # scheduled pg_dump, pruning and optional S3 upload
│   └── Dockerfile                # Postgres client + AWS CLI image for the backup service
├── deploy/
│   ├── deploy.sh                 # server-side redeploy of the checked-out commit
│   └── render-env.sh             # writes the production .env from SSM Parameter Store
├── app/
│   ├── __init__.py              # package marker
│   ├── auth.py                  # JWT + password utilities
│   ├── database.py              # SQLAlchemy engine, session, DB config
│   ├── main.py                  # FastAPI app bootstrap and health routes
│   ├── models.py                # User and Task ORM models
│   ├── routes.py                # task CRUD API routes
│   ├── schemas.py               # Pydantic request/response models
│   └── user_routes.py           # authentication endpoints
├── grafana/
│   ├── dashboards/
│   │   └── api-overview.json     # provisioned API metrics dashboard
│   └── provisioning/
│       ├── dashboards/
│       │   └── provider.yml      # dashboard file provider
│       └── datasources/
│           └── datasource.yml    # Prometheus data source
├── terraform/
│   ├── backend.hcl.example       # template for backend.hcl (state bucket settings)
│   ├── bootstrap/
│   │   └── main.tf               # one-off: S3 bucket for Terraform state
│   ├── main.tf                  # VPC, EC2 server, backups bucket, IAM, SSM parameters and deploy document, GitHub OIDC role
│   ├── outputs.tf               # Terraform output values
│   ├── terraform.tf              # Terraform and provider requirements
│   ├── terraform.tfvars.example  # template for terraform.tfvars, copy and fill in
│   ├── tests/
│   │   └── plan.tftest.hcl       # terraform test checks against a mocked AWS provider
│   ├── user_data.sh.tftpl        # first-boot setup for the server
│   └── variable.tf               # Terraform variables
├── tests/
│   ├── __init__.py              # test package marker
│   ├── test_auth.py             # password hashing and auth route tests
│   └── test_tasks.py            # API test suite
├── .env.example                 # template for .env, copy and fill in
├── .gitignore                   # ignores local environment and generated files
├── alembic.ini                  # Alembic configuration
├── compose.yaml                 # base services: db, backup, migrate, api, prometheus, grafana
├── docker-compose.dev.yaml      # dev overlay: Traefik on localhost over HTTP
├── docker-compose.prod.yaml     # prod overlay: HTTPS via Let's Encrypt (Cloudflare DNS), S3 backups
├── Dockerfile                   # container image for the FastAPI app
├── prometheus.yml               # Prometheus scrape configuration
├── readme.md                    # project overview and setup docs
├── requirements.txt             # runtime Python dependencies (installed in the image)
└── requirements-dev.txt         # test and lint tools on top of requirements.txt
```

### Tech Stack
- **FastAPI**: Acts as the pipeline between the traffic requests and the database.
- **PostgreSQL**: The persistent database for storing data from requests.
- **SQLAlchemy**: An Object-Relational-Mapper (ORM), used for managing database requests, and mapping Python objects to database tables.
- **Docker**: Containerises the application and databases, removing dependency issues, improving reproducibility.
- **Traefik**: Acts as a middleman between public traffic and the API keeping the database and API server private.
- **GitHub Actions**: Workflow CI/CD pipeline automation tool, ensuring all pushed code is functional before deployment.
- **Prometheus**: Pulls metrics data from app, visualised in Grafana
- **Grafana**: Visualises metric data from Prometheus in user-friendly UI
- **Socket Proxy**: Tecnativa socket proxy, for securing access to docker socket
- **Terraform**: IaC tool to configure cloud resources with reproducibility.


### Using this template
When starting a new project from this repo:
1. **Name it**: pick a `project_name` for Terraform (it also sets the SSM path `/<project_name>/`), and rename the `task_*` container names in `compose.yaml` and `docker-compose.prod.yaml`, the `task-api-*` image names in `compose.yaml`, the `docker build` tag in `.github/workflows/pull_requests.yml`, the Prometheus `job_name` in `prometheus.yml`, and the root message in `app/main.py`. Paths on the server (`/opt/task-api`, `/etc/task-api`) are internal and can stay.
2. **Replace the example domain**: swap the `Task` model, `app/routes.py`, `app/schemas.py` and `tests/test_tasks.py` for your own. Keep `User`, `app/auth.py` and `app/user_routes.py` if you want the built-in auth. Then delete `alembic/versions/e30f5768187a_initial_schema.py` and generate a fresh initial migration against an empty database: `alembic revision --autogenerate -m "initial schema"`.
3. **Point it at your repo**: update the clone URL below, and set `repository_url` and `github_repository` in `terraform/terraform.tfvars` (see Production).
4. **Set up GitHub**: CI needs nothing. For deploys, add the repository variables listed in Production step 5 after `terraform apply`.

### Startup
`compose.yaml` holds the shared services and is always combined with an overlay: `docker-compose.dev.yaml` for local work or `docker-compose.prod.yaml` for a server. Running `docker compose up` on `compose.yaml` alone starts no Traefik, so the API is unreachable.

1. Clone the repo
```bash
    git clone https://github.com/IvanKennethBibat/task-api
    cd task-api
```

2. Create `.env` from the example and replace every value. Generate `SECRET_KEY` with `openssl rand -hex 32`; the API refuses to start if it is shorter than 32 characters. Compose stops with an error if a required value is missing.
```bash
    cp .env.example .env
```

#### Development
3. Start the stack. Traefik listens on `127.0.0.1:80` only.
```bash
docker compose -f compose.yaml -f docker-compose.dev.yaml up -d
```

#### Production (AWS)
Terraform provisions the infrastructure; the server builds and runs the same compose stack with the prod overlay. Secrets live in SSM Parameter Store and are never stored in Terraform state or the repo.

What `terraform/` creates: a VPC with one public subnet, an ARM (Graviton) EC2 instance running Ubuntu 24.04 with an Elastic IP, a security group open only on 80 and 443 (no SSH; shell access is through SSM Session Manager), a private encrypted S3 bucket for backups, an instance role, an SSM document that deploys a given commit, and a GitHub Actions OIDC role that can run only that document on that instance.

Prerequisites: AWS CLI with the Session Manager plugin, Terraform >= 1.10, the domain's DNS in Cloudflare, and a Cloudflare API token with `Zone:DNS:Edit` on that zone.

1. Create the secrets as SSM SecureStrings under `/<project_name>/` (default `/task-api/`) in the region you deploy to. Values must not contain a single quote or newline; hex from `openssl rand` is safest.
```bash
REGION=eu-north-1 PREFIX=/task-api
aws ssm put-parameter --region $REGION --type SecureString --name $PREFIX/secret-key --value "$(openssl rand -hex 32)"
aws ssm put-parameter --region $REGION --type SecureString --name $PREFIX/postgres-password --value "$(openssl rand -hex 24)"
aws ssm put-parameter --region $REGION --type SecureString --name $PREFIX/grafana-admin-password --value "$(openssl rand -hex 16)"
aws ssm put-parameter --region $REGION --type SecureString --name $PREFIX/cloudflare-dns-api-token --value '<cloudflare token>'
```
   Postgres only reads its password when the data volume is first created; changing `postgres-password` later also requires `ALTER USER app PASSWORD '...'` in the database.

2. Create `terraform/terraform.tfvars` from the example (`cp terraform/terraform.tfvars.example terraform/terraform.tfvars`; it is gitignored), fill it in and apply. `api_domain`, `acme_email`, `repository_url` and `github_repository` are required and have no defaults, so a clone can never trust or deploy another repository; `github_repository` is `owner/name`, not a URL. If the AWS account already has a GitHub OIDC provider, set `create_github_oidc_provider = false`.
```hcl
aws_region        = "eu-north-1"
project_name      = "task-api"
api_domain        = "api.example.com"
acme_email        = "you@example.com"
repository_url    = "https://github.com/YOUR_ORG/YOUR_REPO.git"
github_repository = "YOUR_ORG/YOUR_REPO"
```
   First create the state bucket, once per project (use the same `aws_region` and `project_name` as in `terraform.tfvars`). Its own state is local and only covers this bucket, which is protected from `terraform destroy`:
```bash
cd terraform/bootstrap
terraform init
terraform apply -var aws_region=eu-north-1 -var project_name=task-api
terraform output -raw backend_config > ../backend.hcl
```
   Then initialise the main configuration against that bucket and apply:
```bash
cd ..
terraform init -backend-config=backend.hcl
terraform apply
```

3. In Cloudflare, add an `A` record for `api_domain` pointing at `terraform output public_ip`. Certificates are issued through the Cloudflare DNS challenge, so this can happen before or after the server is up.

4. On first boot the server installs Docker, clones the repo and deploys. Follow it with:
```bash
$(terraform output -raw ssm_session_command)
sudo tail -f /var/log/cloud-init-output.log
```

5. For automatic deploys, add these GitHub repository variables (Settings → Secrets and variables → Actions → Variables) from the Terraform outputs: `AWS_DEPLOY_ROLE_ARN` (`github_deploy_role_arn`), `AWS_REGION` (`aws_region`), `DEPLOY_INSTANCE_ID` (`instance_id`), `DEPLOY_DOCUMENT_NAME` (`deploy_document_name`). Optionally set `DEPLOY_HEALTH_URL` to `https://<api_domain>/ready`, which the workflow checks after each deploy. From then on, every push to `main` that passes CI is deployed; the Deploy workflow can also be run by hand.

#### Rollback
Every deploy log prints `Previously deployed: <sha>`. To roll back, run the **Deploy** workflow by hand (Actions → Deploy → Run workflow) and paste that SHA, or any other commit on `main`, into `commit`. The server refuses commits that aren't on `main`. A rollback redeploys the old code but leaves the database schema as it is; see Known limitations.

#### Grafana and Prometheus in production
They aren't exposed publicly: both listen on the server's loopback only. Open a tunnel with the AWS CLI and Session Manager plugin, then browse to it locally:
```bash
$(terraform output -raw grafana_tunnel_command)   # then http://localhost:3000/grafana
```
Log in as `admin` with the `grafana-admin-password` parameter. For Prometheus, run the same command with `portNumber=9090,localPortNumber=9090` and open http://localhost:9090/prometheus.

Server settings (domain, ACME email, backup bucket, `enable_docs`) are Terraform-managed SSM parameters under `/<project_name>/config/`. To change one, edit `terraform.tfvars`, run `terraform apply`, then redeploy. The only file on the server, `/etc/task-api/deploy.env`, holds the region and parameter prefix. To deploy by hand from an SSM session: `sudo /opt/task-api/deploy/deploy.sh` (deploys the checked-out commit).

If you turn on Cloudflare's proxy (orange cloud), Traefik sees Cloudflare's IPs instead of clients', so the `/login` and `/register` rate limit applies per Cloudflare edge rather than per user.

#### Database migrations
The `migrate` service runs `alembic upgrade head` on every `up` and exits; the API waits for it and does not start if a migration fails (check `docker compose logs migrate`). When you change `app/models.py`, generate a new migration and commit it:
```bash
alembic revision --autogenerate -m "describe the change"
```

#### Backups
The `backup` service runs `pg_dump` every `BACKUP_INTERVAL_SECONDS` (default daily) into the `backup_data` volume and deletes local dumps older than `BACKUP_KEEP_DAYS` (default 7). In production it also uploads each dump to the S3 bucket from Terraform, which keeps them for `backup_retention_days` (default 30). Check it with `docker compose logs backup`.

To restore, stop the API, restore a dump, and start it again (add `-f compose.yaml -f docker-compose.<dev|prod>.yaml` to each command):
```bash
docker compose exec backup ls /backups
docker compose stop api
docker compose exec backup sh -c 'pg_restore --clean --if-exists --no-owner --dbname="$PGDATABASE" /backups/<file>.dump'
docker compose start api
```
To restore from S3 in production, first copy the dump into the volume: `docker compose exec backup aws s3 cp s3://<bucket>/<file>.dump /backups/`.

#### Running tests locally
Tests need a running PostgreSQL with migrations applied, plus `DATABASE_URL` and `SECRET_KEY` in the environment.
```bash
    python3 -m venv venv
    source venv/bin/activate
    pip install -r requirements-dev.txt
    pytest
```

### API Endpoints
Development:
- **API docs**: http://localhost/docs
- **Grafana**: http://localhost/grafana
- **Prometheus**: http://localhost/prometheus

Production (HTTPS only, HTTP redirects):
- **API**: https://DOMAIN
- **Grafana and Prometheus**: through an SSM tunnel only (see Production).
- `/docs`, `/redoc` and `/openapi.json` are disabled. They are only served when `ENABLE_DOCS=true`, which the dev overlay sets; to enable them in production, set `enable_docs = true` in `terraform.tfvars`, run `terraform apply`, then redeploy.
- `/metrics` is not exposed publicly; Prometheus scrapes the API over the internal Docker network.

`/login` and `/register` are rate-limited by Traefik to 5 requests per minute per IP.

### CI/CD Pipeline
GitHub Actions runs on every pull request and push to `main`:
- **lint**: `ruff check .`
- **test**: applies migrations to a throwaway PostgreSQL and runs `pytest`. No repository secrets are needed.
- **build**: builds the Docker image.
- **terraform**: `terraform fmt -check`, `validate` and `terraform test`, which runs plan-level checks against a mocked AWS provider, so no AWS credentials are needed; the bootstrap config is validated too.

After CI passes on a push to `main`, the **Deploy** workflow assumes the deploy role through GitHub OIDC (no AWS keys in GitHub), runs the SSM deploy document on the server for that commit, and then checks `DEPLOY_HEALTH_URL` if it's set. It can also be run by hand with a `commit` to roll back. It is skipped until the repository variables from the production setup are set.
