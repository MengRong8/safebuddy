// SafeBuddy Flutter App (主程式碼)
// 負責 UI 顯示、前端邏輯、以及與 Node.js 後端 API 溝通。

import 'package:flutter/material.dart';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io' show Platform;
import 'package:window_manager/window_manager.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    await windowManager.ensureInitialized();

    const windowOptions = WindowOptions(
      size: Size(428, 926),
      center: true,
      backgroundColor: Colors.transparent,
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.normal,
      title: 'SafeBuddy',
      minimumSize: Size(375, 667),
      maximumSize: Size(428, 926),
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
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),
      home: const SafeBuddyHomePage(),
      debugShowCheckedModeBanner: false,
    );
  }
}

// --- 常量 ---
const String backendUrl = 'http://localhost:3000/api';
const String mockUserId = 'SAFEBUDDY_USER_123';
const String mockContactNumber = '0987654321';
const double mockLatitude = 25.0478;
const double mockLongitude = 121.5175;

// --- 資料模型 ---
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

// --- 主畫面 ---
class SafeBuddyHomePage extends StatefulWidget {
  const SafeBuddyHomePage({super.key});

  @override
  State<SafeBuddyHomePage> createState() => _SafeBuddyHomePageState();
}

class _SafeBuddyHomePageState extends State<SafeBuddyHomePage>
    with SingleTickerProviderStateMixin {
  String _bleStatus = '已連線';
  bool _isAlerting = false;
  int _countdown = 10;
  String? _currentAlertId;
  String _riskMessage = '';
  bool _showTopNotification = false;
  bool _showCenterDialog = false;
  bool _isLoading = false;

  Timer? _timer;
  Timer? _bleSimulator;
  AnimationController? _slideController;
  Animation<Offset>? _slideAnimation;

  @override
  void initState() {
    super.initState();
    _checkRiskArea();
    _startBleSimulator();

    // 上方通知滑動動畫
    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, -1),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _slideController!,
      curve: Curves.easeOut,
    ));
  }

  @override
  void dispose() {
    _timer?.cancel();
    _bleSimulator?.cancel();
    _slideController?.dispose();
    super.dispose();
  }

  // --- API 呼叫 ---
  Future<void> _checkRiskArea() async {
    setState(() => _isLoading = true);

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
          _riskMessage = riskInfo.message;
          if (riskInfo.isHighRisk) {
            _showTopNotificationBanner();
          }
        });
      }
    } catch (e) {
      print('API Error: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _triggerBackendAlert() async {
    setState(() => _isLoading = true);

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
        setState(() => _currentAlertId = result['alertId']);
      }
    } catch (e) {
      print('API Error: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _cancelAlert() async {
    setState(() => _isLoading = true);

    _timer?.cancel();
    setState(() {
      _isAlerting = false;
      _showCenterDialog = false;
      _countdown = 10;
    });

    try {
      await http
          .post(
            Uri.parse('$backendUrl/cancel'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'alertId': _currentAlertId ?? 'mock-id'}),
          )
          .timeout(const Duration(seconds: 5));

      setState(() => _currentAlertId = null);
    } catch (e) {
      print('API Error: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // --- 前端邏輯 ---
  void _simulateAlert() {
    if (_isAlerting) return;

    setState(() {
      _isAlerting = true;
      _showCenterDialog = true;
      _countdown = 10;
    });

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_countdown == 0) {
        timer.cancel();
        setState(() {
          _isAlerting = false;
          _showCenterDialog = false;
        });
        _triggerBackendAlert();
      } else {
        setState(() => _countdown--);
      }
    });
  }

  void _showTopNotificationBanner() {
    setState(() => _showTopNotification = true);
    _slideController?.forward();

    Future.delayed(const Duration(seconds: 5), () {
      _slideController?.reverse().then((_) {
        setState(() => _showTopNotification = false);
      });
    });
  }

  void _startBleSimulator() {
    _bleSimulator = Timer.periodic(const Duration(seconds: 30), (timer) {
      setState(() {
        _bleStatus = (_bleStatus == '已連線') ? '未連線' : '已連線';
      });
    });
  }

  // --- UI 建構 ---
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // 背景地圖區域（漸層模擬）
          _buildMapBackground(),

          // 右上角電量顯示
          _buildBatteryIndicator(),

          // 左下角地圖按鈕
          _buildMapButton(),

          // 底部使用者資訊卡片
          _buildUserInfoCard(),

          // 上方危險通知橫幅
          if (_showTopNotification) _buildTopNotification(),

          // 中間對話框（是否通知家人）
          if (_showCenterDialog) _buildCenterDialog(),
        ],
      ),
    );
  }

  // 背景地圖（漸層模擬）
  Widget _buildMapBackground() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.teal.shade100,
            Colors.teal.shade50,
            Colors.white,
          ],
        ),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.map,
              size: 120,
              color: Colors.teal.shade200,
            ),
            const SizedBox(height: 16),
            Text(
              '地圖顯示區域',
              style: TextStyle(
                fontSize: 18,
                color: Colors.teal.shade700,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '緯度: $mockLatitude',
              style: TextStyle(fontSize: 12, color: Colors.teal.shade600),
            ),
            Text(
              '經度: $mockLongitude',
              style: TextStyle(fontSize: 12, color: Colors.teal.shade600),
            ),
          ],
        ),
      ),
    );
  }

  // 右上角電量顯示
  Widget _buildBatteryIndicator() {
    final bool isConnected = _bleStatus == '已連線';
    return Positioned(
      top: 50,
      right: 16,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 8,
              spreadRadius: 1,
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isConnected
                  ? Icons.bluetooth_connected
                  : Icons.bluetooth_disabled,
              color: isConnected ? Colors.green : Colors.red,
              size: 18,
            ),
            const SizedBox(width: 6),
            Text(
              isConnected ? '🔋 85%' : '未連線',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: isConnected ? Colors.black : Colors.red,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 左下角地圖按鈕
  Widget _buildMapButton() {
    return Positioned(
      bottom: 280,
      left: 16,
      child: Column(
        children: [
          FloatingActionButton(
            heroTag: 'map',
            onPressed: _checkRiskArea,
            backgroundColor: Colors.white,
            child: _isLoading
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.teal,
                    ),
                  )
                : const Icon(Icons.location_searching, color: Colors.teal),
          ),
          const SizedBox(height: 12),
          FloatingActionButton(
            heroTag: 'alert',
            onPressed: _simulateAlert,
            backgroundColor: Colors.red.shade500,
            child: const Icon(Icons.warning_amber_rounded, color: Colors.white),
          ),
        ],
      ),
    );
  }

  // 底部使用者資訊卡片
  Widget _buildUserInfoCard() {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 10,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 30,
                  backgroundColor: Colors.teal.shade100,
                  child: const Icon(Icons.person, size: 35, color: Colors.teal),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Adventurer Name',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '使用者 ID: $mockUserId',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.teal.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.teal.shade200),
              ),
              child: Row(
                children: [
                  const Text('💡', style: TextStyle(fontSize: 24)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _riskMessage.isEmpty
                          ? '您好！我是 SafeBuddy 小精靈。點擊左側按鈕檢查周邊風險。'
                          : _riskMessage,
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {},
                    icon: const Icon(Icons.share, size: 18),
                    label: const Text('分享位置'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.teal,
                      side: BorderSide(color: Colors.teal.shade300),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {},
                    icon: const Icon(Icons.settings, size: 18),
                    label: const Text('設定'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.teal,
                      side: BorderSide(color: Colors.teal.shade300),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // 上方危險通知橫幅（從上往下滑出）
  Widget _buildTopNotification() {
    return SlideTransition(
      position: _slideAnimation!,
      child: Positioned(
        top: 0,
        left: 0,
        right: 0,
        child: Container(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.red.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.red.shade400, width: 2),
            boxShadow: [
              BoxShadow(
                color: Colors.red.shade200,
                blurRadius: 10,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Row(
            children: [
              Icon(Icons.warning_amber_rounded,
                  color: Colors.red.shade700, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '該地區 22:00 過後人流較少',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.red.shade900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '請注意安全或提伴前行',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.red.shade700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 中間對話框（是否通知家人）
  Widget _buildCenterDialog() {
    return Container(
      color: Colors.black.withOpacity(0.5),
      child: Center(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 30),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.3),
                blurRadius: 20,
                spreadRadius: 5,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.warning_amber_rounded,
                  size: 50,
                  color: Colors.red.shade700,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                '緊急警報倒數',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.red.shade900,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                '$_countdown 秒',
                style: TextStyle(
                  fontSize: 56,
                  fontWeight: FontWeight.w900,
                  color: Colors.red.shade700,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                '倒數結束後將通知緊急聯絡人',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _cancelAlert,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green.shade500,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 5,
                  ),
                  child: const Text(
                    '我沒事',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
