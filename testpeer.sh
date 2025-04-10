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
REMOTE_DIR = "/root/peers_data/"
REMOTE_PASS = "$REMOTE_PASS"
CACHE_FILE = "geo_cache.json"

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
        with open(CACHE_FILE, "r") as f:
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
    print(f"✅ Сохранено: {latest}")
    return latest

def send_to_remote(file):
    print(f"📡 Отправка {file} на {REMOTE_IP}...")
    cmd = [
        "sshpass", "-p", REMOTE_PASS, "scp",
        "-o", "StrictHostKeyChecking=no",
        "-o", "UserKnownHostsFile=/dev/null",
        file, f"{REMOTE_USER}@{REMOTE_IP}:{REMOTE_DIR}"
    ]
    try:
        subprocess.run(cmd, check=True)
        print("✅ Отправлено")
    except subprocess.CalledProcessError as e:
        print(f"❌ Ошибка SCP: {e}")

def main():
    peers = get_peers()
    if not peers:
        print("❌ Пиры не найдены")
        return

    cache = load_cache()
    new_data = []

    for peer_id in tqdm(peers, desc="Пиры"):
        ip = get_ip(peer_id)
        if not ip:
            continue
        # если peer_id есть и ip не изменился — берём старое
        if peer_id in cache and cache[peer_id].get("ip") == ip:
            geo = cache[peer_id]
        else:
            geo = get_geodata(ip)
            if not geo:
                continue
            geo["peer_id"] = peer_id
            geo["ip"] = ip
            cache[peer_id] = geo
        new_data.append(geo)
        time.sleep(0.3)

    if not new_data:
        print("❌ Нет новых данных")
        return

    save_cache(cache)
    file = save_to_csv(new_data)
    send_to_remote(file)

if __name__ == "__main__":
    main()
EOF

# === Разрешения ===
chmod +x collect_and_send_peers.py

# === Крон с логом ===
(crontab -l 2>/dev/null | grep -v 'collect_and_send_peers.py' ; echo "*/15 * * * * cd \$HOME/celestia-peers && \$HOME/celestia-peers/.venv/bin/python3 collect_and_send_peers.py >> \$HOME/celestia-peers/peers_cron.log 2>&1") | crontab -

echo ""
echo "✅ Установка завершена. Сбор пиров и геоданных каждые 15 минут."
echo "👉 Для запуска вручную:"
echo "source ~/celestia-peers/.venv/bin/activate && python3 ~/celestia-peers/collect_and_send_peers.py"
echo "👉 Логи: ~/celestia-peers/peers_cron.log"
