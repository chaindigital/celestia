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
tee collect_and_send_peers.py > /dev/null << EOF
#!/usr/bin/env python3
import subprocess, json, requests, csv, time, shutil, os
from tqdm import tqdm
from datetime import datetime

NETWORK_TAG = "testnet"
REMOTE_USER = "root"
REMOTE_IP = "$REMOTE_IP"
REMOTE_PASS = "$REMOTE_PASS"
REMOTE_DIR = "/root/peers_data/"
CACHE_FILE = "peer_cache_testnet.json"
LOG_FILE = "peers_cron.log"

def log(msg):
    now = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    with open(LOG_FILE, "a") as f:
        f.write(f"[{now}] {msg}\n")
    print(f"[{now}] {msg}")

def get_peers():
    try:
        result = subprocess.run(["celestia", "p2p", "peers"], capture_output=True, text=True, check=True)
        data = json.loads(result.stdout)
        return data.get("result", {}).get("peers", [])
    except: return []

def get_ip(peer_id):
    try:
        result = subprocess.run(["celestia", "p2p", "peer-info", peer_id], capture_output=True, text=True, check=True)
        data = json.loads(result.stdout)
        for addr in data.get("result", {}).get("peer_addr", []):
            if "/ip4/" in addr:
                return addr.split("/ip4/")[1].split("/")[0]
    except: return None

def get_geodata(ip):
    try:
        resp = requests.get(f"https://ipinfo.io/{ip}/json", timeout=5)
        return resp.json() if resp.status_code == 200 else None
    except: return None

def load_cache():
    if os.path.exists(CACHE_FILE):
        with open(CACHE_FILE) as f:
            return json.load(f)
    return {}

def save_cache(cache):
    with open(CACHE_FILE, "w") as f:
        json.dump(cache, f)

def save_to_csv(data):
    latest = f"peers_geo_{NETWORK_TAG}_latest.csv"
    with open(latest, "w", newline="") as f:
        w = csv.writer(f, quoting=csv.QUOTE_ALL)
        w.writerow(["peer_id", "ip", "city", "region", "country", "lat", "lon", "org"])
        for row in data:
            lat, lon = row.get("loc", "0.0,0.0").split(",")
            w.writerow([
                row.get("peer_id", ""),
                row.get("ip", ""),
                row.get("city", ""),
                row.get("region", ""),
                row.get("country", ""),
                lat,
                lon,
                row.get("org", "")
            ])
    log(f"✅ Сохранено: {latest}")
    return latest

def send_to_remote(file):
    log(f"📡 Отправка {file} на {REMOTE_IP}...")
    cmd = ["sshpass", "-p", REMOTE_PASS, "scp", "-o", "StrictHostKeyChecking=no",
           "-o", "UserKnownHostsFile=/dev/null", file, f"{REMOTE_USER}@{REMOTE_IP}:{REMOTE_DIR}"]
    try:
        subprocess.run(cmd, check=True)
        os.remove(file)
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
        if not ip: continue
        new_cache[pid] = ip

        # Если peer_id и IP не изменились — используем старое значение
        if pid in cache and cache[pid] == ip:
            continue

        geo = get_geodata(ip)
        if not geo: continue
        geo["peer_id"], geo["ip"] = pid, ip
        result.append(geo)
        time.sleep(0.3)

    if not result:
        log("ℹ️ Нет новых или изменённых пиров для сохранения.")
    else:
        file = save_to_csv(result)
        send_to_remote(file)

    save_cache(new_cache)
    log("✅ Завершено")

if __name__ == "__main__":
    main()
EOF

# === Права на выполнение ===
chmod +x collect_and_send_peers.py

# === Cron на каждые 20 минут (рекомендуется) ===
(crontab -l 2>/dev/null; echo "*/20 * * * * cd \$HOME/celestia-peers && \$HOME/celestia-peers/.venv/bin/python3 collect_and_send_peers.py") | crontab -

echo ""
echo "✅ Установка завершена. Скрипт будет запускаться каждые 20 минут."
echo "👉 Для запуска вручную:"
echo "source ~/celestia-peers/.venv/bin/activate && python3 ~/celestia-peers/collect_and_send_peers.py"
echo "👉 Логи: ~/celestia-peers/peers_cron.log"
