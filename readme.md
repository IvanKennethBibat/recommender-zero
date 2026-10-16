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
│   │   └── pull_requests.yml     # CI lint, migrations, tests and image build
│   └── dependabot.yml            # weekly dependency, image and action updates
├── alembic/
│   ├── versions/
│   │   └── e30f5768187a_initial_schema.py # initial database schema
│   ├── env.py                    # Alembic environment configuration
│   ├── README                    # Alembic migration notes
│   └── script.py.mako            # migration revision template
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
│   ├── main.tf                  # Terraform AWS configuration
│   ├── outputs.tf               # Terraform output values
│   ├── terraform.tf              # Terraform and provider requirements
│   └── variable.tf               # Terraform variables
├── tests/
│   ├── __init__.py              # test package marker
│   └── test_tasks.py            # API test suite
├── .env.example                 # template for .env, copy and fill in
├── .gitignore                   # ignores local environment and generated files
├── alembic.ini                  # Alembic configuration
├── compose.yaml                 # base services: db, migrate, api, prometheus, grafana
├── docker-compose.dev.yaml      # dev overlay: Traefik on localhost over HTTP
├── docker-compose.prod.yaml     # prod overlay: Traefik with HTTPS via Let's Encrypt
├── Dockerfile                   # container image for the FastAPI app
├── prometheus.yml               # Prometheus scrape configuration
├── readme.md                    # project overview and setup docs
└── requirements.txt             # Python dependencies
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

#### Production
3. In `.env`, also set `DOMAIN` (bare hostname, e.g. `api.example.com`), `ACME_EMAIL` for Let's Encrypt, and `GF_SERVER_ROOT_URL=https://<DOMAIN>/grafana`. Point the domain's DNS at the server and open ports 80 and 443.

4. Start the stack.
```bash
docker compose -f compose.yaml -f docker-compose.prod.yaml up -d
```

#### Database migrations
The `migrate` service runs `alembic upgrade head` on every `up` and exits; the API waits for it and does not start if a migration fails (check `docker compose logs migrate`). When you change `app/models.py`, generate a new migration and commit it:
```bash
alembic revision --autogenerate -m "describe the change"
```

#### Running tests locally
Tests need a running PostgreSQL with migrations applied, plus `DATABASE_URL` and `SECRET_KEY` in the environment.
```bash
    python3 -m venv venv
    source venv/bin/activate
    pip install -r requirements.txt
    pytest
```

### API Endpoints
Development:
- **API docs**: http://localhost/docs
- **Grafana**: http://localhost/grafana
- **Prometheus**: http://localhost/prometheus

Production (HTTPS only, HTTP redirects):
- **API docs**: https://DOMAIN/docs
- **Grafana**: https://DOMAIN/grafana
- Prometheus and `/metrics` are not exposed publicly; Prometheus scrapes the API over the internal Docker network.

`/login` and `/register` are rate-limited by Traefik to 5 requests per minute per IP.

### CI/CD Pipeline
GitHub Actions runs on every pull request and push to `main`:
- **lint**: `ruff check .`
- **test**: applies migrations to a throwaway PostgreSQL and runs `pytest`. No repository secrets are needed.
- **build**: builds the Docker image.
