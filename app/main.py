from fastapi import FastAPI, HTTPException
from sqlalchemy import text
from sqlalchemy.exc import SQLAlchemyError
from app.database import engine
from app import routes, user_routes
from prometheus_fastapi_instrumentator import Instrumentator


app = FastAPI()

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