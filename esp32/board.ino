//this code is used in arduino ide, upload to esp32

/* uncomment below
#include "BluetoothSerial.h"

// Check if Bluetooth is enabled in the settings
#if !defined(CONFIG_BT_ENABLED) || !defined(CONFIG_BLUEDROID_ENABLED)
#error Bluetooth is not enabled! Please run `make menuconfig` to and enable it
#endif

BluetoothSerial SerialBT;

// --- Pin Definitions ---
const int TRIGGER_BUTTON_PIN = 21; // 紅色觸發按鈕
const int CANCEL_BUTTON_PIN = 18;  // 綠色取消按鈕 (Green Button)
const int BUZZER_PIN = 15;         // Buzzer Pin
const int RED_LED_PIN = 26;        // Red LED (Alarm)
const int YELLOW_LED_PIN = 27;     // Yellow LED (Warning)

// --- Button Variables ---
int lastState = HIGH;
int currentState;

// --- System State Variables ---
// 0: Idle/Stop
// 1: Warning (Yellow LED + Slow Beep)
// 2: Alarm (Red LED + Fast Siren)
int systemState = 0; 

// --- Timing Variables ---
unsigned long lastActionTime = 0; // Shared timer for blinking and buzzing
bool toggleState = false;         // Shared toggle state for ON/OFF

void setup() {
  Serial.begin(115200); // For USB debugging
  
  // Start Bluetooth
  SerialBT.begin("ESP32_BlueButton"); 
  Serial.println("Bluetooth Started! Pair with 'ESP32_BlueButton'");
  
  // Initialize Pins
  pinMode(TRIGGER_BUTTON_PIN, INPUT_PULLUP);
  pinMode(CANCEL_BUTTON_PIN, INPUT_PULLUP); // 🆕 設定綠色按鈕輸入
  
  pinMode(BUZZER_PIN, OUTPUT);
  pinMode(RED_LED_PIN, OUTPUT);
  pinMode(YELLOW_LED_PIN, OUTPUT);

  // Ensure everything is OFF at startup
  stopAllAlerts();
  
  // Wait a moment for power to stabilize
  delay(500);
}

void loop() {
  // =================================================
  // 1. 觸發按鈕 (GPIO 21) - 發送訊號給 App
  // =================================================
  currentState = digitalRead(TRIGGER_BUTTON_PIN);
  
  // Detect Button Press (Active Low)
  if (lastState == HIGH && currentState == LOW) {
    SerialBT.println("pressed");       // Send to App via Bluetooth
    Serial.println("Sent: pressed");   // Send to Computer via USB
    delay(50); // Debounce
  }
  lastState = currentState;

  // =================================================
  // 2. 🆕 綠色取消按鈕 (GPIO 18) - 直接停止警報
  // =================================================
  if (digitalRead(CANCEL_BUTTON_PIN) == LOW) {
    delay(50); // 簡單防彈跳
    if (digitalRead(CANCEL_BUTTON_PIN) == LOW) {
      Serial.println("Green Button Pressed: STOPPING ALARM");
      SerialBT.println("stopped");
      stopAllAlerts(); // 執行停止動作
      
      // 等待按鈕放開 (避免重複觸發)
      while(digitalRead(CANCEL_BUTTON_PIN) == LOW);
    }
  }

  // =================================================
  // 3. 接收 App 指令 (W, A, S)
  // =================================================
  if (SerialBT.available()) {
    char command = SerialBT.read();
    Serial.print("Received: ");
    Serial.println(command);

    if (command == 'W') {
      systemState = 1; // Warning Mode
      digitalWrite(RED_LED_PIN, LOW); // Ensure Red is OFF
    } 
    else if (command == 'A') {
      systemState = 2; // Alarm Mode
      digitalWrite(YELLOW_LED_PIN, LOW); // Ensure Yellow is OFF
    } 
    else if (command == 'S') {
      stopAllAlerts(); // App 傳來停止指令 -> 執行停止動作
    }
  }

  // =================================================
  // 4. 執行輸出邏輯 (LEDs + Buzzer)
  // =================================================
  unsigned long currentMillis = millis();
  
  if (systemState == 1) {
    // --- Warning Mode (W) ---
    // Yellow LED blinks, Buzzer beeps (200ms ON, 800ms OFF)
    if (currentMillis - lastActionTime >= (toggleState ? 200 : 800)) {
      lastActionTime = currentMillis;
      toggleState = !toggleState;
      
      if (toggleState) {
        tone(BUZZER_PIN, 1000); // 1000Hz beep
        digitalWrite(YELLOW_LED_PIN, HIGH);
      } else {
        noTone(BUZZER_PIN);
        digitalWrite(YELLOW_LED_PIN, LOW);
      }
    }
  } 
  else if (systemState == 2) {
    // --- Alarm Mode (A) ---
    // Red LED flashes, Buzzer sirens (100ms ON, 100ms OFF)
    if (currentMillis - lastActionTime >= 100) {
      lastActionTime = currentMillis;
      toggleState = !toggleState;
      
      if (toggleState) {
        tone(BUZZER_PIN, 2000); // 2000Hz siren
        digitalWrite(RED_LED_PIN, HIGH);
      } else {
        noTone(BUZZER_PIN);
        digitalWrite(RED_LED_PIN, LOW);
      }
    }
  }
  
  delay(10); // Stability delay
}

// 輔助函數：停止所有聲音和燈光 (等同於指令 'S')
void stopAllAlerts() {
  systemState = 0; // Set state to Idle
  
  // Turn EVERYTHING OFF
  digitalWrite(RED_LED_PIN, LOW);
  digitalWrite(YELLOW_LED_PIN, LOW);
  noTone(BUZZER_PIN);
}


*/