from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.security import OAuth2PasswordRequestForm
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app import models, schemas
from app.auth import (
    DUMMY_PASSWORD_HASH,
    create_access_token,
    hash_password,
    password_needs_rehash,
    verify_password,
)
from app.database import get_db

router = APIRouter()

@router.post("/register", response_model=schemas.UserResponse)
def register(user: schemas.UserCreate, db: Session = Depends(get_db)):
    new_user = models.User(
        username=user.username,
        hashed_password=hash_password(user.password)
    )
    db.add(new_user)
    # Rely on the unique constraint rather than a pre-check, so concurrent signups for the same name get a 400 instead of a 500
    try:
        db.commit()
    except IntegrityError:
        db.rollback()
        raise HTTPException(status_code=400, detail="Username already exists")
    db.refresh(new_user)
    return new_user

@router.post("/login", response_model=schemas.Token)
def login(form_data: OAuth2PasswordRequestForm = Depends(), db: Session = Depends(get_db)):
    invalid_credentials = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Invalid credentials"
    )
    if len(form_data.password) > schemas.PASSWORD_MAX_LENGTH:
        raise invalid_credentials
    user = db.query(models.User).filter(models.User.username == form_data.username).first()
    if user is None:
        # Hash anyway so unknown usernames take as long as wrong passwords and can't be enumerated by timing
        verify_password(form_data.password, DUMMY_PASSWORD_HASH)
        raise invalid_credentials
    if not verify_password(form_data.password, user.hashed_password):
        raise invalid_credentials
    if password_needs_rehash(user.hashed_password):
        user.hashed_password = hash_password(form_data.password)
        db.commit()
    access_token = create_access_token(data={"sub": user.username})
    return {"access_token": access_token, "token_type": "bearer"}