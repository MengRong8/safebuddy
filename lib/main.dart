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

  //  新增：記錄上次訊息切換時間
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

// 新增：電量模擬器（每 10 秒降低 1%，降到 0% 後自動恢復到 100%）
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
        } else {
          //  電量降到 0% 時，自動充電到 100%
          print('🔋 電量耗盡，自動充電中...');
          _chargeBattery();
        }
      });
    });
  }

// 新增：充電動畫（模擬從 0% 充到 100%）
  void _chargeBattery() {
    // 暫停電量消耗
    _batterySimulator?.cancel();

    // 顯示充電訊息
    setState(() {
      _riskMessage = '🔌 電量耗盡，正在快速充電中...';
    });
    _startTypingEffect('🔌 電量耗盡，正在快速充電中...');

    // 快速充電動畫（每 0.1 秒增加 10%）
    Timer.periodic(const Duration(milliseconds: 100), (chargeTimer) {
      setState(() {
        if (_batteryLevel < 100) {
          _batteryLevel += 10;
          if (_batteryLevel > 100) _batteryLevel = 100;
        } else {
          // 充電完成
          chargeTimer.cancel();
          print(' 充電完成！電量恢復到 100%');

          // 顯示充電完成訊息
          _riskMessage = ' 充電完成！電量已恢復到 100%';
          _startTypingEffect(' 充電完成！電量已恢復到 100%');
          _hasShownLowBatteryWarning = false;

          // 3 秒後清除訊息並重新開始消耗
          Future.delayed(const Duration(seconds: 3), () {
            setState(() {
              _riskMessage = '';
            });
            _startTypingEffect('您好！我是你的專屬 SafeBuddy 小精靈。');

            // 重新啟動電量消耗
            _startBatterySimulator();
          });
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

// 右上角電量顯示（加入點擊充電功能）
  Widget _buildBatteryIndicator() {
    final bool isConnected = _bleStatus == '已連線';
    final bool isLowBattery = _batteryLevel <= 20;

    return Positioned(
      top: 140,
      right: 10,
      child: GestureDetector(
        //  新增：點擊手動充電
        onTap: () {
          if (_batteryLevel < 100) {
            print('🔌 手動觸發充電');
            _chargeBattery();
          } else {
            print('🔋 電量已滿，無需充電');
          }
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color:
                const Color.fromARGB(255, 153, 168, 153).withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(20),
            border:
                isLowBattery ? Border.all(color: Colors.red, width: 2) : null,
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
              //  新增：充電中顯示閃電圖示
              if (_batteryLevel == 0 ||
                  _batterySimulator?.isActive == false && _batteryLevel < 100)
                Row(
                  children: [
                    Icon(
                      Icons.bolt,
                      color: Colors.yellow.shade700,
                      size: 18,
                    ),
                    const SizedBox(width: 4),
                  ],
                ),
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
                    //  危險區域：顯示橫幅
                    _riskMessage = _dangerZoneMessage;
                    _showTopNotificationBanner();
                    // 對話框保持顯示電量或打招呼（不改變）
                  } else {
                    //  安全區域：清除危險訊息，顯示安全橫幅
                    _riskMessage = ' 目前位置安全，請放心！'; // 設定安全訊息
                    _dangerZoneMessage = ''; // 清空危險訊息
                    _isInDangerZone = false;
                    _showTopNotificationBanner(); // 顯示安全橫幅
                    // 對話框保持顯示電量或打招呼（不改變）
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

//  對話框（只顯示電量和打招呼訊息）
  Widget _buildSafeBuddyDialog() {
    //  決定要顯示的訊息類型（不包含危險提示）
    String targetMessage;
    Color borderColor;
    Color shadowColor;
    Color textColor;

    if (_batteryLevel <= 20) {
      // 優先級1：低電量警告
      targetMessage = '記得充電喔！電量剩餘 $_batteryLevel%';
      borderColor = const Color.fromARGB(255, 115, 229, 159);
      shadowColor =
          const Color.fromARGB(255, 59, 108, 75).withValues(alpha: 0.25);
      textColor = const Color.fromARGB(255, 38, 119, 88);
    } else {
      // 優先級2：預設打招呼訊息
      targetMessage = '您好！我是你的專屬 SafeBuddy 小精靈。';
      borderColor = Colors.teal.shade300;
      shadowColor = Colors.teal.withValues(alpha: 0.2);
      textColor = Colors.grey.shade800;
    }

    //  當訊息變更時，強制等待 3 秒
    if (_fullMessage != targetMessage && !_isTyping) {
      final now = DateTime.now();

      if (_lastMessageChangeTime != null) {
        final timeSinceLastChange =
            now.difference(_lastMessageChangeTime!).inSeconds;

        //  不論何時都等待剩餘時間
        final remainingTime = (timeSinceLastChange < 5)
            ? (5 - timeSinceLastChange)
            : 5; // 如果超過 5 秒，重新等待 5 秒

        print('⏳ 訊息切換延遲 $remainingTime 秒（強制 5 秒冷卻）');

        Future.delayed(Duration(seconds: remainingTime), () {
          if (mounted && _fullMessage != targetMessage && !_isTyping) {
            print(' 延遲後切換訊息: $targetMessage');
            setState(() {
              _lastMessageChangeTime = DateTime.now();
            });
            _startTypingEffect(targetMessage);
          }
        });
      } else {
        //  首次顯示也等待 3 秒（可選：如果希望首次立即顯示，改為 0）
        print(' 首次顯示訊息（等待 3 秒）: $targetMessage');
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted && _fullMessage != targetMessage && !_isTyping) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              setState(() {
                _lastMessageChangeTime = DateTime.now();
              });
              _startTypingEffect(targetMessage);
            });
          }
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
            color: borderColor,
            width: 2.5,
          ),
          boxShadow: [
            BoxShadow(
              color: shadowColor,
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
                      color: textColor,
                      height: 1.4,
                      fontWeight: _batteryLevel <= 20
                          ? FontWeight.bold
                          : FontWeight.w500,
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

// 上方危險通知橫幅（包含安全提示）
  Widget _buildTopNotification() {
    //  處理所有與位置相關的訊息
    String notificationMessage;
    Color backgroundColor;
    Color borderColor;
    Color iconColor;
    Color textColor;
    IconData iconData;

    if (_isInDangerZone) {
      // 危險區域警告（優先級最高）
      notificationMessage = _dangerZoneMessage.isNotEmpty
          ? _dangerZoneMessage
          : '⚠️ 您位於危險區域，請提高警覺！';
      backgroundColor = Colors.red.shade50;
      borderColor = Colors.red.shade400;
      iconColor = Colors.red.shade700;
      textColor = Colors.red.shade900;
      iconData = Icons.warning_amber_rounded;
    } else if (_riskMessage.isNotEmpty &&
        !_riskMessage.contains('電量') &&
        !_riskMessage.contains('充電')) {
      // 一般訊息（包含安全提示，但排除電量訊息）
      if (_riskMessage.contains('安全')) {
        //  安全訊息（綠色）
        notificationMessage = _riskMessage;
        backgroundColor = Colors.green.shade50;
        borderColor = Colors.green.shade300;
        iconColor = Colors.green.shade600;
        textColor = Colors.green.shade800;
        iconData = Icons.check_circle_outline;
      } else {
        // 其他風險提示（橙色）
        notificationMessage = _riskMessage;
        backgroundColor = Colors.orange.shade50;
        borderColor = Colors.orange.shade300;
        iconColor = Colors.orange.shade600;
        textColor = Colors.orange.shade800;
        iconData = Icons.info_outline;
      }
    } else {
      // 預設訊息（不應該顯示，但作為安全後備）
      notificationMessage = ' 目前位置安全';
      backgroundColor = Colors.green.shade50;
      borderColor = Colors.green.shade300;
      iconColor = Colors.green.shade600;
      textColor = Colors.green.shade800;
      iconData = Icons.check_circle_outline;
    }

    return SlideTransition(
      position: _slideAnimation!,
      child: Positioned(
        top: 165,
        left: 16,
        right: 16,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: borderColor, width: 2),
            boxShadow: [
              BoxShadow(
                color: borderColor.withValues(alpha: 0.3),
                blurRadius: 10,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Row(
            children: [
              // 動態圖示
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  iconData,
                  color: iconColor,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),

              // 動態訊息
              Expanded(
                child: Text(
                  notificationMessage,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: textColor,
                    height: 1.3,
                  ),
                ),
              ),

              // 關閉按鈕
              GestureDetector(
                onTap: () {
                  _slideController?.reverse().then((_) {
                    setState(() {
                      _showTopNotification = false;
                      //  關閉橫幅後清除 _riskMessage（避免重複顯示）
                      if (!_isInDangerZone) {
                        _riskMessage = '';
                      }
                    });
                  });
                },
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: textColor.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.close,
                    size: 16,
                    color: textColor,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 中間對話框
  Widget _buildCenterDialog() {
    return AnimatedBuilder(
      animation: _dialogController!,
      builder: (context, child) {
        return Container(
          color: Colors.black.withValues(alpha: 0.5 * _opacityAnimation!.value),
          child: Center(
            child: Transform.scale(
              scale: _scaleAnimation!.value,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  // 主要對話框
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 40),
                    padding: const EdgeInsets.all(20),
                    width: 280,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          const Color(0xFFFFF9E6), // 淡黃色
                          const Color(0xFFFFFBF0), // 象牙白
                          const Color(0xFFFFFAE6), // 淡奶油黃
                        ],
                      ),
                      borderRadius: BorderRadius.circular(25),
                      border: Border.all(
                        color: const Color(0xFFFFD54F)
                            .withValues(alpha: 0.6), // 金黃色邊框
                        width: 2.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFFFC107)
                              .withValues(alpha: 0.3), // 琥珀色陰影
                          blurRadius: 20,
                          spreadRadius: 3,
                        ),
                        BoxShadow(
                          color: Colors.white.withValues(alpha: 0.5),
                          blurRadius: 10,
                          spreadRadius: -3,
                          offset: const Offset(-3, -3),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // 可愛警告圖示
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                const Color(0xFFFFD54F), // 金黃色
                                const Color(0xFFFFC107), // 琥珀色
                              ],
                            ),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFFFFC107)
                                    .withValues(alpha: 0.4),
                                blurRadius: 15,
                                spreadRadius: 3,
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.favorite_border, // 愛心圖示
                            size: 36,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 16),

                        // 標題
                        Text(
                          '緊急警報倒數',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            color: const Color(0xFFF57C00), // 深橙黃色
                            shadows: [
                              Shadow(
                                color: Colors.white.withValues(alpha: 0.8),
                                blurRadius: 3,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),

                        // 倒數數字（可愛圓形背景）
                        Container(
                          width: 100,
                          height: 100,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                Color(0xFFFFE082), // 淡金黃
                                Color(0xFFFFD54F), // 金黃色
                              ],
                            ),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.white,
                              width: 3,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFFFFC107)
                                    .withValues(alpha: 0.5),
                                blurRadius: 15,
                              ),
                            ],
                          ),
                          child: Center(
                            child: Text(
                              '$_countdown',
                              style: const TextStyle(
                                fontSize: 48,
                                fontWeight: FontWeight.w900,
                                color: Colors.white,
                                shadows: [
                                  Shadow(
                                    color: Color(0xFFF57C00),
                                    blurRadius: 8,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),

                        // 秒字
                        Text(
                          '秒',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFFFFC107),
                          ),
                        ),
                        const SizedBox(height: 12),

                        // 說明文字
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.7),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: const Color(0xFFFFD54F)
                                  .withValues(alpha: 0.5),
                              width: 1.5,
                            ),
                          ),
                          child: const Text(
                            '倒數結束後將通知緊急聯絡人 💕',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 11,
                              color: Color(0xFFF57C00),
                              fontWeight: FontWeight.w600,
                              height: 1.3,
                            ),
                          ),
                        ),
                        const SizedBox(height: 18),

                        // 我沒事按鈕（可愛黃色）
                        Container(
                          width: double.infinity,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(15),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFFFFC107)
                                    .withValues(alpha: 0.3),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: ElevatedButton(
                            onPressed: _isLoading ? null : _cancelAlert,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: const Color(0xFFF57C00),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(15),
                                side: BorderSide(
                                  color: const Color(0xFFFFD54F),
                                  width: 2,
                                ),
                              ),
                              elevation: 0,
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.check_circle,
                                  size: 22,
                                  color: const Color(0xFFFFC107),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  _isLoading ? '處理中...' : 'I\'m Safe',
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w900,
                                    color: Color(0xFFF57C00),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // ✨ 右下角小精靈圖片
                  Positioned(
                    right: 20,
                    bottom: -15,
                    child: Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color:
                                const Color(0xFFFFC107).withValues(alpha: 0.3),
                            blurRadius: 10,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: Image.asset(
                        'assets/image/fairy_speaking.png',
                        fit: BoxFit.contain,
                        errorBuilder: (context, error, stackTrace) {
                          // 如果圖片載入失敗，顯示可愛的替代圖示
                          return Container(
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [
                                  Color(0xFFFFE082),
                                  Color(0xFFFFD54F),
                                ],
                              ),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.record_voice_over,
                              size: 40,
                              color: Colors.white,
                            ),
                          );
                        },
                      ),
                    ),
                  ),

                  // ✨ 裝飾小星星（左上角）
                  Positioned(
                    left: 25,
                    top: -8,
                    child: Icon(
                      Icons.star,
                      size: 20,
                      color:
                          const Color(0xFFFFD700).withValues(alpha: 0.8), // 金色
                    ),
                  ),

                  // ✨ 裝飾小星星（右上角）
                  Positioned(
                    right: 25,
                    top: -5,
                    child: Icon(
                      Icons.star,
                      size: 16,
                      color:
                          const Color(0xFFFFC107).withValues(alpha: 0.8), // 琥珀色
                    ),
                  ),
                ],
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
