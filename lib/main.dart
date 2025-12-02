// SafeBuddy Flutter App (主程式碼)
// 負責 UI 顯示、前端邏輯、以及與 Node.js 後端 API 溝通。

import 'package:flutter/material.dart';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io' show Platform;
import 'package:window_manager/window_manager.dart';
import 'package:latlong2/latlong.dart';
import 'map_page.dart'; // 加在檔案最上方

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    await windowManager.ensureInitialized();

    const windowOptions = WindowOptions(
      size: Size(428, 840),
      center: true,
      backgroundColor: Colors.transparent,
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.normal,
      title: 'SafeBuddy',
      minimumSize: Size(375, 667),
      maximumSize: Size(428, 840),
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
    with TickerProviderStateMixin {
  String _bleStatus = '已連線';
  bool _isAlerting = false;
  int _countdown = 10;
  String? _currentAlertId;
  String _riskMessage = '';
  bool _showTopNotification = false;
  bool _showCenterDialog = false;
  bool _isLoading = false;
  int _batteryLevel = 85;
  bool _hasShownLowBatteryWarning = false;

  //  新增這三行
  LatLng _currentPosition = const LatLng(mockLatitude, mockLongitude);
  bool _isInDangerZone = false;
  String _dangerZoneMessage = '';

  Timer? _timer;
  Timer? _bleSimulator;
  Timer? _batterySimulator; // 新增：電量模擬器
  AnimationController? _slideController;
  Animation<Offset>? _slideAnimation;

  // 對話框動畫控制器
  AnimationController? _dialogController;
  Animation<double>? _scaleAnimation;
  Animation<double>? _opacityAnimation;

  //  新增：打字機效果相關變數
  String _displayedMessage = ''; // 當前顯示的文字
  String _fullMessage = ''; // 完整訊息
  Timer? _typingTimer; // 打字計時器
  int _charIndex = 0; // 當前字元索引
  bool _isTyping = false; // 是否正在打字

  // ✅ 新增：記錄上次訊息切換時間
  DateTime? _lastMessageChangeTime;

  @override
  void initState() {
    super.initState();

    // 只在夜間（22:00-06:00）才自動檢查
    final now = DateTime.now();
    if (now.hour >= 22 || now.hour < 6) {
      _checkRiskArea();
    }
    _startBleSimulator();
    _startBatterySimulator(); // 新增：啟動電量模擬器

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

    // 對話框泡泡彈出動畫
    _dialogController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    _scaleAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _dialogController!,
      curve: Curves.elasticOut,
    ));

    _opacityAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _dialogController!,
      curve: Curves.easeIn,
    ));

    //  初始化預設訊息
    _startTypingEffect('您好！我是 SafeBuddy 小精靈。點擊左側按鈕檢查周邊風險。');
  }

  @override
  void dispose() {
    _timer?.cancel();
    _bleSimulator?.cancel();
    _batterySimulator?.cancel();
    _slideController?.dispose();
    _dialogController?.dispose();
    _typingTimer?.cancel(); //  釋放打字計時器

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

        //  啟動打字機效果
        _startTypingEffect(riskInfo.message);
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

    // 播放縮小消失動畫
    _dialogController?.reverse();

    await Future.delayed(const Duration(milliseconds: 300));

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

  // 新增：電量模擬器（每 10 秒降低 1%，測試用）
  void _startBatterySimulator() {
    _batterySimulator = Timer.periodic(const Duration(seconds: 10), (timer) {
      setState(() {
        if (_batteryLevel > 0) {
          _batteryLevel--;

          // 當電量低於 20% 且尚未提示時，顯示充電提示
          if (_batteryLevel <= 20 && !_hasShownLowBatteryWarning) {
            _showLowBatteryWarning();
            _hasShownLowBatteryWarning = true;
          }

          // 當電量回到 21% 以上，重置提示標記
          if (_batteryLevel > 20) {
            _hasShownLowBatteryWarning = false;
          }
        }
      });
    });
  }

  // 新增：顯示低電量警告
  void _showLowBatteryWarning() {
    setState(() {
      _riskMessage = '記得充電喔！電量剩餘 $_batteryLevel%';
    });

    //  啟動打字機效果
    _startTypingEffect('記得充電喔！電量剩餘 $_batteryLevel%');

    // 可選：發出聲音或震動提示
    print('⚠️ 低電量警告：電量剩餘 $_batteryLevel%');
  }

  //  新增：打字機效果方法
  void _startTypingEffect(String message) {
    // 如果訊息相同，不重複打字
    // if (_fullMessage == message && !_isTyping) {
    //   return;
    // }

    // 取消舊的打字動畫
    _typingTimer?.cancel();

    setState(() {
      _fullMessage = message;
      _displayedMessage = '';
      _charIndex = 0;
      _isTyping = true;
    });

    // 開始打字動畫（每 50 毫秒顯示一個字元）
    _typingTimer = Timer.periodic(
      const Duration(milliseconds: 50), //  打字速度（可調整）
      (timer) {
        if (_charIndex < _fullMessage.length) {
          setState(() {
            _displayedMessage += _fullMessage[_charIndex];
            _charIndex++;
          });
        } else {
          // 打字完成
          timer.cancel();
          setState(() {
            _isTyping = false;
          });
        }
      },
    );
  }

  // --- 前端邏輯 ---
  void _simulateAlert() {
    if (_isAlerting) return;

    setState(() {
      _isAlerting = true;
      _showCenterDialog = true;
      _countdown = 10;
    });

    // 播放對話框彈出動畫
    _dialogController?.forward();

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_countdown == 0) {
        timer.cancel();
        _dialogController?.reverse();
        Future.delayed(const Duration(milliseconds: 300), () {
          setState(() {
            _isAlerting = false;
            _showCenterDialog = false;
          });
          _triggerBackendAlert();
        });
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
          _buildMapBackground(),
          _buildBatteryIndicator(),
          _buildMapButton(),
          _buildUserInfoCard(),
          _buildSafeBuddyCharacter(), // 小精靈角色
          _buildSafeBuddyDialog(), // 小精靈對話框
          // _buildMapOpenButton(), //  新增：獨立的地圖開啟按鈕
          if (_showTopNotification) _buildTopNotification(),
          if (_showCenterDialog) _buildCenterDialog(),
        ],
      ),
    );
  }

  // 背景地圖
  Widget _buildMapBackground() {
    return Stack(
      fit: StackFit.expand,
      children: [
        // 背景 GIF（自動播放）
        Image.asset(
          'assets/image/background.gif',
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            // GIF 載入失敗時顯示靜態圖片
            return Image.asset(
              'assets/image/background.jpg',
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) {
                // 靜態圖也失敗時顯示漸層
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
                );
              },
            );
          },
        ),

        // 半透明遮罩
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withValues(alpha: 0.2),
                Colors.transparent,
                Colors.white.withValues(alpha: 0.3),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // 右上角電量顯示
  Widget _buildBatteryIndicator() {
    final bool isConnected = _bleStatus == '已連線';
    final bool isLowBattery = _batteryLevel <= 20;

    return Positioned(
      top: 140, //  調整避開使用者卡片（原本 80）
      right: 10,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color:
              const Color.fromARGB(255, 153, 168, 153).withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(20),
          border: isLowBattery ? Border.all(color: Colors.red, width: 2) : null,
          boxShadow: [
            BoxShadow(
              color: isLowBattery
                  ? Colors.red.withValues(alpha: 0.3)
                  : Colors.black.withValues(alpha: 0.1),
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
              isConnected ? '🔋 $_batteryLevel%' : '未連線',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: isLowBattery
                    ? Colors.red
                    : (isConnected ? Colors.black : Colors.red),
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
      bottom: 150,
      left: 16,
      child: Column(
        children: [
          //  改為開啟地圖
          FloatingActionButton(
            heroTag: 'map',
            onPressed: () async {
              //  開啟地圖並接收返回資料
              final result = await Navigator.push<Map<String, dynamic>>(
                context,
                MaterialPageRoute(
                  builder: (context) => MapPage(
                    initialPosition: _currentPosition,
                  ),
                ),
              );

              //  處理返回資料
              if (result != null) {
                setState(() {
                  _currentPosition = result['position'] as LatLng;
                  _isInDangerZone = result['isInDangerZone'] as bool? ?? false;
                  _dangerZoneMessage = result['message'] as String? ?? '';

                  if (_isInDangerZone) {
                    _riskMessage = _dangerZoneMessage;
                    _showTopNotificationBanner();
                    _startTypingEffect(_dangerZoneMessage);
                  } else {
                    _riskMessage = '';
                    _startTypingEffect('目前位置安全，請放心！');
                  }
                });
              }
            },
            backgroundColor: Colors.white,
            child: const Icon(Icons.map_outlined, color: Colors.teal),
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

  // 使用者資訊卡片
  Widget _buildUserInfoCard() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: const EdgeInsets.fromLTRB(
            20, 15, 20, 16), //  減少上方 padding（原本 50, 20）
        decoration: BoxDecoration(
          color:
              const Color.fromARGB(255, 153, 168, 153).withValues(alpha: 0.8),
          borderRadius: const BorderRadius.vertical(
            bottom: Radius.circular(30),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
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
                  radius: 28, //  稍微縮小（原本 30）
                  backgroundColor: Colors.teal.shade100,
                  child: const Icon(Icons.person, size: 32, color: Colors.teal),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Adventurer Name',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '使用者 ID: $mockUserId',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10), //  減少間距（原本 12）
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {},
                    icon: const Icon(Icons.share, size: 16),
                    label: const Text('分享位置', style: TextStyle(fontSize: 12)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.teal,
                      side: BorderSide(color: Colors.teal.shade300),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {},
                    icon: const Icon(Icons.settings, size: 16),
                    label: const Text('設定', style: TextStyle(fontSize: 12)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.teal,
                      side: BorderSide(color: Colors.teal.shade300),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 10),
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

  // 小精靈角色
  Widget _buildSafeBuddyCharacter() {
    return Positioned(
      left: 0,
      right: 0,
      top: 460,
      child: Center(
        child: Container(
          width: 300,
          height: 300,
          child: Image.asset(
            'assets/image/fairy_map.gif',
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) {
              // GIF 載入失敗時顯示靜態圖片
              return Image.asset(
                'assets/image/fairy_map.png',
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) {
                  // 都失敗時顯示圖示
                  return Icon(
                    Icons.smart_toy,
                    size: 170,
                    color: Colors.teal.shade700,
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }

  //  對話框
  Widget _buildSafeBuddyDialog() {
    // 決定要顯示的訊息類型
    String targetMessage;
    if (_batteryLevel <= 20) {
      targetMessage = '記得充電喔！電量剩餘 $_batteryLevel%';
    } else if (_riskMessage.isNotEmpty) {
      targetMessage = _riskMessage;
    } else {
      targetMessage = '您好！我是你的專屬 SafeBuddy 小精靈。';
    }

    // ✅ 當訊息變更時，檢查是否需要延遲
    if (_fullMessage != targetMessage && !_isTyping) {
      final now = DateTime.now();

      // ✅ 檢查距離上次切換是否超過 3 秒
      if (_lastMessageChangeTime != null) {
        final timeSinceLastChange =
            now.difference(_lastMessageChangeTime!).inSeconds;

        if (timeSinceLastChange < 3) {
          // ✅ 如果間隔不足 3 秒，延遲執行
          final remainingTime = 3 - timeSinceLastChange;
          print('⏳ 訊息切換延遲 $remainingTime 秒'); // 除錯訊息

          Future.delayed(Duration(seconds: remainingTime), () {
            if (mounted && _fullMessage != targetMessage && !_isTyping) {
              print('✅ 延遲後切換訊息: $targetMessage'); // 除錯訊息
              setState(() {
                _lastMessageChangeTime = DateTime.now();
              });
              _startTypingEffect(targetMessage);
            }
          });
        } else {
          // ✅ 如果間隔超過 3 秒，立即執行
          print('✅ 立即切換訊息: $targetMessage'); // 除錯訊息
          WidgetsBinding.instance.addPostFrameCallback((_) {
            setState(() {
              _lastMessageChangeTime = DateTime.now();
            });
            _startTypingEffect(targetMessage);
          });
        }
      } else {
        // ✅ 第一次顯示訊息，立即執行
        print('✅ 首次顯示訊息: $targetMessage'); // 除錯訊息
        WidgetsBinding.instance.addPostFrameCallback((_) {
          setState(() {
            _lastMessageChangeTime = DateTime.now();
          });
          _startTypingEffect(targetMessage);
        });
      }
    }

    return Positioned(
      right: 16,
      top: 320,
      child: Container(
        width: 220,
        height: 110,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.8),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: _batteryLevel <= 20
                ? const Color.fromARGB(255, 115, 229, 159)
                : (_isInDangerZone
                    ? Colors.red.shade300
                    : Colors.teal.shade300),
            width: 2.5,
          ),
          boxShadow: [
            BoxShadow(
              color: _batteryLevel <= 20
                  ? const Color.fromARGB(255, 59, 108, 75)
                      .withValues(alpha: 0.25)
                  : (_isInDangerZone
                      ? Colors.red.withValues(alpha: 0.25)
                      : Colors.teal.withValues(alpha: 0.2)),
              blurRadius: 15,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Center(
          child: SingleChildScrollView(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    _displayedMessage,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      color: _batteryLevel <= 20
                          ? const Color.fromARGB(255, 38, 119, 88)
                          : (_isInDangerZone
                              ? Colors.red.shade900
                              : Colors.grey.shade800),
                      height: 1.4,
                      fontWeight: _batteryLevel <= 20
                          ? FontWeight.bold
                          : (_isInDangerZone
                              ? FontWeight.bold
                              : FontWeight.w500),
                    ),
                  ),
                ),
                if (_isTyping)
                  Container(
                    margin: const EdgeInsets.only(left: 2),
                    child: _BlinkingCursor(),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // 上方危險通知橫幅
  Widget _buildTopNotification() {
    return SlideTransition(
      position: _slideAnimation!,
      child: Positioned(
        top: 165,
        left: 16,
        right: 16,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.red.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.red.shade400, width: 2),
            boxShadow: [
              BoxShadow(
                color: Colors.red.shade200,
                blurRadius: 8,
                spreadRadius: 1,
              ),
            ],
          ),
          child: Row(
            children: [
              Icon(
                Icons.warning_amber_rounded,
                color: Colors.red.shade700,
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '該地區 22:00 過後人流較少，請注意安全或提伴前行',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.red.shade900,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 中間對話框（綠色半透明 + 泡泡彈出動畫）
  Widget _buildCenterDialog() {
    return AnimatedBuilder(
      animation: _dialogController!,
      builder: (context, child) {
        return Container(
          color: Colors.black.withValues(alpha: 0.5 * _opacityAnimation!.value),
          child: Center(
            child: Transform.scale(
              scale: _scaleAnimation!.value,
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 30),
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Colors.teal.shade300.withValues(alpha: 0.85),
                      Colors.teal.shade400.withValues(alpha: 0.9),
                      Colors.green.shade400.withValues(alpha: 0.85),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.5),
                    width: 3,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.teal.shade700.withValues(alpha: 0.4),
                      blurRadius: 30,
                      spreadRadius: 5,
                    ),
                    BoxShadow(
                      color: Colors.white.withValues(alpha: 0.2),
                      blurRadius: 15,
                      spreadRadius: -5,
                      offset: const Offset(-5, -5),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 動態脈動圓圈圖示
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.3),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.white.withValues(alpha: 0.5),
                            blurRadius: 20,
                            spreadRadius: 5,
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.warning_amber_rounded,
                        size: 60,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 24),

                    // 標題
                    Text(
                      '緊急警報倒數',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        shadows: [
                          Shadow(
                            color: Colors.black.withValues(alpha: 0.3),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // 倒數數字（帶光暈效果）
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 40,
                        vertical: 20,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.25),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.4),
                          width: 2,
                        ),
                      ),
                      child: Text(
                        '$_countdown',
                        style: TextStyle(
                          fontSize: 72,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                          shadows: [
                            Shadow(
                              color: Colors.teal.shade700,
                              blurRadius: 15,
                            ),
                            const Shadow(
                              color: Colors.white,
                              blurRadius: 30,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // 秒字
                    Text(
                      '秒',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                        color: Colors.white.withValues(alpha: 0.9),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // 說明文字
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text(
                        '倒數結束後將通知緊急聯絡人',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.white,
                          fontWeight: FontWeight.w500,
                          height: 1.4,
                        ),
                      ),
                    ),
                    const SizedBox(height: 28),

                    // 我沒事按鈕（白色）
                    Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(15),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.2),
                            blurRadius: 10,
                            offset: const Offset(0, 5),
                          ),
                        ],
                      ),
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _cancelAlert,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: Colors.teal.shade700,
                          padding: const EdgeInsets.symmetric(vertical: 18),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(15),
                          ),
                          elevation: 0,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.check_circle_outline,
                              size: 28,
                              color: Colors.teal.shade700,
                            ),
                            const SizedBox(width: 12),
                            Text(
                              _isLoading ? '處理中...' : 'I\'m Safe',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w900,
                                color: Colors.teal.shade700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

// 打字機效果：閃爍游標元件
class _BlinkingCursor extends StatefulWidget {
  const _BlinkingCursor();

  @override
  State<_BlinkingCursor> createState() => _BlinkingCursorState();
}

class _BlinkingCursorState extends State<_BlinkingCursor>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _controller,
      child: Container(
        width: 2,
        height: 14,
        color: Colors.teal.shade700,
      ),
    );
  }
}
