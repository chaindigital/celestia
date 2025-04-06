#!/bin/bash

# === Установка зависимостей ===
sudo apt update && sudo apt install -y python3 python3-pip python3-venv curl jq

# === Создание директории ===
mkdir -p ~/celestia-maps && cd ~/celestia-maps

# === Виртуальное окружение ===
python3 -m venv .venv
source .venv/bin/activate
pip install folium tqdm

# === Создание скрипта ===
sudo tee generate_maps.py > /dev/null << 'EOF'
#!/usr/bin/env python3
import csv
import folium
import os
from folium.plugins import MarkerCluster

def load_csv(filepath):
    data = []
    if not os.path.exists(filepath):
        print(f"[!] Файл не найден: {filepath}")
        return data
    with open(filepath, newline='') as f:
        reader = csv.DictReader(f)
        for row in reader:
            try:
                lat = float(row["lat"])
                lon = float(row["lon"])
                if lat == 0.0 and lon == 0.0:
                    continue
                data.append({
                    "lat": lat,
                    "lon": lon,
                    "peer_id": row["peer_id"],
                    "ip": row["ip"],
                    "city": row["city"],
                    "country": row["country"],
                    "org": row["org"]
                })
            except Exception as e:
                print(f"⚠️ Ошибка в строке CSV: {e}")
    print(f"✅ Загружено {len(data)} точек из {filepath}")
    return data

def generate_map(data, output_file):
    if not data:
        print(f"❌ Нет данных для генерации карты {output_file}")
        return
    m = folium.Map(tiles="CartoDB dark_matter", zoom_start=2)
    marker_cluster = MarkerCluster().add_to(m)
    for item in data:
        folium.CircleMarker(
            location=[item["lat"], item["lon"]],
            radius=5,
            fill=True,
            color="cyan",
            fill_opacity=0.7,
            popup=(
                f"<b>Peer ID:</b> {item['peer_id']}<br>"
                f"<b>IP:</b> {item['ip']}<br>"
                f"<b>Country:</b> {item['country']}<br>"
                f"<b>City:</b> {item['city']}<br>"
                f"<b>Org:</b> {item['org']}"
            )
        ).add_to(marker_cluster)
    m.save(output_file)
    print(f"🗺️ Карта сохранена: {output_file}")

def main():
    base_dir = "/root/peers_data"
    testnet_csv = os.path.join(base_dir, "peers_geo_testnet_latest.csv")
    mainnet_csv = os.path.join(base_dir, "peers_geo_mainnet_latest.csv")
    testnet_data = load_csv(testnet_csv)
    mainnet_data = load_csv(mainnet_csv)
    generate_map(testnet_data, "map_testnet.html")
    generate_map(mainnet_data, "map_mainnet.html")

if __name__ == "__main__":
    main()
EOF

# === Cron каждые 5 минут ===
(crontab -l 2>/dev/null; echo "*/5 * * * * source \$HOME/celestia-maps/.venv/bin/activate && python3 \$HOME/celestia-maps/generate_maps.py >> \$HOME/celestia-maps/map_cron.log 2>&1") | crontab -

# === Вывод напоминания ===
echo "✅ Установка завершена. Карты будут автоматически обновляться каждые 5 минут."
echo "👉 Для запуска вручную:"
echo "source ~/celestia-maps/.venv/bin/activate && python3 ~/celestia-maps/generate_maps.py"
echo "👉 Cron-логи: ~/celestia-maps/map_cron.log"
