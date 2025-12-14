import json
import csv
import numpy as np
from sklearn.cluster import DBSCAN
from shapely.geometry import MultiPoint, mapping
from geojson import Feature, FeatureCollection, Polygon

def load_accidents(filepath):
    """載入事故資料（支援 CSV 和 JSON）"""
    print(f" 讁取事故資料: {filepath}")
    
    if filepath.endswith('.csv'):
        accidents = []
        with open(filepath, "r", encoding="utf-8") as f:
            reader = csv.DictReader(f)
            for row in reader:
                accidents.append({
                    "accident_type": row["Accident_type"],
                    "latitude": row["Latitude"],
                    "longitude": row["Longitude"],
                    "date": row["Date"],
                    "time": row["Time"],
                    "location": row.get("Road", ""),
                    "county": row.get("County", "")
                })
    else:
        with open(filepath, "r", encoding="utf-8") as f:
            accidents = json.load(f)
    
    print(f"共載入 {len(accidents)} 筆資料")
    return accidents

def filter_valid_accidents(accidents):
    """過濾有效資料（有經緯度 + A1/A2）"""
    points = []
    raw_data = []
    
    for a in accidents:
        # 只取 A1（死亡）和 A2（受傷）事故
        if a.get("accident_type") not in ["A1", "A2"]:
            continue
            
        # 確保有有效的經緯度
        try:
            lat = float(a["latitude"])
            lon = float(a["longitude"])
            
            # 基本範圍檢查（桃園市範圍）
            if not (24.8 <= lat <= 25.2 and 121.0 <= lon <= 121.5):
                continue
                
            points.append([lat, lon])
            raw_data.append(a)
        except (ValueError, KeyError, TypeError):
            continue
    
    points = np.array(points)
    print(f"過濾後有效資料: {len(points)} 筆")
    
    return points, raw_data

def cluster_accidents(points, eps=0.01, min_samples=2):
    """使用 DBSCAN 進行空間聚類"""
    print(f"\n 開始 DBSCAN 聚類...")
    print(f"   參數: eps={eps} (~{int(eps * 111000)}m), min_samples={min_samples}")
    
    db = DBSCAN(
        eps=eps,           # 約 1100 公尺（1 度 ≈ 111 公里）
        min_samples=min_samples,  # 至少 2 件事故才算熱區
        metric='euclidean'
    )
    
    labels = db.fit_predict(points)
    
    # 統計結果
    n_clusters = len(set(labels)) - (1 if -1 in labels else 0)
    n_noise = list(labels).count(-1)
    
    print(f"聚類完成:")
    print(f"   找到 {n_clusters} 個事故熱區")
    print(f"   雜訊點（零星事故）: {n_noise} 個")
    
    return labels

def create_hotzone_polygons(points, labels, raw_data):
    """將聚類結果轉換為多邊形（使用固定半徑的多邊形緩衝區）"""
    print(f"\n🗺️  建立熱區多邊形...")
    
    zones = []
    buffer_radius = 0.0025  # 約 278 公尺半徑（固定大小）
    
    for label in set(labels):
        if label == -1:  # 跳過雜訊
            continue
        
        # 取得該群的所有點
        cluster_points = points[labels == label]
        cluster_data = [raw_data[i] for i, l in enumerate(labels) if l == label]
        
        # 計算該群的統計資訊
        a1_count = sum(1 for d in cluster_data if d.get("accident_type") == "A1")
        a2_count = sum(1 for d in cluster_data if d.get("accident_type") == "A2")
        
        # 計算聚類中心點
        center_lat = cluster_points[:, 0].mean()
        center_lon = cluster_points[:, 1].mean()
        
        from shapely.geometry import Point
        center_point = Point(center_lat, center_lon)
        polygon = center_point.buffer(buffer_radius, resolution=6)  # resolution=8 產生八邊形
        
        zones.append({
            "label": label,
            "geometry": polygon,
            "count": len(cluster_points),
            "a1_count": a1_count,
            "a2_count": a2_count,
            "accidents": cluster_data
        })
        
        print(f"   群 {label}: {len(cluster_points)} 件事故 (A1: {a1_count}, A2: {a2_count})")
    
    return zones

def zones_to_geojson(zones):
    """轉換為 GeoJSON 格式"""
    print(f"\n 轉換為 GeoJSON...")
    
    features = []
    
    for i, zone in enumerate(zones):
        coords = list(zone["geometry"].exterior.coords)
        geojson_coords = [[lon, lat] for lat, lon in coords]
        
        # 決定風險等級
        if zone["count"] >= 2000 or zone["a1_count"] >= 100:
            risk_level = "high"
            color = "#FF0000"  # 紅色
        elif zone["count"] >= 300 or zone["a1_count"] >= 30:
            risk_level = "medium"
            color = "#FFA500"  # 橙色
        else:
            risk_level = "low"
            color = "#FFFF00"  # 黃色
        
        # 建立 Feature
        feature = Feature(
            geometry=Polygon([geojson_coords]),
            properties={
                "id": f"accident_zone_{i}",
                "name": f"事故熱區 #{i+1}",
                "riskLevel": risk_level,
                "color": color,
                "accidentCount": zone["count"],
                "a1Count": zone["a1_count"],  # 死亡事故數
                "a2Count": zone["a2_count"],  # 受傷事故數
                "accidentType": ["A1", "A2"],
                "description": f"此區域發生 {zone['count']} 件交通事故（死亡 {zone['a1_count']} 件，受傷 {zone['a2_count']} 件）",
                "category": "traffic_accident"
            }
        )
        
        features.append(feature)
    
    geojson = FeatureCollection(features)
    
    print(f"已建立 {len(features)} 個熱區 Feature")
    
    return geojson

def save_geojson(geojson, output_path):
    """儲存 GeoJSON 檔案"""
    print(f"\n儲存檔案: {output_path}")
    
    with open(output_path, "w", encoding="utf-8") as f:
        json.dump(geojson, f, ensure_ascii=False, indent=2)
    
    print(f"檔案已儲存！")

def save_geojson_by_risk(geojson, base_output_path):
    """依風險等級分別儲存 GeoJSON 檔案"""
    
    # 依風險等級分類
    high_risk_features = []
    medium_risk_features = []
    low_risk_features = []
    
    for feature in geojson['features']:
        risk_level = feature['properties']['riskLevel']
        
        if risk_level == 'high':
            high_risk_features.append(feature)
        elif risk_level == 'medium':
            medium_risk_features.append(feature)
        elif risk_level == 'low':
            low_risk_features.append(feature)
    
    # 產生三個不同的 GeoJSON
    from geojson import FeatureCollection
    
    high_risk_geojson = FeatureCollection(high_risk_features)
    medium_risk_geojson = FeatureCollection(medium_risk_features)
    low_risk_geojson = FeatureCollection(low_risk_features)
    
    # 儲存檔案
    import os
    base_dir = os.path.dirname(base_output_path)
    
    high_risk_path = os.path.join(base_dir, 'accident_hotzones_high.geojson')
    medium_risk_path = os.path.join(base_dir, 'accident_hotzones_medium.geojson')
    low_risk_path = os.path.join(base_dir, 'accident_hotzones_low.geojson')
    
    print(f"\n儲存分級檔案:")
    
    # 儲存高風險
    with open(high_risk_path, "w", encoding="utf-8") as f:
        json.dump(high_risk_geojson, f, ensure_ascii=False, indent=2)
    print(f"   🔴 高風險: {high_risk_path} ({len(high_risk_features)} 個熱區)")
    
    # 儲存中風險
    with open(medium_risk_path, "w", encoding="utf-8") as f:
        json.dump(medium_risk_geojson, f, ensure_ascii=False, indent=2)
    print(f"   🟠 中風險: {medium_risk_path} ({len(medium_risk_features)} 個熱區)")
    
    # 儲存低風險
    with open(low_risk_path, "w", encoding="utf-8") as f:
        json.dump(low_risk_geojson, f, ensure_ascii=False, indent=2)
    print(f"   🟡 低風險: {low_risk_path} ({len(low_risk_features)} 個熱區)")
    
    print(f"✅ 分級檔案儲存完成！")

def print_statistics(geojson):
    """印出統計資訊"""
    print(f"\n熱區統計:")
    print(f"=" * 50)
    
    high_risk = sum(1 for f in geojson["features"] if f["properties"]["riskLevel"] == "high")
    medium_risk = sum(1 for f in geojson["features"] if f["properties"]["riskLevel"] == "medium")
    low_risk = sum(1 for f in geojson["features"] if f["properties"]["riskLevel"] == "low")
    
    total_accidents = sum(f["properties"]["accidentCount"] for f in geojson["features"])
    total_a1 = sum(f["properties"]["a1Count"] for f in geojson["features"])
    total_a2 = sum(f["properties"]["a2Count"] for f in geojson["features"])
    
    print(f"🔴 高風險熱區: {high_risk} 個")
    print(f"🟠 中風險熱區: {medium_risk} 個")
    print(f"🟡 低風險熱區: {low_risk} 個")
    print(f"📍 總計: {len(geojson['features'])} 個熱區")
    print(f"\n📈 涵蓋事故:")
    print(f"   總計: {total_accidents} 件")
    print(f"   A1 (死亡): {total_a1} 件")
    print(f"   A2 (受傷): {total_a2} 件")
    print(f"=" * 50)

def main():
    """主程式"""
    print("=" * 50)
    print(" 桃園市交通事故熱區生成器")
    print("=" * 50)
    
    # 設定檔案路徑
    input_file = "assets/hotzones/accident.csv"
    output_file = "assets/hotzones/accident_hotzones.geojson"
    
    # Step 1: 載入資料
    accidents = load_accidents(input_file)
    
    # Step 2: 過濾有效資料
    points, raw_data = filter_valid_accidents(accidents)
    
    if len(points) < 5:
        print(" 錯誤: 有效資料不足，無法進行聚類")
        return
    
    # Step 3: DBSCAN 聚類
    labels = cluster_accidents(
        points,
        eps=0.005,
        min_samples=100
    )
    
    # Step 4: 建立多邊形
    zones = create_hotzone_polygons(points, labels, raw_data)
    
    if len(zones) == 0:
        print("⚠️  警告: 未找到任何熱區，請調整 eps 或 min_samples 參數")
        return
    
    # Step 5: 轉換為 GeoJSON
    geojson = zones_to_geojson(zones)
    
    # Step 6: 儲存完整檔案
    save_geojson(geojson, output_file)
    
    # ✅ Step 7: 依風險等級分別儲存
    save_geojson_by_risk(geojson, output_file)
    
    # Step 8: 顯示統計
    print_statistics(geojson)

if __name__ == "__main__":
    main()