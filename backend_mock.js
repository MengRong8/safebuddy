// SafeBuddy 後端模擬 API 服務 (簡化版，加入 Twilio 簡訊功能)

const express = require('express');
const bodyParser = require('body-parser');
const twilio = require('twilio');
require('dotenv').config(); //  載入環境變數

const app = express();
const PORT = 3000;

//  從環境變數讀取 Twilio 憑證
const TWILIO_ACCOUNT_SID = process.env.TWILIO_ACCOUNT_SID;
const TWILIO_AUTH_TOKEN = process.env.TWILIO_AUTH_TOKEN;
const TWILIO_PHONE_NUMBER = process.env.TWILIO_PHONE_NUMBER;

// 初始化 Twilio 客戶端
const twilioClient = twilio(TWILIO_ACCOUNT_SID, TWILIO_AUTH_TOKEN);

// 使用 body-parser 中介軟體來解析 JSON 請求體
app.use(bodyParser.json());

//  新增 CORS 支援
app.use((req, res, next) => {
  res.header('Access-Control-Allow-Origin', '*');
  res.header('Access-Control-Allow-Headers', 'Content-Type');
  res.header('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  next();
});

// 模擬資料庫（使用記憶體儲存）
const mockDatabase = {
  alerts: []
};

/**
 *  真實簡訊 (SMS) 發送服務（使用 Twilio）
 */
async function sendSmsNotification(toPhoneNumber, messageBody, eventData) {
  console.log(`\n--- 📞 傳送 SMS 至 ${toPhoneNumber} ---`);
  console.log(`🚨 訊息內容: ${messageBody}`);
  console.log(`事件位置 (App GPS): 緯度 ${eventData.latitude}, 經度 ${eventData.longitude}`);
  
  try {
    //  真實發送簡訊
    const message = await twilioClient.messages.create({
      body: messageBody,
      from: TWILIO_PHONE_NUMBER,
      to: toPhoneNumber
    });
    
    console.log(` 簡訊已成功發送！訊息 SID: ${message.sid}`);
    console.log("------------------------------------------");
    return { success: true, messageSid: message.sid };
    
  } catch (error) {
    console.error(`❌ 簡訊發送失敗: ${error.message}`);
    console.log("------------------------------------------");
    return { success: false, error: error.message };
  }
}



// --- API 路由定義 ---

// Endpoint 1: 處理緊急警報觸發
app.post('/api/alert', async (req, res) => {
  const { userId, latitude, longitude, contactNumber, triggerType } = req.body;

  if (!userId || !latitude || !longitude || !contactNumber || !triggerType) {
    return res.status(400).send({ success: false, message: '缺少必要的請求參數。' });
  }

  const now = new Date();
  const timeHour = now.getHours();
  const riskCheck = aiRiskPrediction(latitude, longitude, timeHour);

  try {
    const alertId = `alert_${Date.now()}`;
    const eventData = {
      alertId,
      userId,
      latitude,
      longitude,
      contactNumber,
      triggerType,
      timestamp: now.toISOString(),
      isCancelled: false,
      cancellationTime: null,
      riskScore: riskCheck.riskScore,
      riskMessage: riskCheck.message,
      status: 'PENDING_CONFIRMATION'
    };

    // 儲存到記憶體資料庫
    mockDatabase.alerts.push(eventData);

    //  發送真實簡訊通知
    const smsMessage = `🚨緊急警報! SafeBuddy 用戶 (ID: ${userId}) 觸發了 ${triggerType} 警報。當前位置: https://maps.google.com/?q=${latitude},${longitude} 。請立即聯繫!`;
    const smsResult = await sendSmsNotification(contactNumber, smsMessage, eventData);

    res.status(200).send({
      success: true,
      alertId: alertId,
      smsDelivered: smsResult.success,
      messageSid: smsResult.messageSid || null,
      riskInfo: {
        riskScore: riskCheck.riskScore,
        riskMessage: riskCheck.message,
        isHighRisk: riskCheck.isHighRisk
      },
      message: smsResult.success 
        ? '警報已記錄，緊急通知已送出。' 
        : '警報已記錄，但簡訊發送失敗。'
    });
  } catch (error) {
    console.error('寫入警報事件失敗:', error);
    res.status(500).send({ success: false, message: '伺服器內部錯誤，無法記錄警報。' });
  }
});

// Endpoint 2: 處理警報取消
app.post('/api/cancel', async (req, res) => {
  const { alertId } = req.body;

  if (!alertId) {
    return res.status(400).send({ success: false, message: '缺少 alertId 參數。' });
  }

  try {
    const alert = mockDatabase.alerts.find(a => a.alertId === alertId);

    if (!alert) {
      return res.status(404).send({ success: false, message: '找不到對應的警報事件。' });
    }

    if (alert.isCancelled) {
      return res.status(200).send({ success: true, message: '警報已於稍早取消。' });
    }

    // 更新狀態
    alert.isCancelled = true;
    alert.cancellationTime = new Date().toISOString();
    alert.status = 'CANCELLED_SAFE';

    //  發送「回報平安」簡訊
    const safeMessage = ` SafeBuddy 用戶 (ID: ${alert.userId}) 已回報平安。原緊急警報已解除，請放心。`;
    const smsResult = await sendSmsNotification(alert.contactNumber, safeMessage, alert);

    res.status(200).send({ 
      success: true, 
      message: '警報已成功取消並回報平安。',
      smsDelivered: smsResult.success
    });

  } catch (error) {
    console.error('取消警報失敗:', error);
    res.status(500).send({ success: false, message: '伺服器內部錯誤，無法取消警報。' });
  }
});

// Endpoint 3: 詢問 AI 危險判斷 (用於 App 主動提醒)
app.post('/api/check-risk', (req, res) => {
  const { latitude, longitude } = req.body;

  if (!latitude || !longitude) {
    return res.status(400).send({ success: false, message: '缺少經緯度參數。' });
  }

  const timeHour = new Date().getHours();
  const riskCheck = aiRiskPrediction(latitude, longitude, timeHour);

  res.status(200).send({
    success: true,
    riskScore: riskCheck.riskScore,
    message: riskCheck.message,
    isHighRisk: riskCheck.isHighRisk
  });
});

//  Endpoint 4: 測試簡訊發送端點（這是缺少的部分！）
app.post('/api/test-sms', async (req, res) => {
  const { phoneNumber, message } = req.body;

  if (!phoneNumber || !message) {
    return res.status(400).send({ 
      success: false, 
      message: '缺少 phoneNumber 或 message 參數。' 
    });
  }

  try {
    const result = await twilioClient.messages.create({
      body: message,
      from: TWILIO_PHONE_NUMBER,
      to: phoneNumber
    });

    res.status(200).send({
      success: true,
      messageSid: result.sid,
      status: result.status,
      message: '測試簡訊已發送！'
    });
  } catch (error) {
    res.status(500).send({
      success: false,
      error: error.message,
      message: '簡訊發送失敗。'
    });
  }
});

//  根路徑
app.get('/', (req, res) => {
  res.json({
    status: 'running',
    message: 'SafeBuddy Mock Backend API Server (with Twilio SMS)',
    endpoints: [
      { method: 'POST', path: '/api/alert', description: 'Trigger emergency alert (sends SMS)' },
      { method: 'POST', path: '/api/cancel', description: 'Cancel alert (sends safe SMS)' },
      { method: 'POST', path: '/api/check-risk', description: 'Check risk level' },
      { method: 'POST', path: '/api/test-sms', description: 'Test SMS sending' }
    ],
    alerts: mockDatabase.alerts.length,
    twilioConfigured: TWILIO_ACCOUNT_SID !== 'your_account_sid_here'
  });
});

// 啟動伺服器
app.listen(PORT, () => {
  console.log(`\n==========================================`);
  console.log(`SafeBuddy Mock 後端伺服器已啟動: http://localhost:${PORT}`);
  console.log(`==========================================`);
  console.log(`\n測試 API 端點 (使用 POST 請求):`);
  console.log(`- 警報觸發: POST /api/alert (會發送真實簡訊)`);
  console.log(`- 警報取消: POST /api/cancel (會發送平安簡訊)`);
  console.log(`- 風險檢查: POST /api/check-risk`);
  console.log(`- 測試簡訊: POST /api/test-sms`);
  console.log(`- 查看狀態: GET /`);
  
  if (TWILIO_ACCOUNT_SID === 'your_account_sid_here') {
    console.log(`\n⚠️ 警告：尚未設定 Twilio 帳號資訊！`);
    console.log(`請修改 backend_mock.js 中的以下變數：`);
    console.log(`- TWILIO_ACCOUNT_SID`);
    console.log(`- TWILIO_AUTH_TOKEN`);
    console.log(`- TWILIO_PHONE_NUMBER`);
  } else {
    console.log(`\n Twilio 簡訊功能已啟用`);
  }
  
  console.log(`\n 伺服器運行正常，等待請求...`);
});
