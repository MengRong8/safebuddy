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
  
  final StreamController<bool> _connectionStatusController = StreamController.broadcast();
  Stream<bool> get connectionStatusStream => _connectionStatusController.stream;

  final StreamController<String> _dataStreamController = StreamController.broadcast();
  Stream<String> get dataStream => _dataStreamController.stream;

  SerialService({required this.portName, required this.baudRate});

  // 🆕 新增：發送指令給 Arduino
  void sendCommand(String command) {
    if (_serialPort != null && _serialPort!.isOpened) {
      try {
        // 將字串轉為 UTF-8 bytes 並發送
        // 使用 writeBytesFromString 是最簡單的方式
        _serialPort!.writeBytesFromString(
          command, 
          includeZeroTerminator: false
        );
        print('Sent to Arduino: $command');
      } catch (e) {
        print('Failed to send command: $e');
      }
    }
  }

  bool startListening() {
    if (!Platform.isWindows) {
      print('Serial Service: Not running on Windows.');
      return false;
    }

    _closePortResources();

    try {
      _serialPort = SerialPort(
        portName,
        openNow: false, 
        BaudRate: baudRate,
        ByteSize: 8,
        StopBits: 1,
        Parity: 0, 
      );
      
      try {
        _serialPort!.open(); 
      } catch (e) {
        print('⚠️ Connection Failed: $e');
        _connectionStatusController.add(false); 
        return false; 
      }

      print('✅ Connected to $portName');
      _connectionStatusController.add(true); 

      _readTimer = Timer.periodic(const Duration(milliseconds: 50), (timer) async {
        if (_serialPort == null || !_serialPort!.isOpened) {
          timer.cancel();
          _connectionStatusController.add(false); 
          return;
        }
        
        try {
          Uint8List data = await _serialPort!.readBytes(1024, timeout: Duration.zero); 
          if (data.isNotEmpty) {
            final line = String.fromCharCodes(data).trim();
            if (line.isNotEmpty) {
              _dataStreamController.add(line);
              if (!_connectionStatusController.isClosed) {
                _connectionStatusController.add(true); 
              }
            }
          }
        } catch (e) {
          timer.cancel();
          _connectionStatusController.add(false); 
        }
      });
      return true;
    } catch (e) {
      _serialPort = null;
      _connectionStatusController.add(false); 
      return false;
    }
  }

  void _closePortResources() {
    _readTimer?.cancel();
    _readTimer = null;
    if (_serialPort != null && _serialPort!.isOpened) {
      _serialPort!.close();
    }
    _serialPort = null;
  }

  void stopListening() {
    print('Stopping serial service...');
    _closePortResources();
    if (!_connectionStatusController.isClosed) {
      _connectionStatusController.add(false);
    }
  }
  
  void dispose() {
    stopListening();
    _connectionStatusController.close();
    _dataStreamController.close();
  }
}