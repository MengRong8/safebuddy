// SafeBuddy 後端模擬 API 服務 (使用 Node.js / Express / Firestore)
//
// 此檔案模擬了 SafeBuddy 專案所需的後端核心功能：
// 1. 警報事件記錄與簡訊通知轉發。
// 2. 警報取消機制。
// 3. AI 危險區域風險判斷。
//
// **注意：要運行此程式碼，您需要在本地安裝 Node.js、Express 和 Firebase Admin SDK，**
// **並替換 'YOUR_FIREBASE_SERVICE_ACCOUNT_PATH' 和 'YOUR_PROJECT_ID'。**

const express = require('express');
const bodyParser = require('body-parser');
const admin = require('firebase-admin');

// --- 1. Firebase 初始化設定 ---
//
// 實際專案中，您應使用服務帳戶金鑰來初始化 Firebase Admin SDK。
// 請確保您的服務帳戶 JSON 檔案路徑正確。
// 如果沒有金鑰檔案，可以先使用一個模擬物件。

const SERVICE_ACCOUNT_PATH = 'YOUR_FIREBASE_SERVICE_ACCOUNT_PATH'; // <--- 請替換成您的路徑
const PROJECT_ID = 'YOUR_PROJECT_ID'; // <--- 請替換成您的專案 ID

try {
    // 這裡假設您已設定好服務帳號，如果沒有，請在 Firebase Console 取得
    const serviceAccount = require(SERVICE_ACCOUNT_PATH);
    admin.initializeApp({
        credential: admin.credential.cert(serviceAccount),
        databaseURL: `https://${PROJECT_ID}.firebaseio.com`
    });
    console.log("Firebase Admin SDK 初始化成功。");
} catch (error) {
    console.error("⚠️ 警告：Firebase Admin SDK 初始化失敗。", error.message);
    console.log("正在使用模擬資料庫，請在正式環境中配置有效的服務帳戶。");
    // 如果服務帳戶設定失敗，使用模擬資料庫
    admin.initializeApp({
        projectId: PROJECT_ID || 'mock-project-id'
    });
}

const db = admin.firestore();
const app = express();
const PORT = 3000;

// 使用 body-parser 中介軟體來解析 JSON 請求體
app.use(bodyParser.json());

// --- 2. 核心功能函數定義 ---

/**
 * 模擬簡訊 (SMS) 發送服務。
 * 在真實專案中，這裡會替換為 Twilio, MessageBird 或其他 SMS 閘道器的 API 呼叫。
 * @param {string} toPhoneNumber - 接收者電話號碼 (緊急聯絡人)。
 * @param {string} messageBody - 簡訊內容。
 * @param {object} eventData - 警報事件資料。
 */
function sendSmsNotification(toPhoneNumber, messageBody, eventData) {
    // 在此處插入實際 SMS API 呼叫邏輯
    console.log(`\n--- 📞 模擬 SMS 傳送至 ${toPhoneNumber} ---`);
    console.log(`🚨 訊息內容: ${messageBody}`);
    console.log(`事件位置 (App GPS): 緯度 ${eventData.latitude}, 經度 ${eventData.longitude}`);
    console.log("------------------------------------------");
    return true; // 模擬發送成功
}

/**
 * 模擬 AI 危險區域判斷邏輯。
 * 根據簡報，此處應結合地理圍欄 (Geofence) 和高風險資料庫。
 * @param {number} latitude - 使用者緯度。
 * @param {number} longitude - 使用者經度。
 * @param {number} timeHour - 觸發事件的小時 (0-23)。
 * @returns {object} 包含風險分數 (0-100) 和提示訊息。
 */
function aiRiskPrediction(latitude, longitude, timeHour) {
    let riskScore = 10;
    let message = "目前區域風險普通。";

    // 模擬：夜間 (22:00-06:00) 提高風險分數
    const isNightTime = timeHour >= 22 || timeHour < 6;
    if (isNightTime) {
        riskScore += 40;
        message = "⚠️ 此為夜間時段 (22:00-06:00)，區域人流較少，請特別注意安全！";
    }

    // 模擬：特定區域 (假設靠近模擬事故熱點 25.04, 121.5) 提高風險
    const hotspotLat = 25.04;
    const hotspotLon = 121.5;
    const distance = Math.sqrt(Math.pow(latitude - hotspotLat, 2) + Math.pow(longitude - hotspotLon, 2));

    if (distance < 0.1) {
        riskScore += 30;
        message = "🚨 靠近歷史事故/犯罪高發區！請提高警覺。";
    }

    // 確保分數不超過 100
    riskScore = Math.min(riskScore, 100);

    return {
        riskScore: riskScore,
        message: message,
        isHighRisk: riskScore >= 70 // 定義高風險閾值
    };
}


// --- 3. API 路由定義 ---

// Endpoint 1: 處理緊急警報觸發
// App 傳送插銷拔出或 AI 偵測到的危險事件
app.post('/api/alert', async (req, res) => {
    const { userId, latitude, longitude, contactNumber, triggerType } = req.body;

    if (!userId || !latitude || !longitude || !contactNumber || !triggerType) {
        return res.status(400).send({ success: false, message: '缺少必要的請求參數。' });
    }

    const now = admin.firestore.Timestamp.now();
    const timeHour = new Date(now.toDate()).getHours();
    const riskCheck = aiRiskPrediction(latitude, longitude, timeHour);

    try {
        const eventData = {
            userId,
            latitude,
            longitude,
            contactNumber,
            triggerType, // 例如: 'PIN_PULL' (插銷), 'AI_DETECT' (AI 偵測)
            timestamp: now,
            isCancelled: false,
            cancellationTime: null,
            riskScore: riskCheck.riskScore,
            riskMessage: riskCheck.message,
            status: 'PENDING_CONFIRMATION' // 等待 10 秒取消
        };

        // 1. 將事件寫入 Firestore
        const docRef = await db.collection('alerts').add(eventData);

        // 2. 模擬簡訊通知 (在 10 秒取消機制之後，通常會在 App 端處理 10 秒延遲，
        //    或者後端設置一個延遲任務，此處簡化為立即發送，但狀態為 PENDING)
        const smsMessage = `🚨緊急警報! SafeBuddy 用戶 (ID: ${userId}) 觸發了 ${triggerType} 警報。當前位置: https://maps.google.com/?q=${latitude},${longitude} 。請立即聯繫!`;
        sendSmsNotification(contactNumber, smsMessage, eventData);

        // 返回事件 ID 給 App，以便進行取消操作
        res.status(200).send({
            success: true,
            alertId: docRef.id,
            riskInfo: {
                riskScore: riskCheck.riskScore,
                riskMessage: riskCheck.message,
                isHighRisk: riskCheck.isHighRisk
            },
            message: '警報已記錄，緊急通知已送出 (或即將送出)。'
        });
    } catch (error) {
        console.error('寫入警報事件失敗:', error);
        res.status(500).send({ success: false, message: '伺服器內部錯誤，無法記錄警報。' });
    }
});

// Endpoint 2: 處理警報取消 (10 秒內按下「我沒事」)
app.post('/api/cancel', async (req, res) => {
    const { alertId } = req.body;

    if (!alertId) {
        return res.status(400).send({ success: false, message: '缺少 alertId 參數。' });
    }

    try {
        const alertRef = db.collection('alerts').doc(alertId);
        const alertDoc = await alertRef.get();

        if (!alertDoc.exists) {
            return res.status(404).send({ success: false, message: '找不到對應的警報事件。' });
        }

        const alertData = alertDoc.data();

        if (alertData.isCancelled) {
            return res.status(200).send({ success: true, message: '警報已於稍早取消。' });
        }

        // 1. 更新 Firestore 狀態為已取消
        await alertRef.update({
            isCancelled: true,
            cancellationTime: admin.firestore.Timestamp.now(),
            status: 'CANCELLED_SAFE'
        });

        // 2. 模擬發送「回報平安」簡訊
        const safeMessage = `✅ SafeBuddy 用戶 (ID: ${alertData.userId}) 已回報平安。原緊急警報已解除，請放心。`;
        sendSmsNotification(alertData.contactNumber, safeMessage, alertData);

        res.status(200).send({ success: true, message: '警報已成功取消並回報平安。' });

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


// 4. 啟動伺服器
app.listen(PORT, () => {
    console.log(`\n==========================================`);
    console.log(`SafeBuddy Mock 後端伺服器已啟動: http://localhost:${PORT}`);
    console.log(`==========================================`);
    console.log(`\n測試 API 端點 (使用 POST 請求):`);
    console.log(`- 警報觸發: /api/alert`);
    console.log(`- 警報取消: /api/cancel`);
    console.log(`- 風險檢查: /api/check-risk`);
});
