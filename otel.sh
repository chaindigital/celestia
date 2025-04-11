#!/bin/bash

# === Ввод переменных ===
read -p "Введите IP третьего сервера (REMOTE_IP): " REMOTE_IP
read -s -p "Введите пароль пользователя bridge на третьем сервере (REMOTE_PASS): " REMOTE_PASS
echo

# === Экспорт во временное окружение ===
export REMOTE_IP=$REMOTE_IP
export REMOTE_PASS=$REMOTE_PASS

# === Установка зависимостей ===
apt update && apt install -y python3 python3-pip python3-venv sshpass curl

# === Директория otel_data (единая) ===
mkdir -p /root/otel_data
cd /root/otel_data

# === Виртуальное окружение ===
python3 -m venv .venv
source .venv/bin/activate
pip install requests tqdm

# === Python-скрипт ===
cat > /root/otel_data/fetch_otel_metrics.py << 'EOF'
#!/usr/bin/env python3
import requests, os, subprocess
from datetime import datetime, timezone

ENDPOINTS = {
    "testnet": "https://fdp-mocha.celestia.observer/metrics",
    "mainnet": "https://fdp-lunar.celestia.observer/metrics"
}

REMOTE_USER = "bridge"
REMOTE_IP = os.environ.get("REMOTE_IP")
REMOTE_PASS = os.environ.get("REMOTE_PASS")
REMOTE_DIR = "/home/bridge/otel_data/"
SAVE_DIR = "/root/otel_data"

def log(msg):
    now = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S UTC")
    print(f"[{now}] {msg}")

def fetch_and_send(network, url):
    try:
        log(f"🔄 Получение OTEL метрик для {network}...")
        resp = requests.get(url, timeout=10)
        if resp.status_code != 200:
            log(f"❌ Ошибка {resp.status_code} при запросе {url}")
            return
        filename = f"otel_metrics_{network}_latest.txt"
        path = os.path.join(SAVE_DIR, filename)
        with open(path, "w") as f:
            f.write(resp.text)
        log(f"✅ Сохранено: {filename}")

        log(f"📡 Отправка {filename} на {REMOTE_IP}...")
        scp_cmd = [
            "sshpass", "-p", REMOTE_PASS,
            "scp", "-o", "StrictHostKeyChecking=no",
            "-o", "UserKnownHostsFile=/dev/null",
            path,
            f"{REMOTE_USER}@{REMOTE_IP}:{REMOTE_DIR}"
        ]
        subprocess.run(scp_cmd, check=True)
        log(f"✅ Успешно отправлено: {filename}\\n")
    except Exception as e:
        log(f"❌ Ошибка при обработке {network}: {e}")

def main():
    for net, url in ENDPOINTS.items():
        fetch_and_send(net, url)

if __name__ == "__main__":
    main()
EOF

chmod +x /root/otel_data/fetch_otel_metrics.py

# === Скрипт run_otel.sh для cron с логами ===
cat > /root/otel_data/run_otel.sh << EOF
#!/bin/bash
export REMOTE_IP="$REMOTE_IP"
export REMOTE_PASS="$REMOTE_PASS"
source /root/otel_data/.venv/bin/activate
python3 /root/otel_data/fetch_otel_metrics.py >> /root/otel_data/otel_cron.log 2>&1
EOF

chmod +x /root/otel_data/run_otel.sh

# === Добавить в cron (каждые 5 минут) ===
(crontab -l 2>/dev/null | grep -v 'run_otel.sh'; echo "*/5 * * * * /bin/bash /root/otel_data/run_otel.sh") | crontab -

# === Финальное сообщение ===
echo ""
echo "✅ Установка завершена. Метрики будут отправляться каждые 5 минут."
echo "👉 Для запуска вручную:"
echo "source /root/otel_data/.venv/bin/activate && python3 /root/otel_data/fetch_otel_metrics.py"
echo "👉 Cron-логи: /root/otel_data/otel_cron.log"
echo "👉 Локальные файлы: /root/otel_data/otel_metrics_testnet_latest.txt и otel_metrics_mainnet_latest.txt"
