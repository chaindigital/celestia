#!/bin/bash

# === Ввод переменных ===
read -p "Введите IP третьего сервера (REMOTE_IP): " REMOTE_IP
read -s -p "Введите пароль root пользователя на третьем сервере (REMOTE_PASS): " REMOTE_PASS
echo

# === Установка зависимостей ===
sudo apt update && sudo apt install -y python3 python3-pip python3-venv jq curl sshpass cron

# === Создание директории и окружения ===
mkdir -p ~/celestia-peers && cd ~/celestia-peers
python3 -m venv .venv
source .venv/bin/activate
pip install requests tqdm

# === Создание скрипта ===
sudo tee collect_and_send_peers.py > /dev/null << EOF
#!/usr/bin/env python3
import subprocess, json, requests, csv, time, shutil, os
from tqdm import tqdm
from datetime import datetime

NETWORK_TAG = "testnet"
REMOTE_USER = "root"
REMOTE_IP = "${REMOTE_IP}"
REMOTE_PASS = "${REMOTE_PASS}"
REMOTE_DIR = "/root/peers_data/"

def get_peers():
    try:
        result = subprocess.run(["celestia", "p2p", "peers"], capture_output=True, text=True, check=True)
        data = json.loads(result.stdout)
        return data.get("result", {}).get("peers", [])
    except: return []

def get_ip(peer_id):
    try:
        result = subprocess.run(["celestia", "p2p", "peer-info", peer_id], capture_output=True, text=True, check=True)
        addresses = json.loads(result.stdout).get("result", {}).get("peer_addr", [])
        for addr in addresses:
            if "/ip4/" in addr:
                return addr.split("/ip4/")[1].split("/")[0]
    except: return None

def get_geodata(ip):
    try:
        r = requests.get(f"https://ipinfo.io/{ip}/json", timeout=5)
        return r.json() if r.status_code == 200 else None
    except: return None

def save_csv(data):
    ts = datetime.now().strftime("%Y%m%d_%H%M%S")
    f1 = f"peers_geo_{NETWORK_TAG}_${ts}.csv"
    f2 = f"peers_geo_{NETWORK_TAG}_latest.csv"
    with open(f1, "w", newline="") as f:
        w = csv.writer(f, quoting=csv.QUOTE_ALL)
        w.writerow(["peer_id", "ip", "city", "region", "country", "lat", "lon", "org"])
        for row in data:
            lat, lon = row.get("loc", "0.0,0.0").split(",") if "," in row.get("loc", "") else ("0.0", "0.0")
            w.writerow([
                row.get("peer_id", ""),
                row.get("ip", ""),
                row.get("city", ""),
                row.get("region", ""),
                row.get("country", ""),
                lat, lon,
                row.get("org", "")
            ])
    shutil.copyfile(f1, f2)
    print(f"✅ Файл {f1} сохранён")
    return [f1, f2]

def send_scp(file):
    print(f"📡 Отправка {file} на {REMOTE_IP}...")
    cmd = [
        "sshpass", "-p", REMOTE_PASS, "scp",
        "-o", "StrictHostKeyChecking=no",
        "-o", "UserKnownHostsFile=/dev/null",
        file,
        f"{REMOTE_USER}@{REMOTE_IP}:{REMOTE_DIR}"
    ]
    return subprocess.run(cmd).returncode == 0

def main():
    peers = get_peers()
    if not peers: return
    data = []
    for pid in tqdm(peers, desc="Обработка пиров"):
        ip = get_ip(pid)
        if not ip: continue
        geo = get_geodata(ip)
        if not geo: continue
        geo["peer_id"], geo["ip"] = pid, ip
        data.append(geo)
        time.sleep(0.3)
    if not data: return
    files = save_csv(data)
    for f in files:
        if send_scp(f):
            os.remove(f)
            print(f"🧹 Удалён локально: {f}")

if __name__ == "__main__":
    main()
EOF

# === Делаем скрипт исполняемым ===
sudo chmod +x collect_and_send_peers.py

# === Добавляем cron задачу на каждые 5 минут ===
(crontab -l 2>/dev/null; echo "*/5 * * * * cd ~/celestia-peers && source .venv/bin/activate && python3 collect_and_send_peers.py") | crontab -

echo "✅ Установка завершена. Сбор пиров будет запускаться каждые 5 минут."
echo "👉 Для запуска вручную:"
echo "source ~/celestia-peers/.venv/bin/activate && python3 ~/celestia-peers/collect_and_send_peers.py"
