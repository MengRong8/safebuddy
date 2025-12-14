// lib/serial_service.dart

import 'dart:async';
import 'package:serial_port_win32/serial_port_win32.dart'; 
import 'dart:typed_data';
import 'dart:io' show Platform; 

class SerialService {
  final String portName;
  final int baudRate;
  
  SerialPort? _serialPort; 
  Timer? _readTimer; 
  
  // 專門用於通知連線狀態變化的 Stream
  final StreamController<bool> _connectionStatusController = StreamController.broadcast();
  Stream<bool> get connectionStatusStream => _connectionStatusController.stream;

  // 專門用於傳輸數據的 Stream
  final StreamController<String> _dataStreamController = StreamController.broadcast();
  Stream<String> get dataStream => _dataStreamController.stream;

  SerialService({required this.portName, required this.baudRate});

  // 啟動連線和監聽
  bool startListening() {
    // 1. 平台檢查
    if (!Platform.isWindows) {
      print('❌ Serial Service: Not running on Windows.');
      return false;
    }

    // 2. 清理舊的資源 (防止重複開啟)
    _closePortResources();

    try {
      // 3. 建立 SerialPort 實例
      _serialPort = SerialPort(
        portName,
        openNow: false, // ⚠️ 關鍵：先不要在這裡開啟，讓我們手動開啟以捕捉錯誤
        BaudRate: baudRate,
        ByteSize: 8,
        StopBits: 1,
        Parity: 0, 
      );
      
      // 4. 嘗試開啟埠口 (這裡是防止崩潰的關鍵)
      try {
        _serialPort!.open(); 
      } catch (e) {
        print('⚠️ Serial Port Connection Failed (Device might not be connected): $e');
        _connectionStatusController.add(false); // 通知 UI 連線失敗
        return false; // 優雅地返回失敗，不要崩潰
      }

      print('✅ Serial Port (Win32): Connected to $portName (Baud: $baudRate)');
      
      // 5. 連線成功，發送 true 狀態
      _connectionStatusController.add(true); 

      // 6. 啟動定時輪詢讀取 (Polling)
      _readTimer = Timer.periodic(const Duration(milliseconds: 50), (timer) async {
        // 檢查埠口是否意外關閉
        if (_serialPort == null || !_serialPort!.isOpened) {
          timer.cancel();
          print('⚠️ Serial Port unexpectedly closed.');
          _connectionStatusController.add(false); 
          return;
        }
        
        try {
          // 嘗試非阻塞讀取
          Uint8List data = await _serialPort!.readBytes(1024, timeout: Duration.zero); 
          
          if (data.isNotEmpty) {
            final line = String.fromCharCodes(data).trim();
            if (line.isNotEmpty) {
              // 發送數據到數據流
              _dataStreamController.add(line);
              
              // 🆕 收到數據，再次確認連線狀態為 true (心跳機制)
              if (!_connectionStatusController.isClosed) {
                _connectionStatusController.add(true); 
              }
            }
          }
        } catch (e) {
          print('❌ Error during serial read poll: $e');
          timer.cancel();
          _connectionStatusController.add(false); // 讀取錯誤視為斷線
        }
      });
      
      return true;

    } catch (e) {
      print('❌ Serial Port Initialization Error: $e');
      _serialPort = null;
      _connectionStatusController.add(false); 
      return false;
    }
  }

  // 內部私有方法：僅關閉埠口和計時器，不關閉 StreamController
  void _closePortResources() {
    _readTimer?.cancel();
    _readTimer = null;
    if (_serialPort != null) {
      if (_serialPort!.isOpened) {
        _serialPort!.close();
      }
      _serialPort = null;
    }
  }

  // 外部呼叫：停止監聽
  void stopListening() {
    print('Serial Port (Win32): Stopping listening...');
    _closePortResources();
    
    // 通知 UI 已斷線
    if (!_connectionStatusController.isClosed) {
      _connectionStatusController.add(false);
    }
    
    // 注意：我們故意不呼叫 StreamController.close()
    // 這樣使用者點擊「重試」時，這些 Stream 依然可用，不需要重新建立 Service 物件。
  }
  
  // 如果確定整個 App 要關閉了，可以呼叫這個
  void dispose() {
    stopListening();
    _connectionStatusController.close();
    _dataStreamController.close();
  }
}