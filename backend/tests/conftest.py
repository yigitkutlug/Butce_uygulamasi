import os
import sys
from pathlib import Path

# Make `app` importable when tests are executed from repository root or backend.
BACKEND_DIR = Path(__file__).resolve().parents[1]
if str(BACKEND_DIR) not in sys.path:
    sys.path.insert(0, str(BACKEND_DIR))

# Ensure security settings can initialize in test environments.
os.environ.setdefault("JWT_SECRET", "test_secret_for_pytest_only")
