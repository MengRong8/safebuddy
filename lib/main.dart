// SafeBuddy Flutter App (主程式碼)
// 負責 UI 顯示、前端邏輯、以及與 Node.js 後端 API 溝通。
//
// ⚠️ 運行此程式碼前，請確認已在專案的 pubspec.yaml 中加入以下依賴：
// dependencies:
//   flutter:
//     sdk: flutter
//   http: ^1.2.1  <--- 需要此套件來發送 HTTP 請求給後端

import 'package:flutter/material.dart';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io' show Platform;
import 'package:window_manager/window_manager.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 桌面平台視窗設定
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    await windowManager.ensureInitialized();

    const windowOptions = WindowOptions(
      size: Size(414, 896), // iPhone 11 Pro Max 尺寸
      center: true, // 視窗置中
      backgroundColor: Colors.transparent,
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.normal,
      title: 'SafeBuddy 貼身保鑣',
      minimumSize: Size(375, 667), // 不能小於 iPhone SE
      maximumSize: Size(428, 926), // 不能大於 iPhone 14 Pro Max
    );

    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }

  runApp(const SafeBuddyApp());
}

class SafeBuddyApp extends StatelessWidget {
  const SafeBuddyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SafeBuddy',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const SafeBuddyHomePage(),
      debugShowCheckedModeBanner: false,
    );
  }
}

// --- 1. 常量與模擬資料 ---

// 您的 Node.js 後端服務位址
const String backendUrl = 'http://localhost:3000/api';
// ❌ 不要用 10.0.2.2（那是 Android 模擬器專用）
const String mockUserId = 'SAFEBUDDY_USER_123';
const String mockContactNumber = '0987654321';
const double mockLatitude = 25.0478; // 模擬當前位置 (台北車站)
const double mockLongitude = 121.5175;

// --- 2. 資料模型 ---

class RiskInfo {
  final int riskScore;
  final String message;
  final bool isHighRisk;

  RiskInfo({
    required this.riskScore,
    required this.message,
    required this.isHighRisk,
  });

  factory RiskInfo.fromJson(Map<String, dynamic> json) {
    return RiskInfo(
      riskScore: json['riskScore'] ?? 0,
      message: json['message'] ?? '未知風險資訊',
      isHighRisk: json['isHighRisk'] ?? false,
    );
  }
}

// --- 3. 介面主體 ---

class SafeBuddyHomePage extends StatefulWidget {
  const SafeBuddyHomePage({super.key});

  @override
  State<SafeBuddyHomePage> createState() => _SafeBuddyHomePageState();
}

class _SafeBuddyHomePageState extends State<SafeBuddyHomePage> {
  // 狀態變數
  String _bleStatus = '已連線';
  bool _isAlerting = false;
  int _countdown = 10;
  String? _currentAlertId;
  String _riskMessage = '您好！我是 SafeBuddy 小精靈，很高興為您服務。';
  String? _statusMessage;
  bool _isLoading = false;

  Timer? _timer;
  Timer? _bleSimulator;

  @override
  void initState() {
    super.initState();
    _checkRiskArea(); // App 啟動時先檢查風險
    _startBleSimulator(); // 模擬 BLE 連線狀態變化
  }

  @override
  void dispose() {
    _timer?.cancel();
    _bleSimulator?.cancel();
    super.dispose();
  }

  // --- 4. HTTP 服務 (與 Node.js 後端溝通) ---

  // 呼叫後端 API 檢查區域風險
  Future<void> _checkRiskArea() async {
    setState(() => _isLoading = true);
    _setStatusMessage('🔍 正在檢查當前位置的風險評估...');

    try {
      final response = await http
          .post(
            Uri.parse('$backendUrl/check-risk'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'latitude': mockLatitude,
              'longitude': mockLongitude,
            }),
          )
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final result = jsonDecode(utf8.decode(response.bodyBytes));
        final riskInfo = RiskInfo.fromJson(result);
        setState(() {
          _riskMessage = '${riskInfo.message} (分數: ${riskInfo.riskScore})';
          _setStatusMessage('✅ 風險檢查完成。');
        });
      } else {
        _handleApiError('風險檢查失敗: ${response.statusCode}');
      }
    } on TimeoutException {
      _handleApiError('連線超時，請檢查後端服務是否運行。');
    } catch (e) {
      _handleApiError('無法連線至後端伺服器 (請確認 Node.js 服務運行中)。');
      print('API Error: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // 倒數結束後，觸發後端警報
  Future<void> _triggerBackendAlert() async {
    setState(() => _isLoading = true);
    _setStatusMessage('📡 倒數結束，App 正在向後端回報緊急事件...');

    try {
      final response = await http
          .post(
            Uri.parse('$backendUrl/alert'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'userId': mockUserId,
              'latitude': mockLatitude,
              'longitude': mockLongitude,
              'contactNumber': mockContactNumber,
              'triggerType': 'PIN_PULL',
            }),
          )
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final result = jsonDecode(utf8.decode(response.bodyBytes));
        setState(() {
          _currentAlertId = result['alertId'];
          _setStatusMessage('✅ 緊急事件已回報後端！Alert ID: $_currentAlertId。簡訊已送出。');
        });
      } else {
        _handleApiError('緊急事件回報失敗: ${response.statusCode}');
      }
    } catch (e) {
      _handleApiError('無法連線至後端伺服器。');
      print('API Error: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // 取消警報
  Future<void> _cancelAlert() async {
    setState(() => _isLoading = true);
    _setStatusMessage('📡 App 正在回報平安，通知後端取消警報...');

    _timer?.cancel();
    setState(() {
      _isAlerting = false;
      _countdown = 10;
    });

    try {
      final response = await http
          .post(
            Uri.parse('$backendUrl/cancel'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'alertId': _currentAlertId ?? 'mock-id'}),
          )
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        setState(() {
          _currentAlertId = null;
          _setStatusMessage('✅ 警報已成功取消！已發送「回報平安」簡訊給聯絡人。');
        });
      } else {
        _handleApiError('取消警報失敗: ${response.statusCode}');
      }
    } catch (e) {
      _handleApiError('無法連線至後端伺服器。');
      print('API Error: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // --- 5. 前端邏輯與計時器 ---

  // 模擬收到裝置警報
  void _simulateAlert() {
    if (_isAlerting) return;

    setState(() {
      _isAlerting = true;
      _countdown = 10;
      _setStatusMessage('⚠️ 警報觸發！啟動 10 秒倒數，App 即將發送緊急通知。');
    });

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_countdown == 0) {
        timer.cancel();
        setState(() => _isAlerting = false);
        _triggerBackendAlert(); // 倒數結束，呼叫後端
      } else {
        setState(() {
          _countdown--;
        });
      }
    });
  }

  // 模擬 BLE 距離提醒
  void _startBleSimulator() {
    _bleSimulator = Timer.periodic(const Duration(seconds: 30), (timer) {
      setState(() {
        _bleStatus = (_bleStatus == '已連線') ? '未連線' : '已連線';
        if (_bleStatus == '未連線') {
          _setStatusMessage('❗ 警示：SafeBuddy 裝置未攜帶或超出距離 (50m)！');
        } else {
          _setStatusMessage('✅ 裝置連線恢復。');
        }
      });
    });
  }

  // 錯誤處理
  void _handleApiError(String message) {
    setState(() {
      _statusMessage = '❌ $message';
    });
  }

  // 設定狀態訊息，並在 5 秒後清除
  void _setStatusMessage(String message) {
    setState(() {
      _statusMessage = message;
    });
    Future.delayed(const Duration(seconds: 5), () {
      if (_statusMessage == message) {
        setState(() {
          _statusMessage = null;
        });
      }
    });
  }

  // --- 6. UI 建構 ---

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.indigo.shade50,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const Text(
                'SafeBuddy 貼身保鑣精靈',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Colors.indigo,
                ),
              ),
              const SizedBox(height: 20),

              // 裝置連線狀態卡片
              _buildDeviceStatusCard(),
              const SizedBox(height: 15),

              // 訊息/結果顯示
              if (_statusMessage != null) _buildStatusMessage(),
              const SizedBox(height: 15),

              // AI 小精靈與危險區域提醒
              _buildRiskPredictionCard(),
              const SizedBox(height: 20),

              // 警報倒數計時區塊
              if (_isAlerting)
                _buildAlertCountdownCard()
              else
                _buildSimulateAlertButton(),

              const SizedBox(height: 20),

              // 其他資訊/功能 (如電量、分享位置)
              _buildAdditionalInfo(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDeviceStatusCard() {
    final bool isConnected = _bleStatus == '已連線';
    return Card(
      elevation: 5,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: isConnected ? Colors.green.shade400 : Colors.red.shade400,
          width: 2,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Icon(
                  Icons.bluetooth_connected,
                  color:
                      isConnected ? Colors.green.shade700 : Colors.red.shade700,
                  size: 30,
                ),
                const SizedBox(width: 10),
                Text(
                  _bleStatus,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: isConnected
                        ? Colors.green.shade700
                        : Colors.red.shade700,
                  ),
                ),
              ],
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                const Text(
                  '電量顯示',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                Text(
                  isConnected ? '🔋 85%' : 'N/A',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: isConnected ? Colors.black : Colors.grey,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRiskPredictionCard() {
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        padding: const EdgeInsets.all(20.0),
        decoration: BoxDecoration(
          color: Colors.indigo.shade50,
          borderRadius: BorderRadius.circular(20),
          border: Border(
            left: BorderSide(color: Colors.indigo.shade400, width: 4),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('💡', style: TextStyle(fontSize: 24)),
                const SizedBox(width: 8),
                Text(
                  '小精靈提醒',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                    color: Colors.indigo.shade800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              _riskMessage,
              style: const TextStyle(fontSize: 14, color: Colors.black87),
            ),
            const SizedBox(height: 15),
            ElevatedButton(
              onPressed: _isLoading ? null : _checkRiskArea,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.indigo,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                minimumSize: const Size(double.infinity, 45),
                elevation: 5,
              ),
              child: _isLoading && !_isAlerting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Text('🧭 查看附近區域人流與風險'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAlertCountdownCard() {
    return Container(
      padding: const EdgeInsets.all(25.0),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(25),
        border: Border.all(color: Colors.red.shade600, width: 3),
        boxShadow: [
          BoxShadow(
            color: Colors.red.shade200,
            blurRadius: 10,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Column(
        children: [
          const Text(
            '🚨 緊急警報已觸發 🚨',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: Colors.red,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 20.0),
            child: Text(
              '$_countdown s',
              style: const TextStyle(
                fontSize: 56,
                fontWeight: FontWeight.w900,
                color: Colors.red,
              ),
            ),
          ),
          const Text(
            '將於倒數結束後自動發送簡訊給聯絡人！',
            style: TextStyle(fontSize: 14, color: Colors.red),
          ),
          const SizedBox(height: 15),
          ElevatedButton(
            onPressed: _isLoading ? null : _cancelAlert,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green.shade600,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(30),
              ),
              minimumSize: const Size(double.infinity, 55),
              elevation: 8,
            ),
            child: Text(
              _isLoading ? '處理中...' : '我沒事，取消警報',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSimulateAlertButton() {
    return ElevatedButton(
      onPressed: _isLoading ? null : _simulateAlert,
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.red.shade500,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        minimumSize: const Size(double.infinity, 60),
        elevation: 10,
        shadowColor: Colors.red.shade300,
      ),
      child: const Text(
        '模擬 SafeBuddy 警報觸發 (PIN_PULL)',
        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildStatusMessage() {
    final bool isError =
        _statusMessage!.contains('❌') || _statusMessage!.contains('無法');
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 15),
      decoration: BoxDecoration(
        color: isError ? Colors.red.shade100 : Colors.green.shade100,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isError ? Colors.red.shade300 : Colors.green.shade300,
        ),
      ),
      child: Text(
        _statusMessage!,
        style: TextStyle(
          color: isError ? Colors.red.shade700 : Colors.green.shade700,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildAdditionalInfo() {
    return Column(
      children: [
        const Divider(height: 30, thickness: 1, color: Colors.grey),
        ListTile(
          leading: const Icon(Icons.share, color: Colors.indigo),
          title: const Text('與聯絡人分享當前位置'),
          subtitle: Text('緯度: $mockLatitude, 經度: $mockLongitude'),
          trailing: const Icon(Icons.arrow_forward_ios, size: 16),
          onTap: () {
            _setStatusMessage('🌍 模擬分享位置服務... (功能待實作)');
          },
        ),
        ListTile(
          leading: const Icon(Icons.account_circle, color: Colors.indigo),
          title: const Text('使用者個人帳號'),
          subtitle: const Text('點擊查看通知設定與緊急聯絡人'),
          trailing: const Icon(Icons.arrow_forward_ios, size: 16),
          onTap: () {
            _setStatusMessage('👤 模擬進入帳號頁面... (功能待實作)');
          },
        ),
      ],
    );
  }
}
