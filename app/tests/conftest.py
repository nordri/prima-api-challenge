import os
import sys
from pathlib import Path


APP_DIR = Path(__file__).parent.parent / "prima-tech-challenge"
sys.path.insert(0, str(APP_DIR))

os.environ.setdefault("DYNAMODB_TABLE", "test-users")
os.environ.setdefault("S3_BUCKET", "test-avatars")
os.environ.setdefault("LOCALSTACK_HOST", "http://localhost:4566")
