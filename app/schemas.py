
from pydantic import BaseModel, ConfigDict, Field, field_validator

TITLE_MAX_LENGTH = 200
PASSWORD_MAX_LENGTH = 128

class TaskCreate(BaseModel):
    title: str = Field(min_length=1, max_length=TITLE_MAX_LENGTH)

class TaskResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: int
    title: str
    completed: bool

class TaskUpdate(BaseModel):
    title: str | None = Field(default=None, min_length=1, max_length=TITLE_MAX_LENGTH)
    completed: bool | None = None

class UserCreate(BaseModel):
    username: str = Field(min_length=3, max_length=50, pattern=r"^[A-Za-z0-9_.-]+$")
    password: str = Field(min_length=8, max_length=PASSWORD_MAX_LENGTH)

    @field_validator("password")
    @classmethod
    def password_must_contain_special(cls, v):
        special_characters = "!@#$%^&*()_+-=[]{}|;:,.<>?"
        if not any(char in special_characters for char in v):
            raise ValueError("Password needs at least one special character.")
        
        return v

class UserResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: int
    username: str

class Token(BaseModel):
    access_token: str
    token_type: str