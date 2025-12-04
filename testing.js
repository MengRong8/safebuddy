// SafeBuddy Twilio 簡訊測試 (Node.js 進階版)

const twilio = require("twilio");
require('dotenv').config();

const accountSid = process.env.TWILIO_ACCOUNT_SID;
const authToken = process.env.TWILIO_AUTH_TOKEN;
const fromNumber = process.env.TWILIO_PHONE_NUMBER;
const toNumber = process.env.RECIPIENT_PHONE_NUMBER;

// 檢查憑證
if (!accountSid || !authToken || !fromNumber || !toNumber) {
  console.error("❌ 錯誤：請確認 .env 檔案包含所有必要的 Twilio 憑證");
  process.exit(1);
}

const client = twilio(accountSid, authToken);

/**
 * 發送測試簡訊
 * @param {string} customMessage - 自訂訊息內容（可選）
 * @param {string} customRecipient - 自訂接收者（可選）
 */
async function sendTestMessage(customMessage = null, customRecipient = null) {
  const messageBody = customMessage || "SafeBuddy測試:Node.js正常";
  const recipient = customRecipient || toNumber;
  
  console.log(`\n--- 發送簡訊 ---`);
  console.log(`訊息內容: ${messageBody}`);
  console.log(`發送者: ${fromNumber}`);
  console.log(`接收者: ${recipient}`);
  console.log(`訊息長度: ${messageBody.length} 字元`);
  
  // 檢查訊息長度（試用帳號限制）
  const maxLength = 120;
  if (messageBody.length > maxLength) {
    console.warn(`⚠️  警告：訊息長度 (${messageBody.length}) 超過建議長度 (${maxLength})`);
  }
  
  try {
    const message = await client.messages.create({
      body: messageBody,
      from: fromNumber,
      to: recipient,
    });

    console.log(`\n✅ 簡訊已發送！`);
    console.log(`訊息 SID: ${message.sid}`);
    console.log(`狀態: ${message.status}`);
    console.log(`發送至: ${message.to}`);
    console.log(`價格: ${message.price || 'N/A'} ${message.priceUnit || ''}`);
    console.log(`------------------`);
    
    return { success: true, messageSid: message.sid };
    
  } catch (error) {
    console.error(`\n❌ 簡訊發送失敗:`);
    console.error(`錯誤訊息: ${error.message}`);
    console.error(`錯誤代碼: ${error.code || 'N/A'}`);
    console.error(`更多資訊: ${error.moreInfo || 'N/A'}`);
    console.error(`------------------`);
    
    return { success: false, error: error.message };
  }
}

// 主程式
async function main() {
  console.log("=== SafeBuddy Twilio 簡訊測試 (Node.js) ===");
  
  // 從命令列參數讀取自訂訊息
  const args = process.argv.slice(2);
  const customMessage = args[0];
  
  if (customMessage) {
    console.log(`使用自訂訊息: ${customMessage}`);
    await sendTestMessage(customMessage);
  } else {
    console.log(`使用預設訊息`);
    await sendTestMessage();
  }
  
  console.log("\n=== 測試完成 ===");
}

// 執行主程式
main().catch(error => {
  console.error("程式執行錯誤:", error);
  process.exit(1);
});