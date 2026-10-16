import os

from fastapi import FastAPI, HTTPException
from prometheus_fastapi_instrumentator import Instrumentator
from sqlalchemy import text
from sqlalchemy.exc import SQLAlchemyError

from app import routes, user_routes
from app.database import engine

# Interactive docs and the OpenAPI schema are off unless explicitly enabled (the dev overlay turns them on)
ENABLE_DOCS = os.getenv("ENABLE_DOCS", "false").lower() == "true"

app = FastAPI(
    docs_url="/docs" if ENABLE_DOCS else None,
    redoc_url="/redoc" if ENABLE_DOCS else None,
    openapi_url="/openapi.json" if ENABLE_DOCS else None,
)

Instrumentator().instrument(app).expose(app)

app.include_router(routes.router)
app.include_router(user_routes.router)

@app.get("/")
def root():
    return {"message": "task-api is running"}

@app.get("/health")
def health():
    return {"status": "ok"}

@app.get("/ready")
def readiness_check():
    try:
        with engine.connect() as connection:
            connection.execute(text("SELECT 1"))

        return {"status": "ready"}

    except SQLAlchemyError:
        raise HTTPException(
            status_code=503,
            detail="Service temporarily unavailable",
        )