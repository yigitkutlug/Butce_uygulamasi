import importlib
import os

os.environ.setdefault("JWT_SECRET", "test_secret_for_pytest_only")


def test_password_hash_and_verify_roundtrip():
    security = importlib.import_module("app.core.security")
    plain = "Sup3rSecret!"
    hashed = security.get_password_hash(plain)

    assert hashed != plain
    assert security.verify_password(plain, hashed) is True
    assert security.verify_password("wrong-pass", hashed) is False


def test_create_access_token_returns_non_empty_string():
    security = importlib.import_module("app.core.security")
    token = security.create_access_token("user-123")
    assert isinstance(token, str)
    assert len(token) > 20
