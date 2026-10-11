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
│   └── workflows/
│       ├── deploy.yml            # EC2 deployment automation
│       └── pull_requests.yml     # CI validation for pull requests
├── app/
│   ├── __init__.py              # package marker
│   ├── auth.py                  # JWT + password utilities
│   ├── database.py              # SQLAlchemy engine, session, DB config
│   ├── main.py                  # FastAPI app bootstrap and health routes
│   ├── models.py                # User and Task ORM models
│   ├── routes.py                # authentication endpoints
│   ├── schemas.py               # Pydantic request/response models
│   └── user_routes.py           # task CRUD API routes
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
├── .gitignore                   # ignores local environment and generated files
├── Dockerfile                   # container image for the FastAPI app
├── docker-compose.yml           # multi-service local deployment stack
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
- **AWS EC2**: Virtual machine used for online app deployment.
- **GitHub Actions**: Workflow CI/CD pipeline automation tool, ensuring all pushed code is functional before deployment.
- **Prometheus**: Pulls metrics data from app, visualised in Grafana
- **Grafana**: Visualises metric data from Prometheus in user-friendly UI
- **Socket Proxy**: Tecnativa socket proxy, for securing access to docker socket


### Startup
1. Clone the repo
```bash
    git clone https://github.com/IvanKennethBibat/task-api
    cd task-api
```

2. Create the venv
```bash
    python3 -m venv venv
    source venv/bin/activate
```
3. Install required dependencies
```bash
    pip install -r requirements.txt
```

4. Create `.env` in root
```bash
    DATABASE_URL=postgresql://taskuser:taskpassword@db:5432/taskdb
```

5. Start the application
```bash
docker compose up -d
```

### API Endpoints
- **API**: http://localhost/docs
- **Grafana**: http://localhost/grafana
- **Prometheus**: http://localhost/prometheus
- **Traefik**: http://localhost:80

### CI/CD Pipeline
GitHub Actions tests each API Endpoint after each code commit, ensuring each feature works as expected prior to deployment on the EC2 virtual machine.