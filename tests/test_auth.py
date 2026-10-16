from argon2 import PasswordHasher

from app.auth import hash_password, password_needs_rehash, verify_password

# Hash created by passlib before it was removed, to keep existing users' passwords working
PASSLIB_HASH = "$argon2id$v=19$m=65536,t=3,p=4$CUFo7f3fm3POmdPauzdmjA$xHk+oDqilrZM2oVmqmtCViwDiBTZYTUaqfFsIhmRk6w"


def test_hash_and_verify():
    hashed = hash_password("Secret!pass")
    assert hashed.startswith("$argon2id$")
    assert verify_password("Secret!pass", hashed)
    assert not verify_password("wrong", hashed)


def test_verifies_passlib_hash():
    assert verify_password("OldUser!pass", PASSLIB_HASH)
    assert not verify_password("wrong", PASSLIB_HASH)


def test_invalid_hash_returns_false():
    assert not verify_password("anything", "not-a-hash")


def test_needs_rehash_for_weaker_parameters():
    weak_hash = PasswordHasher(time_cost=1, memory_cost=8192).hash("Secret!pass")
    assert password_needs_rehash(weak_hash)
    assert not password_needs_rehash(hash_password("Secret!pass"))
