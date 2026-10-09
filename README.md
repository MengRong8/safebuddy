# SafeBuddy — 藍牙／Wi-Fi 防身警報裝置與求助聯動系統

> 國立中央大學資工系 團隊專題　｜　指導教授：周立德 教授　｜　成員：陳孟蓉、郭語婕、江玉如
> 🥉 計算機網路應用創意競賽 銅牌獎

SafeBuddy 是一套軟硬體整合的個人安全系統：使用者按下隨身的 ESP32 警報按鈕後，裝置會鳴笛、閃燈，並透過藍牙或 Wi-Fi 通知電腦端 App；App 再呼叫後端服務，以簡訊將求助訊息與目前位置傳給緊急聯絡人。App 同時以地圖呈現交通事故熱區，使用者接近高風險區域時會收到提醒。

## 系統架構

```
 ┌──────────────┐  Bluetooth Serial / HTTP   ┌──────────────────────┐   REST API   ┌──────────────────────┐
 │ ESP32 警報器 │ ─────────────────────────▶ │ Flutter App (Windows)│ ───────────▶ │ Node.js / Express    │
 │ 按鈕・蜂鳴器 │ ◀───────────────────────── │ 地圖・熱區・通知      │ ◀─────────── │ 後端服務              │
 │ 紅／黃 LED   │      狀態指令 (W / A / S)  └──────────────────────┘              └─────────┬────────────┘
 └──────────────┘                                                                            │ Twilio SMS
                                                                                             ▼
                                                                                      緊急聯絡人手機
```

| 模組 | 內容 | 主要檔案 |
|---|---|---|
| 硬體端 | ESP32：觸發／取消按鈕、蜂鳴器、紅黃 LED，三段狀態（待機／警告／警報）。提供藍牙序列與 Wi-Fi HTTP 兩種連線版本 | `esp32/bluetooth.ino`、`esp32/wifi.ino` |
| App 端 | Flutter（Windows 桌面）：接收裝置訊號、`flutter_map` 地圖、事故熱區疊圖、危險區域通知、使用者登入與資料管理（SQLite） | `lib/` |
| 後端 | Express API：`/api/alert` 發送求助簡訊、`/api/cancel` 解除警報、`/api/check-risk` 位置風險評分、`/api/notify-family` 通知家人 | `backend_mock.js` |
| 熱區資料 | 以 2024 年桃園市交通事故資料（約 9.2 萬筆）做 DBSCAN 空間聚類，依事故密度輸出高／中／低三級 GeoJSON 熱區 | `generate_hotzones.py`、`assets/hotzones/` |

## 技術重點

- **雙通道裝置連線**：同一套 App 邏輯支援藍牙序列（`lib/main.dart`）與 Wi-Fi HTTP 輪詢（`lib/wifi_main.dart`），斷線時自動重試。
- **資料驅動的危險區域**：以 DBSCAN（eps ≈ 1.1 km）對事故座標分群，再依群內事故數分級，取代人工標註。
- **求助流程閉環**：按鈕觸發 → App 取得位置 → 後端以 Twilio 傳送含座標的簡訊 → 可由裝置或 App 取消。

## 執行方式

**1. 後端**

```bash
npm install
cp .env.example .env   # 填入 Twilio 帳號、寄件號碼與聯絡人號碼
npm start              # 預設 http://localhost:3000
```

**2. Flutter App（Windows）**

```bash
flutter pub get
flutter run -d windows
```

藍牙版請先在 `lib/main.dart` 設定裝置的 COM port；Wi-Fi 版請在 `lib/wifi_main.dart` 設定 ESP32 的 IP。

**3. ESP32**

以 Arduino IDE 開啟 `esp32/bluetooth.ino` 或 `esp32/wifi.ino` 上傳至 ESP32（Wi-Fi 版需先填入網路名稱與密碼）。

**4. 重新產生熱區（選用）**

```bash
pip install numpy scikit-learn shapely geojson
python generate_hotzones.py
```

## 目前限制

- 位置風險評分（`/api/check-risk`）目前為規則式模擬：依夜間時段與距熱區遠近加權，尚未接入預測模型。
- App 以 Windows 桌面版開發與展示，行動裝置版本尚未建置。
