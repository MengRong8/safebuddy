import 'package:dart_serial_port/dart_serial_port.dart';
import 'dart:async';

// 定義一個回傳型別，用於通知外部接收到的訊息
typedef SerialDataCallback = void Function(String data);

class SerialService {
  final String portName;
  final int baudRate;
  
  SerialPort? _serialPort;
  SerialPortReader? _serialPortReader;
  
  // 讓外部可以訂閱 (Subscribe) 接收到的資料
  final StreamController<String> _dataStreamController = StreamController.broadcast();
  Stream<String> get dataStream => _dataStreamController.stream;

  SerialService({required this.portName, required this.baudRate});

  // 1. 初始化並啟動監聽
  bool startListening() {
    // 檢查埠是否可用 (可選)
    final availablePorts = SerialPort.availablePorts;
    if (!availablePorts.contains(portName)) {
      print('Serial Port $portName not found.');
      return false;
    }

    _serialPort = SerialPort(portName);

    // 設定配置參數
    _serialPort!.config.baudRate = baudRate;
    _serialPort!.config.bits = 8;
    _serialPort!.config.stopBits = 1;
    _serialPort!.config.parity = SerialPortParity.none;
    
    // 嘗試開啟串列埠
    try {
      bool opened = _serialPort!.openRead(); 
      if (!opened) {
        print('Serial Port: Could not open $portName.');
        return false;
      }

      print('Serial Port: Connected to $portName (Baud: $baudRate)');

      _serialPortReader = SerialPortReader(_serialPort!, timeout: 0);

      // 監聽數據流
      _serialPortReader!.stream.listen((data) {
        final line = String.fromCharCodes(data).trim();

        if (line.isNotEmpty) {
          // 將接收到的數據發佈到 Stream 中，供外部訂閱
          _dataStreamController.add(line);
        }
      });
      
      return true;

    } on SerialPortError catch (e) {
      print('Serial Port Error on open: ${e.message}');
      return false;
    } catch (e) {
      print('Unknown Serial Port Error: $e');
      return false;
    }
  }

  // 2. 停止並關閉資源
  void stopListening() {
    print('Serial Port: Closing connection...');
    _dataStreamController.close();
    _serialPortReader?.close();
    _serialPort?.close();
  }
}