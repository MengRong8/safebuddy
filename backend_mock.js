// SafeBuddy 後端模擬 API 服務 (簡化版，加入 Twilio 簡訊功能)

const express = require('express');
const bodyParser = require('body-parser');
const twilio = require('twilio');
require('dotenv').config(); // 載入環境變數

const app = express();
const PORT = 3000;

// 從環境變數讀取 Twilio 憑證
const accountSid = process.env.TWILIO_ACCOUNT_SID;
const authToken = process.env.TWILIO_AUTH_TOKEN;
const fromNumber = process.env.TWILIO_PHONE_NUMBER;
const toNumber = process.env.RECIPIENT_PHONE_NUMBER;

// 初始化 Twilio 客戶端
const client = twilio(accountSid, authToken);

// 使用 body-parser 中介軟體來解析 JSON 請求體
app.use(bodyParser.json());

app.use((req, res, next) => {
  res.header('Access-Control-Allow-Origin', '*'); // 允許所有來源
  res.header('Access-Control-Allow-Headers', 'Content-Type, Authorization'); // 允許的標頭
  res.header('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, OPTIONS'); // 允許的方法
  res.header('Access-Control-Allow-Credentials', 'true'); // 允許憑證
  
  // 處理 OPTIONS 預檢請求
  if (req.method === 'OPTIONS') {
    return res.status(200).end();
  }
  
  // 記錄所有請求
  console.log(`\n 收到請求: ${req.method} ${req.path}`);
  console.log(`   來源: ${req.get('origin') || '未知'}`);
  console.log(`   User-Agent: ${req.get('user-agent') || '未知'}`);
  
  next();
});

// 模擬資料庫（使用記憶體儲存）
const mockDatabase = {
  alerts: []
};

/**
 * 真實簡訊 (SMS) 發送服務（使用 Twilio）- 使用 testing.js 的方法
 * @param {string} customRecipient - 接收者電話號碼（可選，預設為 toNumber）
 * @param {string} messageBody - 簡訊內容
 * @param {object} eventData - 事件資料（用於日誌）
 */
async function sendSmsNotification(customRecipient = null, messageBody, eventData = {}) {
  const recipient = customRecipient || toNumber;
  
  // 檢查簡訊長度（試用帳號前綴約 40 字元 + 訊息內容不可超過 120 字元）
  const maxLength = 120;
  if (messageBody.length > maxLength) {
    console.log(` 警告: 簡訊內容過長 (${messageBody.length} 字元)，將截斷至 ${maxLength} 字元`);
    messageBody = messageBody.substring(0, maxLength);
  }
  
  console.log(`\n---  發送簡訊 ---`);
  console.log(`訊息內容: ${messageBody}`);
  console.log(`發送者: ${fromNumber}`);
  console.log(`接收者: ${recipient}`);
  console.log(`訊息長度: ${messageBody.length} 字元`);
  
  if (eventData.latitude && eventData.longitude) {
    console.log(`事件位置: 緯度 ${eventData.latitude}, 經度 ${eventData.longitude}`);
  }
  
  try {
    // 使用 testing.js 的方法發送簡訊
    const message = await client.messages.create({
      body: messageBody,
      from: fromNumber,
      to: recipient,
    });

    console.log(`\n簡訊已發送！`);
    console.log(`訊息 SID: ${message.sid}`);
    console.log(`狀態: ${message.status}`);
    console.log(`發送至: ${message.to}`);
    console.log(`訊息內容: ${message.body}`);
    console.log(`------------------`);
    
    return { 
      success: true, 
      messageSid: message.sid,
      status: message.status,
      to: message.to
    };
    
  } catch (error) {
    console.error(`\n 簡訊發送失敗:`);
    console.error(`錯誤訊息: ${error.message}`);
    console.error(`錯誤代碼: ${error.code || 'N/A'}`);
    console.error(`------------------`);
    
    return { 
      success: false, 
      error: error.message,
      errorCode: error.code
    };
  }
}

/**
 * 模擬 AI 危險區域判斷邏輯。
 */
function aiRiskPrediction(latitude, longitude, timeHour) {
  let riskScore = 10;
  let message = "目前區域風險普通。";

  // 模擬：夜間 (22:00-06:00) 提高風險分數
  const isNightTime = timeHour >= 22 || timeHour < 6;
  if (isNightTime) {
    riskScore += 40;
    message = "此為夜間時段 (22:00-06:00)，區域人流較少，請特別注意安全！";
  }

  // 模擬：特定區域提高風險
  const hotspotLat = 25.04;
  const hotspotLon = 121.5;
  const distance = Math.sqrt(Math.pow(latitude - hotspotLat, 2) + Math.pow(longitude - hotspotLon, 2));

  if (distance < 0.1) {
    riskScore += 30;
    message = "靠近歷史事故/犯罪高發區！請提高警覺。";
  }

  riskScore = Math.min(riskScore, 100);

  return {
    riskScore: riskScore,
    message: message,
    isHighRisk: riskScore >= 70
  };
}

// --- API 路由定義 ---

// Endpoint 1: 處理緊急警報觸發
app.post('/api/alert', async (req, res) => {
  const { userId, latitude, longitude, contactNumber, triggerType } = req.body;

  if (!userId || !latitude || !longitude || !triggerType) {
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
      contactNumber: contactNumber || toNumber,
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

    console.log(`\n 緊急警報觸發！`);
    console.log(`警報 ID: ${alertId}`);
    console.log(`用戶 ID: ${userId}`);
    console.log(`觸發類型: ${triggerType}`);
    console.log(`風險分數: ${riskCheck.riskScore}/100`);

    const smsMessage = `緊急!${triggerType}警報
                    使用者當前位置 : maps.google.com/?q=${latitude.toFixed(4)},${longitude.toFixed(4)}
                    請盡速與使用者聯繫
                    -- SafeBuddy`;

    const smsResult = await sendSmsNotification(
      contactNumber,
      smsMessage, 
      eventData
    );

    res.status(200).send({
      success: true,
      alertId: alertId,
      smsDelivered: smsResult.success,
      messageSid: smsResult.messageSid || null,
      recipientNumber: smsResult.to || toNumber,
      riskInfo: {
        riskScore: riskCheck.riskScore,
        riskMessage: riskCheck.message,
        isHighRisk: riskCheck.isHighRisk
      },
      message: smsResult.success 
        ? '警報已記錄，緊急通知已送出給家人。' 
        : `警報已記錄，但簡訊發送失敗: ${smsResult.error}`
    });
  } catch (error) {
    console.error(' 寫入警報事件失敗:', error);
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
    console.log(`\n=== 警報取消 ===`);
    console.log(`   警報 ID: ${alertId}`);
    console.log(`   取消時間: ${new Date().toISOString()}`);

    // 簡化版簡訊內容（不需要 alert 物件）
    const safeMessage = `平安！警報為誤觸
用戶已回報平安。
時間: ${new Date().toLocaleString('zh-TW', { timeZone: 'Asia/Taipei' })}
-- SafeBuddy`;

    // 直接使用 toNumber（從 .env 讀取）
    const smsResult = await sendSmsNotification(
      null,          // 使用預設的 toNumber
      safeMessage,   // 簡訊內容
      { alertId }    // 事件資料
    );

    console.log(`\n 簡訊發送結果:`);
    console.log(`   成功: ${smsResult.success}`);
    console.log(`   接收者: ${smsResult.to || toNumber}`);

    // 回傳結果給 Flutter
    res.status(200).send({ 
      success: true, 
      message: '警報已成功取消並回報平安。',
      smsDelivered: smsResult.success,
      messageSid: smsResult.messageSid || null,
      recipientNumber: smsResult.to || toNumber,
      alertId: alertId
    });

  } catch (error) {
    console.error('\n 取消警報失敗:', error);
    console.error('   錯誤訊息:', error.message);
    console.error('   錯誤堆疊:', error.stack);
    
    res.status(500).send({ 
      success: false, 
      message: '伺服器內部錯誤，無法取消警報。',
      error: error.message
    });
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

  console.log(`\n 風險檢查`);
  console.log(`位置: ${latitude}, ${longitude}`);
  console.log(`風險分數: ${riskCheck.riskScore}/100`);
  console.log(`是否高風險: ${riskCheck.isHighRisk ? '是' : '否'}`);

  res.status(200).send({
    success: true,
    riskScore: riskCheck.riskScore,
    message: riskCheck.message,
    isHighRisk: riskCheck.isHighRisk
  });
});

// Endpoint 4: 測試簡訊發送端點
app.post('/api/test-sms', async (req, res) => {
  const { phoneNumber, message } = req.body;

  const recipient = phoneNumber || toNumber;
  const messageBody = message || 'SafeBuddy測試:系統正常';

  if (!recipient) {
    return res.status(400).send({ 
      success: false, 
      message: '缺少接收者電話號碼（phoneNumber）或環境變數 RECIPIENT_PHONE_NUMBER。' 
    });
  }

  console.log(`\n 測試簡訊發送`);
  console.log(`訊息: ${messageBody}`);
  console.log(`接收者: ${recipient}`);

  try {
    const result = await client.messages.create({
      body: messageBody,
      from: fromNumber,
      to: recipient,
    });

    console.log(`\n測試簡訊已發送！`);
    console.log(`訊息 SID: ${result.sid}`);
    console.log(`狀態: ${result.status}`);
    console.log(`發送至: ${result.to}`);

    res.status(200).send({
      success: true,
      messageSid: result.sid,
      status: result.status,
      to: result.to,
      message: '測試簡訊已發送！'
    });
  } catch (error) {
    console.error(`\n 測試簡訊發送失敗:`);
    console.error(`錯誤訊息: ${error.message}`);
    console.error(`錯誤代碼: ${error.code || 'N/A'}`);

    res.status(500).send({
      success: false,
      error: error.message,
      errorCode: error.code,
      message: '簡訊發送失敗。'
    });
  }
});

// Endpoint 5: 發送簡訊給家人
app.post('/api/notify-family', async (req, res) => {
  const { message, userId, latitude, longitude } = req.body;

  if (!message) {
    return res.status(400).send({ 
      success: false, 
      message: '缺少訊息內容（message）參數。' 
    });
  }

  const eventData = {
    userId: userId || 'UNKNOWN',
    latitude: latitude || null,
    longitude: longitude || null
  };

  console.log(`\n 通知家人`);
  console.log(`訊息: ${message}`);
  console.log(`用戶 ID: ${userId || '未提供'}`);

  try {
    const smsResult = await sendSmsNotification(
      null,
      message,
      eventData
    );

    res.status(200).send({
      success: smsResult.success,
      messageSid: smsResult.messageSid || null,
      status: smsResult.status || null,
      recipientNumber: smsResult.to || toNumber,
      message: smsResult.success 
        ? '簡訊已成功發送給家人。' 
        : `簡訊發送失敗: ${smsResult.error}`
    });
  } catch (error) {
    console.error(' 通知家人失敗:', error);
    res.status(500).send({
      success: false,
      error: error.message,
      message: '伺服器內部錯誤。'
    });
  }
});

// Endpoint 6: 查看所有警報
app.get('/api/alerts', (req, res) => {
  console.log(`\n 查詢所有警報 (共 ${mockDatabase.alerts.length} 筆)`);
  
  res.status(200).send({
    success: true,
    count: mockDatabase.alerts.length,
    alerts: mockDatabase.alerts
  });
});

// 根路徑
app.get('/', (req, res) => {
  console.log(`\n根路徑請求成功`);
  
  res.json({
    status: 'running',
    message: 'SafeBuddy Mock Backend API Server (with Twilio SMS)',
    version: '1.0.0',
    endpoints: [
      { method: 'POST', path: '/api/alert', description: 'Trigger emergency alert (sends SMS to family)' },
      { method: 'POST', path: '/api/cancel', description: 'Cancel alert (sends safe SMS to family)' },
      { method: 'POST', path: '/api/check-risk', description: 'Check risk level' },
      { method: 'POST', path: '/api/test-sms', description: 'Test SMS sending (optional recipient)' },
      { method: 'POST', path: '/api/notify-family', description: 'Send custom message to family' },
      { method: 'GET', path: '/api/alerts', description: 'View all alerts' }
    ],
    alerts: mockDatabase.alerts.length,
    twilioConfigured: !!(accountSid && authToken && fromNumber),
    recipientConfigured: !!toNumber
  });
});

// 新增：健康檢查端點
app.get('/health', (req, res) => {
  console.log(`\n 健康檢查請求`);
  res.json({ 
    status: 'healthy', 
    timestamp: new Date().toISOString(),
    uptime: process.uptime()
  });
});

// 啟動伺服器
app.listen(PORT, async () => {
  console.log(`\n==========================================`);
  console.log(` SafeBuddy Mock 後端伺服器已啟動`);
  console.log(`==========================================`);
  console.log(`\n 伺服器位址: http://localhost:${PORT}`);
  console.log(` 啟動時間: ${new Date().toLocaleString('zh-TW')}`);
  
  // 新增：顯示所有可用的網路位址
  const os = require('os');
  const interfaces = os.networkInterfaces();
  console.log(`\n 可用的網路位址:`);
  console.log(`   http://localhost:${PORT}`);
  console.log(`   http://127.0.0.1:${PORT}`);
  
  Object.keys(interfaces).forEach(interfaceName => {
    interfaces[interfaceName].forEach(iface => {
      if (iface.family === 'IPv4' && !iface.internal) {
        console.log(`   http://${iface.address}:${PORT}`);
      }
    });
  });
  
  console.log(`\n 可用的 API 端點:`);
  console.log(`   GET    /                    - 伺服器狀態`);
  console.log(`   GET    /health              - 健康檢查`);
  console.log(`   POST   /api/alert           - 觸發緊急警報`);
  console.log(`   POST   /api/cancel          - 取消警報`);
  console.log(`   POST   /api/check-risk      - 檢查風險等級`);
  console.log(`   POST   /api/test-sms        - 測試簡訊發送`);
  console.log(`   POST   /api/notify-family   - 通知家人`);
  console.log(`   GET    /api/alerts          - 查看所有警報`);
  
  console.log(`\n---  環境變數檢查 ---`);
  
  // 檢查憑證是否載入
  if (!accountSid || !authToken || !fromNumber || !toNumber) {
    console.log(` 錯誤：請確認 .env 檔案包含所有必要的 Twilio 憑證`);
    console.log(`需要的環境變數：`);
    console.log(`- TWILIO_ACCOUNT_SID`);
    console.log(`- TWILIO_AUTH_TOKEN`);
    console.log(`- TWILIO_PHONE_NUMBER`);
    console.log(`- RECIPIENT_PHONE_NUMBER`);
  } else {
    console.log(`Twilio Account SID: ${accountSid.substring(0, 10)}...`);
    console.log(`Twilio Auth Token: ${authToken.substring(0, 4)}****`);
    console.log(`Twilio Phone Number: ${fromNumber}`);
    console.log(`Recipient Phone Number (家人): ${toNumber}`);
    
    console.log(`\n 測試 Twilio 連線...`);
    
    try {
      // 測試 API 連線（不發送簡訊）
      const account = await client.api.accounts(accountSid).fetch();
      
      console.log(`Twilio 連線成功！`);
      console.log(`   帳號名稱: ${account.friendlyName}`);
      console.log(`   帳號狀態: ${account.status}`);
      console.log(`   帳號類型: ${account.type}`);
      
    } catch (error) {
      console.error(`\n Twilio 連線失敗:`);
      console.error(`   錯誤: ${error.message}`);
      console.error(`   錯誤代碼: ${error.code || 'N/A'}`);
    }
  }
  
  console.log(`\n伺服器運行正常，等待請求...`);
  console.log(`==========================================\n`);
  
  // 新增：提示 Flutter 連線測試命令
  console.log(` Flutter 連線測試命令 (在 Flutter Debug Console):`);
  console.log(`   final response = await http.get(Uri.parse('http://localhost:3000/'));`);
  console.log(`   print(response.body);`);
  console.log(`\n`);
});
