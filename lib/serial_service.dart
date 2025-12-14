// lib/serial_service.dart (使用 serial_port_win32 - 最終修正為直接傳參)

import 'dart:async';
import 'package:serial_port_win32/serial_port_win32.dart'; 
import 'dart:typed_data';
import 'dart:io' show Platform; 

class SerialService {
  final String portName;
  final int baudRate;
  
  SerialPort? _serialPort; 
  Timer? _readTimer; 

  final StreamController<String> _dataStreamController = StreamController.broadcast();
  Stream<String> get dataStream => _dataStreamController.stream;

  SerialService({required this.portName, required this.baudRate});

  // 啟動連線和監聽
  bool startListening() {
    if (_serialPort != null) {
      stopListening();
    }
    
    if (!Platform.isWindows) {
      print('❌ Serial Service: serial_port_win32 is only supported on Windows.');
      return false;
    }
    
    try {
      // 1. 修正建構函式：直接傳遞 BaudRate、ByteSize、StopBits、Parity 等參數
      _serialPort = SerialPort(
        portName,
        openNow: false, 
        // ⚠️ 根據您提供的文件，使用大寫開頭的具名參數
        BaudRate: baudRate,
        ByteSize: 8, // Data Bits
        StopBits: 1, // Stop Bits
        Parity: 0,   // 0 = NONE (使用整數值，因為 Enum 可能不相容)
        // ❌ 移除 config: PortConfig(...) 和 setCommTimeouts
      );
      
      _serialPort!.open(); 
      print('✅ Serial Port (Win32): Connected to $portName (Baud: $baudRate)');

      // 2. 啟動定時輪詢 (保持這個邏輯，因為 Stream 屬性可能有問題)
      _readTimer = Timer.periodic(const Duration(milliseconds: 50), (timer) async {
        if (!_serialPort!.isOpened) {
          timer.cancel();
          return;
        }

        try {
          // 使用 readBytes 讀取緩衝區中所有可用的數據
          // 設置 timeout: Duration.zero 確保是非阻塞讀取
          // 嘗試讀取最多 1024 bytes
          Uint8List data = await _serialPort!.readBytes(1024, timeout: Duration.zero); 
          
          if (data.isNotEmpty) {
            // 將數據轉換為字串並發佈
            final line = String.fromCharCodes(data).trim();
            if (line.isNotEmpty) {
              _dataStreamController.add(line);
            }
          }
        } catch (e) {
          // 讀取錯誤，取消定時器
          print('⚠️ Error during serial read poll: $e');
          // 這裡不應自動關閉，讓錯誤傳播，直到應用程式或外部邏輯決定關閉
        }
      });
      
      return true;

    } catch (e) {
      print('❌ Serial Port Error during open/config: $e');
      _serialPort = null;
      return false;
    }
  }

  // 停止並釋放資源
  void stopListening() {
    print('Serial Port (Win32): Closing connection...');
    _readTimer?.cancel(); 
    _dataStreamController.close(); 
    _serialPort?.close(); 
    _serialPort = null;
  }
}