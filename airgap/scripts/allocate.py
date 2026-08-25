#!/usr/bin/env python3
"""
演習環境の user_id 採番・管理スクリプト

Usage:
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
        os.replace(tmp, ALLOCATIONS_FILE)
    except BaseException:
        os.unlink(tmp)
        raise


def build_entry(user_id, client_ip, hostname, status="allocated"):
    return {
        "user_id": user_id,
        "client_ip": client_ip,
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


def allocate(client_ip, hostname):
    data = load_allocations()

    for entry in data["allocations"]:
        if entry["client_ip"] == client_ip and entry["status"] != "released":
            entry_json = json.dumps(entry, ensure_ascii=False)
            print(entry_json)
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

    entry = build_entry(user_id, client_ip, hostname)
    data["allocations"].append(entry)
    data["allocations"].sort(key=lambda e: e["user_id"])
    save_allocations(data)

    print(json.dumps(entry, ensure_ascii=False))


def lookup(client_ip):
    data = load_allocations()
    for entry in data["allocations"]:
        if entry["client_ip"] == client_ip and entry["status"] != "released":
            print(json.dumps(entry, ensure_ascii=False))
            return
    print('{"error": "not found"}', file=sys.stderr)
    sys.exit(1)


def activate(client_ip):
    data = load_allocations()
    for entry in data["allocations"]:
        if entry["client_ip"] == client_ip and entry["status"] != "released":
            entry["status"] = "active"
            entry["activated_at"] = datetime.now().isoformat(timespec="seconds")
            save_allocations(data)
            print(json.dumps(entry, ensure_ascii=False))
            return
    print('{"error": "not found"}', file=sys.stderr)
    sys.exit(1)


def release(client_ip=None, user_id=None):
    data = load_allocations()
    for entry in data["allocations"]:
        if entry["status"] == "released":
            continue
        ip_ok = client_ip is None or entry["client_ip"] == client_ip
        id_ok = user_id is None or entry["user_id"] == user_id
        if ip_ok and id_ok and (client_ip is not None or user_id is not None):
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
    with open(LOCK_FILE, "w") as lf:
        _acquire_lock(lf, fcntl.LOCK_SH)
        return func(*args, **kwargs)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--client-ip", default=None)
    parser.add_argument("--hostname", default="unknown")
    parser.add_argument("--user-id", type=int, default=None)
    parser.add_argument(
        "--action",
        required=True,
        choices=["allocate", "lookup", "activate", "release", "status"],
    )
    args = parser.parse_args()

    if args.action == "allocate":
        if not args.client_ip:
            print("--client-ip required for allocate", file=sys.stderr)
            sys.exit(1)
        with_lock(allocate, args.client_ip, args.hostname)
    elif args.action == "lookup":
        if not args.client_ip:
            print("--client-ip required for lookup", file=sys.stderr)
            sys.exit(1)
        with_shared_lock(lookup, args.client_ip)
    elif args.action == "activate":
        if not args.client_ip:
            print("--client-ip required for activate", file=sys.stderr)
            sys.exit(1)
        with_lock(activate, args.client_ip)
    elif args.action == "release":
        if not args.client_ip and not args.user_id:
            print("--client-ip or --user-id required", file=sys.stderr)
            sys.exit(1)
        with_lock(release, args.client_ip, args.user_id)
    elif args.action == "status":
        with_shared_lock(status)


if __name__ == "__main__":
    main()
