//this code is used in arduino ide, upload to esp32

/* uncomment below

#include <WiFi.h>
#include <WebServer.h>

// 1. Wi-Fi 設定 (已填入您的資訊)
const char* ssid = "greenUmbrella";
const char* password = "109104032";

// 建立 Web Server 在 Port 80
WebServer server(80);

// --- 腳位定義 (與藍牙版相同) ---
const int TRIGGER_BUTTON_PIN = 21; // 紅色觸發按鈕
const int CANCEL_BUTTON_PIN = 18;  // 綠色取消按鈕
const int BUZZER_PIN = 15;         // 蜂鳴器
const int RED_LED_PIN = 26;        // 紅燈 (Alarm)
const int YELLOW_LED_PIN = 27;     // 黃燈 (Warning)

// --- 狀態變數 ---
// 旗標：用來告訴 App 按鈕被按過了
bool triggerPressedFlag = false; 
bool cancelPressedFlag = false;

// 系統狀態 (0: Stop, 1: Warning, 2: Alarm)
int systemState = 0;
unsigned long lastActionTime = 0;
bool toggleState = false;

// --- 輔助函數：停止所有警報 ---
void stopAllAlerts() {
  systemState = 0;
  digitalWrite(RED_LED_PIN, LOW);
  digitalWrite(YELLOW_LED_PIN, LOW);
  digitalWrite(BUZZER_PIN, LOW);
  noTone(BUZZER_PIN);
}

// --- API 1: 讓 App 查詢按鈕狀態 (Polling) ---
// 網址: http://<ESP_IP>/status
void handleStatus() {
  String json = "{";
  json += "\"trigger\":" + String(triggerPressedFlag ? "true" : "false") + ",";
  json += "\"cancel\":" + String(cancelPressedFlag ? "true" : "false");
  json += "}";
  
  server.send(200, "application/json", json);
  
  // App 讀取完後，將旗標重置，避免重複觸發
  if(triggerPressedFlag) triggerPressedFlag = false;
  if(cancelPressedFlag) cancelPressedFlag = false;
}

// --- API 2: 讓 App 控制警報 (Command) ---
// 網址: http://<ESP_IP>/set?cmd=W
void handleSetCommand() {
  if (server.hasArg("cmd")) {
    String cmd = server.arg("cmd");
    Serial.println("收到指令: " + cmd);
    
    if (cmd == "W") {
      systemState = 1; // Warning Mode
      digitalWrite(RED_LED_PIN, LOW);
    } else if (cmd == "A") {
      systemState = 2; // Alarm Mode
      digitalWrite(YELLOW_LED_PIN, LOW);
    } else if (cmd == "S") {
      systemState = 0; // Stop Mode
      stopAllAlerts();
    }
    server.send(200, "text/plain", "OK");
  } else {
    server.send(400, "text/plain", "Missing cmd");
  }
}

void setup() {
  Serial.begin(9600);
  
  // 初始化腳位
  pinMode(TRIGGER_BUTTON_PIN, INPUT_PULLUP);
  pinMode(CANCEL_BUTTON_PIN, INPUT_PULLUP);
  pinMode(BUZZER_PIN, OUTPUT);
  pinMode(RED_LED_PIN, OUTPUT);
  pinMode(YELLOW_LED_PIN, OUTPUT);
  
  stopAllAlerts();

  // 連接 Wi-Fi
  Serial.print("Connecting to ");
  Serial.println(ssid);
  WiFi.begin(ssid, password);
  
  while (WiFi.status() != WL_CONNECTED) {
    delay(500);
    Serial.print(".");
  }
  Serial.println("");
  Serial.println("Wi-Fi connected.");
  Serial.print("IP address: ");
  Serial.println(WiFi.localIP()); // ⚠️ 重要：請記下這個 IP

  // 設定 API 路徑
  server.on("/status", handleStatus); 
  server.on("/set", handleSetCommand);
  server.begin();
  Serial.println("HTTP Server Started");
}

void loop() {
  Serial.println(WiFi.localIP());
  server.handleClient(); // 處理來自 App 的請求

  // --- 1. 讀取紅色觸發按鈕 ---
  if (digitalRead(TRIGGER_BUTTON_PIN) == LOW) {
    delay(50);
    if (digitalRead(TRIGGER_BUTTON_PIN) == LOW) {
      triggerPressedFlag = true; // 立旗標
      Serial.println("Trigger Button Pressed!");
      while(digitalRead(TRIGGER_BUTTON_PIN) == LOW);
    }
  }

  // --- 2. 讀取綠色取消按鈕 ---
  if (digitalRead(CANCEL_BUTTON_PIN) == LOW) {
    delay(50);
    if (digitalRead(CANCEL_BUTTON_PIN) == LOW) {
      cancelPressedFlag = true; // 立旗標
      Serial.println("Cancel Button Pressed!");
      stopAllAlerts(); // 硬體優先停止
      while(digitalRead(CANCEL_BUTTON_PIN) == LOW);
    }
  }

  // --- 3. 處理聲光效果 (非阻塞式) ---
  unsigned long currentMillis = millis();
  
  // Warning Mode (黃燈 + 慢嗶)
  if (systemState == 1) { 
    if (currentMillis - lastActionTime >= (toggleState ? 200 : 800)) {
      lastActionTime = currentMillis;
      toggleState = !toggleState;
      if (toggleState) { 
        tone(BUZZER_PIN, 1000); 
        digitalWrite(YELLOW_LED_PIN, HIGH); 
      } else { 
        noTone(BUZZER_PIN); 
        digitalWrite(YELLOW_LED_PIN, LOW); 
      }
    }
  } 
  // Alarm Mode (紅燈 + 快嗶)
  else if (systemState == 2) { 
    if (currentMillis - lastActionTime >= 100) {
      lastActionTime = currentMillis;
      toggleState = !toggleState;
      if (toggleState) { 
        tone(BUZZER_PIN, 2000); 
        digitalWrite(RED_LED_PIN, HIGH); 
      } else { 
        noTone(BUZZER_PIN); 
        digitalWrite(RED_LED_PIN, LOW); 
      }
    }
  }
  
  delay(10); // 穩定 CPU
}


*/