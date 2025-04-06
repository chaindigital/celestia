#!/bin/bash

# === Установка зависимостей ===
sudo apt update && sudo apt install -y python3 python3-pip python3-venv curl jq

# === Создание директории ===
MAP_DIR="$HOME/celestia-maps"
mkdir -p "$MAP_DIR"
cd "$MAP_DIR"

# === Создание виртуального окружения ===
python3 -m venv .venv
source .venv/bin/activate
pip install --break-system-packages requests tqdm folium

# === Создание generate_maps.py ===
tee "$MAP_DIR/generate_maps.py" > /dev/null << 'EOF'
#!/usr/bin/env python3
import csv
import folium
from folium.plugins import MarkerCluster
import os

DATA_DIR = "/root/peers_data"
OUTPUT_DIR = os.path.dirname(os.path.abspath(__file__))
NETWORKS = ["testnet", "mainnet"]

def load_data(csv_path):
    data = []
    try:
        with open(csv_path, newline='') as f:
            reader = csv.DictReader(f)
            for row in reader:
                try:
                    lat, lon = float(row["lat"]), float(row["lon"])
                    if lat == 0.0 and lon == 0.0:
                        continue
                    data.append({
                        "lat": lat,
                        "lon": lon,
                        "peer_id": row.get("peer_id", ""),
                        "ip": row.get("ip", ""),
                        "city": row.get("city", ""),
                        "country": row.get("country", ""),
                        "org": row.get("org", "")
                    })
                except:
                    continue
        print(f"✅ Загружено {len(data)} точек из {csv_path}")
    except Exception as e:
        print(f"❌ Ошибка загрузки {csv_path}: {e}")
    return data

def generate_map(data, output_file):
    m = folium.Map(tiles="CartoDB dark_matter", zoom_start=2)
    cluster = MarkerCluster().add_to(m)
    for node in data:
        popup = (
            f"<b>Peer ID:</b> {node['peer_id']}<br>"
            f"<b>IP:</b> {node['ip']}<br>"
            f"<b>Country:</b> {node['country']}<br>"
            f"<b>City:</b> {node['city']}<br>"
            f"<b>Org:</b> {node['org']}"
        )
        folium.CircleMarker(
            location=(node["lat"], node["lon"]),
            radius=5,
            fill=True,
            color="cyan",
            fill_opacity=0.7,
            popup=popup
        ).add_to(cluster)
    m.save(output_file)
    print(f"🗺️ Карта сохранена: {output_file}")

def main():
    for net in NETWORKS:
        file = os.path.join(DATA_DIR, f"peers_geo_{net}_latest.csv")
        output_file = os.path.join(OUTPUT_DIR, f"map_{net}.html")
        if os.path.exists(file):
            data = load_data(file)
            if data:
                generate_map(data, output_file)
        else:
            print(f"⚠️ Файл не найден: {file}")

if __name__ == "__main__":
    main()
EOF

# === Скрипт запуска для cron ===
tee "$MAP_DIR/run_maps.sh" > /dev/null << EOF
#!/bin/bash
source "$HOME/celestia-maps/.venv/bin/activate"
"$HOME/celestia-maps/.venv/bin/python3" "$HOME/celestia-maps/generate_maps.py" >> "$HOME/celestia-maps/map_cron.log" 2>&1
EOF

# === Сделать скрипты исполняемыми ===
chmod +x "$MAP_DIR/run_maps.sh"
chmod +x "$MAP_DIR/generate_maps.py"

# === Добавить cron каждые 5 минут ===
( crontab -l 2>/dev/null | grep -v 'run_maps.sh' ; echo "*/5 * * * * /bin/bash $MAP_DIR/run_maps.sh" ) | crontab -

# === Вывод завершения ===
echo ""
echo "✅ Установка завершена. Карты будут автоматически обновляться каждые 5 минут."
echo "👉 Для запуска вручную:"
echo "source ~/celestia-maps/.venv/bin/activate && python3 ~/celestia-maps/generate_maps.py"
echo "👉 Cron-логи: ~/celestia-maps/map_cron.log"
