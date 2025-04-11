#!/bin/bash

# === Ввод переменных ===
read -p "Введите IP третьего сервера (REMOTE_IP): " REMOTE_IP
read -s -p "Введите пароль root пользователя на третьем сервере (REMOTE_PASS): " REMOTE_PASS
echo

# === Установка зависимостей ===
sudo apt update && sudo apt install -y python3 python3-pip python3-venv jq curl sshpass

# === Создание директории и окружения ===
mkdir -p ~/celestia-peers && cd ~/celestia-peers
python3 -m venv .venv
source .venv/bin/activate
pip install --break-system-packages requests tqdm

# === Создание Python-скрипта ===
tee collect_and_send_peers_mainnet.py > /dev/null << EOF
#!/usr/bin/env python3
import subprocess, json, requests, csv, time, shutil, os
from tqdm import tqdm
from datetime import datetime, timezone

NETWORK_TAG = "mainnet"
REMOTE_USER = "root"
REMOTE_IP = "$REMOTE_IP"
REMOTE_PASS = "$REMOTE_PASS"
REMOTE_DIR = "/root/peers_data/"
CACHE_FILE = f"peer_cache_{NETWORK_TAG}.json"
BACKUP_FILE = f"peer_cache_{NETWORK_TAG}_backup.json"
CSV_FILE = f"peers_geo_{NETWORK_TAG}_latest.csv"
LOG_FILE = f"peers_cron_{NETWORK_TAG}.log"
IPINFO_TOKEN = "3fd7f871c70454"

def log(msg):
    now = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S UTC")
    with open(LOG_FILE, "a") as f:
        f.write(f"[{now}] {msg}\\n")
    print(f"[{now}] {msg}")

def get_peers():
    try:
        result = subprocess.run(["celestia", "p2p", "peers"], capture_output=True, text=True, check=True)
        data = json.loads(result.stdout)
        return data.get("result", {}).get("peers", [])
    except:
        return []

def get_ip(peer_id):
    try:
        result = subprocess.run(["celestia", "p2p", "peer-info", peer_id], capture_output=True, text=True, check=True)
        data = json.loads(result.stdout)
        for addr in data.get("result", {}).get("peer_addr", []):
            if "/ip4/" in addr:
                return addr.split("/ip4/")[1].split("/")[0]
    except:
        return None

def get_geodata(ip):
    try:
        resp = requests.get(f"https://ipinfo.io/{ip}/json?token={IPINFO_TOKEN}", timeout=5)
        if resp.status_code == 200:
            return resp.json()
    except:
        pass
    return None

def load_cache():
    if os.path.exists(CACHE_FILE):
        with open(CACHE_FILE) as f:
            return json.load(f)
    return {}

def save_cache(cache):
    with open(CACHE_FILE, "w") as f:
        json.dump(cache, f)
    shutil.copyfile(CACHE_FILE, BACKUP_FILE)

def save_to_csv(data):
    with open(CSV_FILE, "w", newline="") as f:
        writer = csv.writer(f, quoting=csv.QUOTE_ALL)
        writer.writerow(["peer_id", "ip", "city", "region", "country", "lat", "lon", "org"])
        for row in data:
            loc = row.get("loc", "0.0,0.0")
            lat, lon = loc.split(",") if "," in loc else ("0.0", "0.0")
            writer.writerow([
                row.get("peer_id", ""),
                row.get("ip", ""),
                row.get("city", ""),
                row.get("region", ""),
                row.get("country", ""),
                lat,
                lon,
                row.get("org", "")
            ])
    log(f"✅ Сохранено: {CSV_FILE}")
    return CSV_FILE

def send_to_remote(file):
    log(f"📡 Отправка {file} на {REMOTE_IP}...")
    cmd = [
        "sshpass", "-p", REMOTE_PASS,
        "scp", "-o", "StrictHostKeyChecking=no",
        "-o", "UserKnownHostsFile=/dev/null",
        file, f"{REMOTE_USER}@{REMOTE_IP}:{REMOTE_DIR}"
    ]
    try:
        subprocess.run(cmd, check=True)
        log(f"✅ Отправлено: {file}")
    except subprocess.CalledProcessError as e:
        log(f"❌ Ошибка отправки: {e}")

def main():
    log("🚀 Старт сбора пиров")
    peers = get_peers()
    if not peers:
        log("❌ Пиры не найдены.")
        return

    cache = load_cache()
    new_cache = {}
    result = []

    for pid in tqdm(peers, desc="Пиры"):
        ip = get_ip(pid)
        if not ip:
            continue
        geo = {}
        if pid in cache and cache[pid]["ip"] == ip and all(cache[pid].get(k) for k in ["city", "region", "country", "org", "loc"]):
            geo = cache[pid]
        else:
            geo = get_geodata(ip) or {}
        geo["peer_id"], geo["ip"] = pid, ip
        geo["updated_at"] = datetime.now(timezone.utc).isoformat()
        new_cache[pid] = geo
        result.append(geo)
        time.sleep(0.3)

    if not result:
        log("ℹ️ Нет данных для CSV, но кэш обновлён.")
    else:
        file = save_to_csv(result)
        send_to_remote(file)

    save_cache(new_cache)
    log("✅ Завершено")

if __name__ == "__main__":
    main()
EOF

# === Разрешения на выполнение ===
chmod +x collect_and_send_peers_mainnet.py

# === Крон каждые 5 минут ===
(crontab -l 2>/dev/null; echo "*/5 * * * * cd \$HOME/celestia-peers && \$HOME/celestia-peers/.venv/bin/python3 collect_and_send_peers_mainnet.py") | crontab -

echo ""
echo "✅ Установка завершена. Скрипт будет запускаться каждые 5 минут."
echo "👉 Для запуска вручную:"
echo "source ~/celestia-peers/.venv/bin/activate && python3 collect_and_send_peers_mainnet.py"
echo "👉 Логи:  ~/celestia-peers/peers_cron_mainnet.log"
echo "👉 Кеш:   ~/celestia-peers/peer_cache_mainnet.json"
echo "👉 Бэкап: ~/celestia-peers/peer_cache_mainnet_backup.json"
echo "👉 CSV:   ~/celestia-peers/peers_geo_mainnet_latest.csv"
