import 'dart:async';
import 'dart:convert'; // For jsonDecode
import 'package:http/http.dart' as http; // You need to add http to pubspec.yaml

class HttpService {
  // The IP address of your ESP32 (e.g., "192.168.0.105")
  final String espIp;
  
  Timer? _pollingTimer;
  
  // --- STREAMS (Identical to SerialService for compatibility) ---
  final StreamController<bool> _connectionStatusController = StreamController.broadcast();
  Stream<bool> get connectionStatusStream => _connectionStatusController.stream;

  final StreamController<String> _dataStreamController = StreamController.broadcast();
  Stream<String> get dataStream => _dataStreamController.stream;

  HttpService({required this.espIp});

  // 🆕 Send Command (Equivalent to writeBytesFromString)
  // Sends GET request to: http://<IP>/set?cmd=<command>
  Future<void> sendCommand(String command) async {
    try {
      final uri = Uri.parse('http://$espIp/set?cmd=$command');
      print('📤 Sending HTTP: $uri');
      
      // We don't need to wait for the result to block UI, but we await to catch errors
      await http.get(uri).timeout(const Duration(seconds: 2));
      
    } catch (e) {
      print('❌ Failed to send HTTP command: $e');
    }
  }

  // 🆕 Start Polling (Equivalent to startListening)
  // Instead of listening to a port, we ask the ESP32 status every 500ms
  bool startPolling() {
    print('🌐 HTTP Service: Start polling $espIp...');
    
    // Stop any existing timer first
    stopPolling();

    // Notify UI that we are "attempting" to connect
    // In HTTP, we don't know we are connected until the first request succeeds
    
    _pollingTimer = Timer.periodic(const Duration(milliseconds: 500), (timer) async {
      try {
        // 1. Ask ESP32 for status
        final response = await http.get(Uri.parse('http://$espIp/status'))
            .timeout(const Duration(seconds: 2)); // Short timeout is crucial

        if (response.statusCode == 200) {
          // ✅ Connection is good
          if (!_connectionStatusController.isClosed) {
            _connectionStatusController.add(true); 
          }

          // 2. Parse the JSON response
          // Expected JSON: {"trigger": true, "cancel": false}
          final Map<String, dynamic> data = jsonDecode(response.body);
          
          // 3. Map JSON back to the strings your App expects
          if (data['trigger'] == true) {
            _dataStreamController.add('pressed'); // Simulate "pressed" message
          }
          
          if (data['cancel'] == true) {
            _dataStreamController.add('stopped'); // Simulate "stopped" message
          }
          
        } else {
          // Server reachable but gave error (e.g. 404 or 500)
           _connectionStatusController.add(false);
        }
      } catch (e) {
        // ❌ Timeout or Network Unreachable
        // print('❌ HTTP Polling Error: $e'); // Uncomment for debugging
        if (!_connectionStatusController.isClosed) {
           _connectionStatusController.add(false);
        }
      }
    });

    return true; // Always returns true because "starting" the timer never fails
  }

  void stopPolling() {
    _pollingTimer?.cancel();
    _pollingTimer = null;
    if (!_connectionStatusController.isClosed) {
      _connectionStatusController.add(false);
    }
  }
  
  void dispose() {
    stopPolling();
    _connectionStatusController.close();
    _dataStreamController.close();
  }
}