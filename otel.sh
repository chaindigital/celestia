#!/bin/bash

# === Ввод переменных ===
read -p "Введите IP третьего сервера (REMOTE_IP): " REMOTE_IP
read -s -p "Введите пароль пользователя bridge на третьем сервере (REMOTE_PASS): " REMOTE_PASS
echo

# === Экспорт в окружение для использования в Python ===
echo "export REMOTE_IP=$REMOTE_IP" >> ~/.bashrc
echo "export REMOTE_PASS=$REMOTE_PASS" >> ~/.bashrc
export REMOTE_IP=$REMOTE_IP
export REMOTE_PASS=$REMOTE_PASS

# === Установка зависимостей ===
sudo apt update && sudo apt install -y python3 python3-pip python3-venv curl sshpass

# === Каталоги ===
INSTALL_DIR="/root/celestia-otel"
DATA_DIR="/root/otel_data"
mkdir -p "$INSTALL_DIR" "$DATA_DIR"
cd "$INSTALL_DIR"

# === Виртуальное окружение ===
python3 -m venv .venv
source .venv/bin/activate
pip install --break-system-packages requests

# === Python-скрипт для метрик ===
tee "$INSTALL_DIR/fetch_otel_metrics.py" > /dev/null << 'EOF'
#!/usr/bin/env python3
import os
import requests
import subprocess

ENDPOINTS = {
    "testnet": "https://fdp-mocha.celestia.observer/metrics",
    "mainnet": "https://fdp-lunar.celestia.observer/metrics"
}

REMOTE_USER = "bridge"
REMOTE_IP = os.environ.get("REMOTE_IP")
REMOTE_PASS = os.environ.get("REMOTE_PASS")
REMOTE_DIR = "/home/bridge/otel_data/"
LOCAL_DIR = "/root/otel_data/"

def fetch_and_send(network, url):
    try:
        resp = requests.get(url, timeout=10)
        if resp.status_code != 200:
            print(f"❌ {network}: ошибка {resp.status_code}")
            return

        filename = f"otel_metrics_{network}_latest.txt"
        filepath = os.path.join(LOCAL_DIR, filename)
        with open(filepath, "w") as f:
            f.write(resp.text)
        print(f"✅ {network}: сохранено в {filename}")

        cmd = [
            "sshpass", "-p", REMOTE_PASS,
            "scp", "-o", "StrictHostKeyChecking=no",
            "-o", "UserKnownHostsFile=/dev/null",
            filepath, f"{REMOTE_USER}@{REMOTE_IP}:{REMOTE_DIR}"
        ]
        subprocess.run(cmd, check=True)
        print(f"✅ {network}: отправлено на {REMOTE_IP}")
    except Exception as e:
        print(f"❌ {network}: ошибка — {e}")

def main():
    for net, url in ENDPOINTS.items():
        fetch_and_send(net, url)

if __name__ == "__main__":
    main()
EOF

# === Cron-обёртка ===
tee "$INSTALL_DIR/run_otel.sh" > /dev/null << EOF
#!/bin/bash
source "$INSTALL_DIR/.venv/bin/activate"
python3 "$INSTALL_DIR/fetch_otel_metrics.py" >> "$INSTALL_DIR/otel_cron.log" 2>&1
EOF

chmod +x "$INSTALL_DIR/fetch_otel_metrics.py" "$INSTALL_DIR/run_otel.sh"

# === Добавление в cron каждые 5 минут ===
(crontab -l 2>/dev/null | grep -v 'run_otel.sh'; echo "*/5 * * * * /bin/bash $INSTALL_DIR/run_otel.sh") | crontab -

# === Финальное сообщение ===
echo ""
echo "✅ Установка завершена. Метрики будут отправляться каждые 5 минут."
echo "👉 Для запуска вручную:"
echo "source $INSTALL_DIR/.venv/bin/activate && python3 $INSTALL_DIR/fetch_otel_metrics.py"
echo "👉 Cron-логи: $INSTALL_DIR/otel_cron.log"
echo "👉 Локальные файлы: $DATA_DIR/otel_metrics_testnet_latest.txt и otel_metrics_mainnet_latest.txt"
