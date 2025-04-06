#!/bin/bash

echo "🚀 Установка окружения для Celestia Testnet Peers"

# 👉 Запрашиваем IP и пароль
read -p "Введите IP сервера-приемника: " REMOTE_IP
read -s -p "Введите пароль для SCP: " REMOTE_PASS
echo ""

# Обновление системы и установка зависимостей
sudo apt update && sudo apt install -y python3 python3-pip python3-venv curl jq sshpass

# Создание директории
mkdir -p ~/celestia-peers && cd ~/celestia-peers

# Виртуальное окружение
python3 -m venv .venv
source .venv/bin/activate
pip install requests tqdm

# Создание Python-скрипта с передачей переменных
sudo tee collect_and_send_peers.py > /dev/null << EOF
#!/usr/bin/env python3
import subprocess
import json
import requests
import csv
import time
import os
from tqdm import tqdm
from datetime import datetime
import shutil

# === Настройки ===
NETWORK_TAG = "testnet"
REMOTE_USER = "root"
REMOTE_IP = "${REMOTE_IP}"
REMOTE_DIR = "/root/peers_data/"
REMOTE_PASS = "${REMOTE_PASS}"

def get_peers():
    try:
        result = subprocess.run(["celestia", "p2p", "peers"], capture_output=True, text=True, check=True)
        data = json.loads(result.stdout)
        peers = data.get("result", {}).get("peers", [])
        print(f"🔍 Найдено пиров: {len(peers)}")
        return peers
    except subprocess.CalledProcessError as e:
        print(f"[!] Ошибка при получении пиров: {e}")
        return []

def get_ip(peer_id):
    try:
        result = subprocess.run(["celestia", "p2p", "peer-info", peer_id], capture_output=True, text=True, check=True)
        data = json.loads(result.stdout)
        addresses = data.get("result", {}).get("peer_addr", [])
        for addr in addresses:
            if "/ip4/" in addr:
                ip = addr.split("/ip4/")[1].split("/")[0]
                return ip
    except:
        pass
    return None

def get_geodata(ip):
    try:
        resp = requests.get(f"https://ipinfo.io/{ip}/json", timeout=5)
        if resp.status_code == 200:
            return resp.json()
    except:
        pass
    return None

def save_to_csv(data):
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    filename = f"peers_geo_{NETWORK_TAG}_${timestamp}.csv"
    latest_filename = f"peers_geo_{NETWORK_TAG}_latest.csv"
    with open(filename, "w", newline="") as f:
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
    shutil.copyfile(filename, latest_filename)
    print(f"✅ Файл {filename} сохранён")
    return filename

def send_to_remote(file):
    print(f"📡 Отправка {file} на {REMOTE_IP}...")
    scp_cmd = [
        "sshpass", "-p", REMOTE_PASS,
        "scp",
        "-o", "StrictHostKeyChecking=no",
        "-o", "UserKnownHostsFile=/dev/null",
        file,
        f"{REMOTE_USER}@{REMOTE_IP}:{REMOTE_DIR}"
    ]
    try:
        subprocess.run(scp_cmd, check=True)
        print("✅ Файл отправлен успешно")
    except subprocess.CalledProcessError as e:
        print(f"❌ Ошибка отправки файла: {e}")

def main():
    peers = get_peers()
    if not peers:
        print("❌ Пиры не найдены.")
        return
    all_data = []
    for peer_id in tqdm(peers, desc="Обработка пиров"):
        ip = get_ip(peer_id)
        if not ip:
            print(f"⚠️  IP не найден для {peer_id}")
            continue
        geo = get_geodata(ip)
        if not geo:
            continue
        geo["peer_id"] = peer_id
        geo["ip"] = ip
        all_data.append(geo)
        time.sleep(0.3)
    if not all_data:
        print("❌ Нет данных для сохранения")
        return
    filename = save_to_csv(all_data)
    send_to_remote(filename)

if __name__ == "__main__":
    main()
EOF

# Разрешаем исполнение
chmod +x collect_and_send_peers.py

# Финальный вывод
echo ""
echo "✅ Установка завершена. Запусти сбор пиров вручную:"
echo "source ~/celestia-peers/.venv/bin/activate && python3 ~/celestia-peers/collect_and_send_peers.py"
