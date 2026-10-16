# Task API

### Problem Statement

Starting projects from scratch is slow and tedious. This project serves as a boilerplate for future projects to accelerate the initial setup phase.

### Description
REST API built using FastAPI and PostgreSQL, using Docker to containerise the application. Traefik acting as a reverse proxy, routing traffic to the API.

### Architecture


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
│   ├── main.tf                  # VPC, EC2 server, backups bucket, IAM, SSM deploy document, GitHub OIDC role
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

Prerequisites: AWS CLI with the Session Manager plugin, Terraform >= 1.5, the domain's DNS in Cloudflare, and a Cloudflare API token with `Zone:DNS:Edit` on that zone.

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
```bash
cd terraform
terraform init
terraform apply
```

3. In Cloudflare, add an `A` record for `api_domain` pointing at `terraform output public_ip`. Certificates are issued through the Cloudflare DNS challenge, so this can happen before or after the server is up.

4. On first boot the server installs Docker, clones the repo and deploys. Follow it with:
```bash
$(terraform output -raw ssm_session_command)
sudo tail -f /var/log/cloud-init-output.log
```

5. For automatic deploys, add these GitHub repository variables (Settings → Secrets and variables → Actions → Variables) from the Terraform outputs: `AWS_DEPLOY_ROLE_ARN` (`github_deploy_role_arn`), `AWS_REGION` (`aws_region`), `DEPLOY_INSTANCE_ID` (`instance_id`), `DEPLOY_DOCUMENT_NAME` (`deploy_document_name`). From then on, every push to `main` that passes CI is deployed; the Deploy workflow can also be run by hand.

The non-secret server settings (domain, bucket, region, `ENABLE_DOCS`) are in `/etc/task-api/deploy.env` on the server. It is only written on first boot, so edit it there to change them, then redeploy. To deploy by hand from an SSM session: `sudo /opt/task-api/deploy/deploy.sh` (deploys the checked-out commit).

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
- **Grafana**: https://DOMAIN/grafana
- `/docs`, `/redoc` and `/openapi.json` are disabled. They are only served when `ENABLE_DOCS=true`, which the dev overlay sets; to enable them in production, add `ENABLE_DOCS=true` to `/etc/task-api/deploy.env` on the server and redeploy.
- Prometheus and `/metrics` are not exposed publicly; Prometheus scrapes the API over the internal Docker network.

`/login` and `/register` are rate-limited by Traefik to 5 requests per minute per IP.

### CI/CD Pipeline
GitHub Actions runs on every pull request and push to `main`:
- **lint**: `ruff check .`
- **test**: applies migrations to a throwaway PostgreSQL and runs `pytest`. No repository secrets are needed.
- **build**: builds the Docker image.
- **terraform**: `terraform fmt -check`, `validate` and `terraform test`, which runs plan-level checks against a mocked AWS provider, so no AWS credentials are needed.

After CI passes on a push to `main`, the **Deploy** workflow assumes the deploy role through GitHub OIDC (no AWS keys in GitHub) and runs the SSM deploy document on the server for that commit. It is skipped until the repository variables from the production setup are set.
