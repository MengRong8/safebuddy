# Download the helper library from https://www.twilio.com/docs/python/install
import os
from twilio.rest import Client
from dotenv import load_dotenv

# 載入 .env 檔案
load_dotenv()

# 從環境變數讀取憑證
account_sid = os.environ.get("TWILIO_ACCOUNT_SID")
auth_token = os.environ.get("TWILIO_AUTH_TOKEN")
from_number = os.environ.get("TWILIO_PHONE_NUMBER")
to_number = os.environ.get("RECIPIENT_PHONE_NUMBER")

# 檢查憑證是否載入
if not all([account_sid, auth_token, from_number, to_number]):
    raise ValueError("請確認 .env 檔案包含所有必要的 Twilio 憑證")

# 建立 Twilio 客戶端
client = Client(account_sid, auth_token)

# 發送簡訊
try:
    message = client.messages.create(
        body="SafeBuddy 測試訊息：Python 版本運作正常！",
        from_=from_number,
        to=to_number,
    )
    
    print(f"簡訊已發送！")
    print(f"訊息 SID: {message.sid}")
    print(f"狀態: {message.status}")
    print(f"發送至: {message.to}")
    
except Exception as e:
    print(f" 簡訊發送失敗: {e}")