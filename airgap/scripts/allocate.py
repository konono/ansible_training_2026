#!/usr/bin/env python3
"""
演習環境の user_id 採番・管理スクリプト

Usage:
  allocate.py --username <user> --action allocate [--hostname <name>] [--client-ip <IP>]
  allocate.py --username <user> --action lookup
  allocate.py --username <user> --action release
  allocate.py --client-ip <IP> --action allocate [--hostname <name>]
  allocate.py --client-ip <IP> --action lookup
  allocate.py --client-ip <IP> --action release
  allocate.py --action status
  allocate.py --user-id <ID> --action release
"""

import argparse
import fcntl
import json
import os
import sys
import tempfile
from datetime import datetime

ALLOCATIONS_FILE = os.environ.get(
    "ALLOCATIONS_FILE", "/opt/training/allocations.json"
)
LOCK_FILE = os.environ.get(
    "LOCK_FILE", "/opt/training/.lock"
)
MAX_USER_ID = 99
LOCK_TIMEOUT = 30


def load_allocations():
    if os.path.exists(ALLOCATIONS_FILE):
        try:
            with open(ALLOCATIONS_FILE) as f:
                return json.load(f)
        except json.JSONDecodeError as e:
            print(
                f'{{"error": "allocations.json の読み込みに失敗しました: {e}"}}',
                file=sys.stderr,
            )
            sys.exit(1)
    return {"allocations": []}


def save_allocations(data):
    dirpath = os.path.dirname(ALLOCATIONS_FILE)
    os.makedirs(dirpath, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=dirpath, suffix=".tmp")
    try:
        with os.fdopen(fd, "w") as f:
            json.dump(data, f, indent=2, ensure_ascii=False)
        os.chmod(tmp, 0o644)
        os.replace(tmp, ALLOCATIONS_FILE)
    except BaseException:
        os.unlink(tmp)
        raise


def build_entry(user_id, client_ip, hostname, username=None, status="allocated"):
    entry = {
        "user_id": user_id,
        "username": username or "",
        "client_ip": client_ip or "",
        "client_hostname": hostname,
        "allocated_at": datetime.now().isoformat(timespec="seconds"),
        "ssh_port": 2200 + user_id,
        "subnet": f"172.20.{user_id}.0/24",
        "network_name": f"user{user_id}_ansible_net",
        "containers": {
            "controller": f"172.20.{user_id}.10",
            "node1": f"172.20.{user_id}.11",
            "node2": f"172.20.{user_id}.12",
            "node3": f"172.20.{user_id}.13",
            "lb": f"172.20.{user_id}.14",
        },
        "training_dir": f"/opt/training/user{user_id}",
        "status": status,
    }
    return entry


def _find_active_entry(data, username=None, client_ip=None):
    """username または client_ip でアクティブなエントリを検索"""
    for entry in data["allocations"]:
        if entry["status"] == "released":
            continue
        if username and entry.get("username") == username:
            return entry
        if client_ip and entry.get("client_ip") == client_ip:
            return entry
    return None


def allocate(username=None, client_ip=None, hostname="unknown"):
    data = load_allocations()

    existing = _find_active_entry(data, username=username, client_ip=client_ip)
    if existing:
        if username and not existing.get("username"):
            existing["username"] = username
            save_allocations(data)
        print(json.dumps(existing, ensure_ascii=False))
        return

    released = sorted(
        [e for e in data["allocations"] if e["status"] == "released"],
        key=lambda e: e["user_id"],
    )
    if released:
        user_id = released[0]["user_id"]
        data["allocations"] = [
            e for e in data["allocations"] if e["user_id"] != user_id
        ]
    else:
        used_ids = [
            e["user_id"]
            for e in data["allocations"]
            if e["status"] != "released"
        ]
        user_id = max(used_ids, default=0) + 1

    if user_id > MAX_USER_ID:
        print(
            f'{{"error": "user_id 上限 ({MAX_USER_ID}) に達しました。'
            f'不要な環境を destroy-training.sh で削除してください。"}}',
            file=sys.stderr,
        )
        sys.exit(1)

    entry = build_entry(user_id, client_ip, hostname, username=username)
    data["allocations"].append(entry)
    data["allocations"].sort(key=lambda e: e["user_id"])
    save_allocations(data)

    print(json.dumps(entry, ensure_ascii=False))


def lookup(username=None, client_ip=None):
    data = load_allocations()
    entry = _find_active_entry(data, username=username, client_ip=client_ip)
    if entry:
        print(json.dumps(entry, ensure_ascii=False))
        return
    print('{"error": "not found"}', file=sys.stderr)
    sys.exit(1)


def activate(username=None, client_ip=None):
    data = load_allocations()
    entry = _find_active_entry(data, username=username, client_ip=client_ip)
    if entry:
        entry["status"] = "active"
        entry["activated_at"] = datetime.now().isoformat(timespec="seconds")
        save_allocations(data)
        print(json.dumps(entry, ensure_ascii=False))
        return
    print('{"error": "not found"}', file=sys.stderr)
    sys.exit(1)


def release(username=None, client_ip=None, user_id=None):
    data = load_allocations()
    for entry in data["allocations"]:
        if entry["status"] == "released":
            continue
        username_ok = username is None or entry.get("username") == username
        ip_ok = client_ip is None or entry.get("client_ip") == client_ip
        id_ok = user_id is None or entry["user_id"] == user_id
        has_key = username is not None or client_ip is not None or user_id is not None
        if username_ok and ip_ok and id_ok and has_key:
            entry["status"] = "released"
            entry["released_at"] = datetime.now().isoformat(timespec="seconds")
            save_allocations(data)
            print(json.dumps(entry, ensure_ascii=False))
            return
    print('{"error": "not found"}', file=sys.stderr)
    sys.exit(1)


def status():
    data = load_allocations()
    print(json.dumps(data, indent=2, ensure_ascii=False))


def _acquire_lock(lf, lock_type):
    try:
        fcntl.flock(lf, lock_type | fcntl.LOCK_NB)
    except OSError:
        import time
        deadline = time.monotonic() + LOCK_TIMEOUT
        while True:
            try:
                fcntl.flock(lf, lock_type | fcntl.LOCK_NB)
                break
            except OSError:
                if time.monotonic() >= deadline:
                    print(
                        '{"error": "ロック取得タイムアウト"}',
                        file=sys.stderr,
                    )
                    sys.exit(1)
                time.sleep(0.1)


def with_lock(func, *args, **kwargs):
    os.makedirs(os.path.dirname(LOCK_FILE), exist_ok=True)
    with open(LOCK_FILE, "w") as lf:
        _acquire_lock(lf, fcntl.LOCK_EX)
        return func(*args, **kwargs)


def with_shared_lock(func, *args, **kwargs):
    os.makedirs(os.path.dirname(LOCK_FILE), exist_ok=True)
    try:
        lf = open(LOCK_FILE, "r")
    except FileNotFoundError:
        return func(*args, **kwargs)
    except PermissionError:
        return func(*args, **kwargs)
    with lf:
        _acquire_lock(lf, fcntl.LOCK_SH)
        return func(*args, **kwargs)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--client-ip", default=None)
    parser.add_argument("--username", default=None)
    parser.add_argument("--hostname", default="unknown")
    parser.add_argument("--user-id", type=int, default=None)
    parser.add_argument(
        "--action",
        required=True,
        choices=["allocate", "lookup", "activate", "release", "status"],
    )
    args = parser.parse_args()

    if args.action == "status":
        with_shared_lock(status)
        return

    if args.action == "release" and args.user_id:
        with_lock(release, user_id=args.user_id)
        return

    if not args.username and not args.client_ip:
        if args.action == "release" and args.user_id:
            pass
        else:
            print("--username or --client-ip required", file=sys.stderr)
            sys.exit(1)

    if args.action == "allocate":
        with_lock(allocate, username=args.username, client_ip=args.client_ip,
                  hostname=args.hostname)
    elif args.action == "lookup":
        with_shared_lock(lookup, username=args.username,
                         client_ip=args.client_ip)
    elif args.action == "activate":
        with_lock(activate, username=args.username, client_ip=args.client_ip)
    elif args.action == "release":
        with_lock(release, username=args.username, client_ip=args.client_ip,
                  user_id=args.user_id)


if __name__ == "__main__":
    main()
