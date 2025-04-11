#!/bin/bash

# === Ввод переменных ===
read -p "Введите IP третьего сервера (REMOTE_IP): " REMOTE_IP
read -s -p "Введите пароль пользователя bridge на третьем сервере (REMOTE_PASS): " REMOTE_PASS
echo

# === Установка зависимостей ===
sudo apt update && sudo apt install -y python3 python3-pip python3-venv curl sshpass

# === Константы ===
REMOTE_USER="bridge"
REMOTE_DIR="/home/bridge/otel_data"
SAVE_DIR="$HOME/otel_data"
SCRIPT_DIR="$HOME/celestia-otel"
VENV_DIR="$SCRIPT_DIR/.venv"

# === Создание директорий ===
mkdir -p "$SAVE_DIR"
mkdir -p "$SCRIPT_DIR"
cd "$SCRIPT_DIR"

# === Виртуальное окружение ===
python3 -m venv .venv
source .venv/bin/activate
pip install --break-system-packages requests

# === Python-скрипт ===
tee "$SCRIPT_DIR/fetch_otel_metrics.py" > /dev/null << EOF
#!/usr/bin/env python3
import requests
import subprocess
import os

ENDPOINTS = {
    "testnet": "https://fdp-mocha.celestia.observer/metrics",
    "mainnet": "https://fdp-lunar.celestia.observer/metrics"
}

REMOTE_USER = "$REMOTE_USER"
REMOTE_IP = "$REMOTE_IP"
REMOTE_PASS = "$REMOTE_PASS"
REMOTE_DIR = "$REMOTE_DIR"
SAVE_DIR = "$SAVE_DIR"

def fetch_and_send(network, url):
    try:
        print(f"🔄 Получение OTEL метрик для {network}...")
        resp = requests.get(url, timeout=10)
        if resp.status_code != 200:
            print(f"❌ Ошибка {resp.status_code} при запросе {url}")
            return
        filename = f"otel_metrics_{network}_latest.txt"
        filepath = os.path.join(SAVE_DIR, filename)

        with open(filepath, "w") as f:
            f.write(resp.text)
        print(f"✅ Сохранено: {filename}")

        print(f"📡 Отправка {filename} на {REMOTE_IP}...")
        subprocess.run([
            "sshpass", "-p", REMOTE_PASS,
            "scp", "-o", "StrictHostKeyChecking=no",
            "-o", "UserKnownHostsFile=/dev/null",
            filepath,
            f"{REMOTE_USER}@{REMOTE_IP}:{REMOTE_DIR}/"
        ], check=True)
        print(f"✅ Успешно отправлено: {filename}\n")
    except Exception as e:
        print(f"❌ Ошибка: {e}")

def main():
    for net, url in ENDPOINTS.items():
        fetch_and_send(net, url)

if __name__ == "__main__":
    main()
EOF

# === Обёртка для cron ===
tee "$SCRIPT_DIR/run_otel.sh" > /dev/null << EOF
#!/bin/bash
source "$VENV_DIR/bin/activate"
python3 "$SCRIPT_DIR/fetch_otel_metrics.py" >> "$SCRIPT_DIR/otel_cron.log" 2>&1
EOF

# === Права на выполнение ===
chmod +x "$SCRIPT_DIR/fetch_otel_metrics.py"
chmod +x "$SCRIPT_DIR/run_otel.sh"

# === Cron каждые 5 минут ===
( crontab -l 2>/dev/null | grep -v "run_otel.sh" ; echo "*/5 * * * * /bin/bash $SCRIPT_DIR/run_otel.sh" ) | crontab -

# === Финальный вывод ===
echo ""
echo "✅ Установка завершена. Метрики будут отправляться каждые 5 минут."
echo "👉 Для запуска вручную:"
echo "source $VENV_DIR/bin/activate && python3 $SCRIPT_DIR/fetch_otel_metrics.py"
echo "👉 Cron-логи: $SCRIPT_DIR/otel_cron.log"
echo "👉 Локальные файлы: $SAVE_DIR/otel_metrics_testnet_latest.txt и otel_metrics_mainnet_latest.txt"
