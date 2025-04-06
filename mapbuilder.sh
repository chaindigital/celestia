#!/bin/bash

# === Установка зависимостей ===
sudo apt update && sudo apt install -y python3 python3-pip python3-venv curl jq

# === Создание рабочей директории и окружения ===
mkdir -p ~/celestia-maps && cd ~/celestia-maps
python3 -m venv .venv
source .venv/bin/activate
pip install requests folium tqdm

# === Создание скрипта генерации карты ===
tee generate_maps.py > /dev/null << 'EOF'
#!/usr/bin/env python3
import csv, folium, os
from folium.plugins import MarkerCluster

DATA_DIR = "/root/peers_data"

def load_csv(path):
    try:
        with open(path, newline='') as f:
            return [row for row in csv.DictReader(f) if row.get("lat") and row.get("lon") and float(row["lat"]) and float(row["lon"])]
    except FileNotFoundError:
        print(f"❌ Не найден: {path}")
        return []

def generate_map(rows, out_file):
    m = folium.Map(tiles="CartoDB dark_matter", zoom_start=2)
    cluster = MarkerCluster().add_to(m)
    for r in rows:
        lat, lon = float(r["lat"]), float(r["lon"])
        popup = f"<b>Peer ID:</b> {r['peer_id']}<br><b>IP:</b> {r['ip']}<br><b>Country:</b> {r['country']}<br><b>City:</b> {r['city']}<br><b>Org:</b> {r['org']}"
        folium.CircleMarker(location=(lat, lon), radius=5, fill=True, color="cyan", fill_opacity=0.7, popup=popup).add_to(cluster)
    m.save(out_file)
    print(f"🗺️  Карта сохранена: {out_file}")

def main():
    for net in ["testnet", "mainnet"]:
        f = os.path.join(DATA_DIR, f"peers_geo_{net}_latest.csv")
        out = f"peers_map_{net}.html"
        if os.path.exists(f):
            generate_map(load_csv(f), out)
        else:
            print(f"⚠️ Нет файла {f}")

if __name__ == "__main__":
    main()
EOF

# === Права на исполнение ===
chmod +x generate_maps.py

# === Добавление cron задачи ===
(crontab -l 2>/dev/null; echo "*/5 * * * * source \$HOME/celestia-maps/.venv/bin/activate && python3 \$HOME/celestia-maps/generate_maps.py") | crontab -

echo "✅ Установка завершена. Карты будут автоматически обновляться каждые 5 минут."
echo "👉 Для запуска вручную:"
echo "source ~/celestia-maps/.venv/bin/activate && python3 ~/celestia-maps/generate_maps.py"
