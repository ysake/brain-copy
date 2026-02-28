#!/usr/bin/env python3
"""
APIキーをコマンドライン引数で渡してAPIサーバーを起動するスクリプト。

使い方:
  python scripts/run_api.py YOUR_MISTRAL_API_KEY
  python scripts/run_api.py YOUR_MISTRAL_API_KEY --port 8001

引数なしの場合は .env または環境変数 MISTRAL_API_KEY を参照します。
"""
import os
import subprocess
import sys


def main() -> None:
    # このスクリプトがあるディレクトリ → knowledge-organizer のルート
    script_dir = os.path.dirname(os.path.abspath(__file__))
    root_dir = os.path.dirname(script_dir)
    os.chdir(root_dir)

    env = os.environ.copy()
    if len(sys.argv) >= 2 and not sys.argv[1].startswith("-"):
        api_key = sys.argv[1]
        env["MISTRAL_API_KEY"] = api_key
        # uvicorn に渡す引数は2つ目以降（--port など）
        uvicorn_args = sys.argv[2:]
    else:
        uvicorn_args = sys.argv[1:]

    cmd = [sys.executable, "-m", "uvicorn", "apps.api.main:app", "--reload", *uvicorn_args]
    subprocess.run(cmd, env=env)


if __name__ == "__main__":
    main()
