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
import json
import os
import sys
from datetime import datetime

ALLOCATIONS_FILE = os.environ.get(
    "ALLOCATIONS_FILE", "/opt/training/allocations.json"
)


def load_allocations():
    if os.path.exists(ALLOCATIONS_FILE):
        with open(ALLOCATIONS_FILE) as f:
            return json.load(f)
    return {"allocations": []}


def save_allocations(data):
    os.makedirs(os.path.dirname(ALLOCATIONS_FILE), exist_ok=True)
    with open(ALLOCATIONS_FILE, "w") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)


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
        if entry["client_ip"] == client_ip:
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
        match = False
        if client_ip and entry["client_ip"] == client_ip:
            match = True
        if user_id and entry["user_id"] == user_id:
            match = True
        if match and entry["status"] != "released":
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
        allocate(args.client_ip, args.hostname)
    elif args.action == "lookup":
        if not args.client_ip:
            print("--client-ip required for lookup", file=sys.stderr)
            sys.exit(1)
        lookup(args.client_ip)
    elif args.action == "activate":
        if not args.client_ip:
            print("--client-ip required for activate", file=sys.stderr)
            sys.exit(1)
        activate(args.client_ip)
    elif args.action == "release":
        if not args.client_ip and not args.user_id:
            print("--client-ip or --user-id required", file=sys.stderr)
            sys.exit(1)
        release(args.client_ip, args.user_id)
    elif args.action == "status":
        status()


if __name__ == "__main__":
    main()
