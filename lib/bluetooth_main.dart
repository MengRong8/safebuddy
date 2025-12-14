// SafeBuddy Flutter App (主程式碼)
// 負責 UI 顯示、前端邏輯、以及與 Node.js 後端 API 溝通。

import 'package:flutter/material.dart';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io' show Platform;
import 'package:window_manager/window_manager.dart';
import 'package:latlong2/latlong.dart';
import 'map_page.dart';

import 'dart:io';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'login_page.dart';
import 'editUser_page.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'database/database_helper.dart';
import 'package:intl/intl.dart';
import 'package:lottie/lottie.dart';

import 'serial_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await dotenv.load(fileName: ".env");
  // HttpOverrides.global = MyHttpOverrides();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

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
final String mockContactNumber =
    dotenv.env['RECIPIENT_PHONE_NUMBER'] ?? '+18777804236';
const double mockLatitude = 24.969271709239766;
const double mockLongitude = 121.19130497846623;


const String SERIAL_PORT_COM = 'COM8'; // <--- 更改為您的 COM port
const int BAUD_RATE = 9600;

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

class BackendStatus {
  final bool isRunning;
  final bool twilioConfigured;
  final bool recipientConfigured;
  final int alertsCount;

  BackendStatus({
    required this.isRunning,
    required this.twilioConfigured,
    required this.recipientConfigured,
    required this.alertsCount,
  });

  factory BackendStatus.fromJson(Map<String, dynamic> json) {
    return BackendStatus(
      isRunning: json['status'] == 'running',
      twilioConfigured: json['twilioConfigured'] ?? false,
      recipientConfigured: json['recipientConfigured'] ?? false,
      alertsCount: json['alerts'] ?? 0,
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
  bool _isBleConnected = true;
  int _countdown = 10;
  String? _currentAlertId;
  String _riskMessage = '';
  bool _showTopNotification = false;
  bool _showCenterDialog = false;
  bool _isLoading = false;
  int _batteryLevel = 60;
  bool _hasShownLowBatteryWarning = false;
  int _currentDefaultMessageIndex = 0;
  bool _showGreetingMessage = false; //

  LatLng _currentPosition = const LatLng(mockLatitude, mockLongitude);
  bool _isInDangerZone = false;
  String _dangerZoneMessage = '';

  // 後端連線狀態
  bool _isBackendConnected = false;
  BackendStatus? _backendStatus;

  Timer? _timer;
  Timer? _bleSimulator;
  Timer? _batterySimulator;
  Timer? _backendHealthCheck;
  AnimationController? _slideController;
  Animation<Offset>? _slideAnimation;

  AnimationController? _dialogController;
  Animation<double>? _scaleAnimation;
  Animation<double>? _opacityAnimation;
  AnimationController? _floatingController;
  Animation<double>? _floatingAnimation;

  String _displayedMessage = '';
  String _fullMessage = '';
  Timer? _typingTimer;
  int _charIndex = 0;
  bool _isTyping = false;

  DateTime? _lastMessageChangeTime;

  String userName = '';
  String userId = '';

  SerialService? _serialService;

  @override
  void initState() {
    super.initState();

    _floatingController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000), // 2秒完成一次上下飄動
    )..repeat(reverse: true); // 重複播放，來回飄動

    _floatingAnimation = Tween<double>(
      begin: -10.0,
      end: 10.0,
    ).animate(CurvedAnimation(
      parent: _floatingController!,
      curve: Curves.easeInOut, // 平滑的飄動效果
    ));
    // 啟動時檢查後端連線
    _checkBackendConnection();

    _startBackendHealthCheck();

    final now = DateTime.now();
    if (now.hour >= 22 || now.hour < 6) {
      _checkRiskArea();
    }
    //_startBleSimulator();
    _startBatterySimulator();
    
    if (Platform.isWindows) {
      // 確保 _serialService 已經被初始化
      _serialService = SerialService(portName: SERIAL_PORT_COM, baudRate: BAUD_RATE);
      
      // 呼叫啟動方法
      _startSerialListener();
    }


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
  }

  @override
  void dispose() {
    _timer?.cancel();
    _bleSimulator?.cancel();
    _batterySimulator?.cancel();
    _backendHealthCheck?.cancel(); // 釋放後端檢查計時器
    _slideController?.dispose();
    _dialogController?.dispose();
    _serialService?.stopListening();
    _typingTimer?.cancel();
    _floatingController?.dispose();
    super.dispose();
  }

  // 檢查後端連線狀態
  Future<void> _checkBackendConnection() async {
    try {
      final response = await http
          .get(Uri.parse('http://localhost:3000/'))
          .timeout(const Duration(seconds: 3));

      if (response.statusCode == 200) {
        final result = jsonDecode(utf8.decode(response.bodyBytes));
        final status = BackendStatus.fromJson(result);

        setState(() {
          _isBackendConnected = true;
          _backendStatus = status;
        });

        print('後端連線成功');
        print('   Twilio 已設定: ${status.twilioConfigured}');
        print('   家人號碼已設定: ${status.recipientConfigured}');
        print('   警報數量: ${status.alertsCount}');
      } else {
        throw Exception('後端回應錯誤: ${response.statusCode}');
      }
    } catch (e) {
      setState(() {
        _isBackendConnected = false;
        _backendStatus = null;
      });

      print(' 後端連線失敗: $e');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                Icon(Icons.error, color: Colors.white),
                SizedBox(width: 10),
                Expanded(
                  child: Text(' 後端未連線\n請執行: node backend_mock.js'),
                ),
              ],
            ),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 5),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  // 定期檢查後端連線
  void _startBackendHealthCheck() {
    _backendHealthCheck = Timer.periodic(const Duration(seconds: 120), (timer) {
      _checkBackendConnection();
    });
  }

  // 通知家人（自訂訊息）
  Future<void> _notifyFamily(String message) async {
    if (!_isBackendConnected) {
      _showBackendNotConnectedError();
      return;
    }

    setState(() => _isLoading = true);

    try {
      final response = await http
          .post(
            Uri.parse('$backendUrl/notify-family'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'message': message,
              'userId': mockUserId,
              'latitude': _currentPosition.latitude,
              'longitude': _currentPosition.longitude,
            }),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final result = jsonDecode(utf8.decode(response.bodyBytes));

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  Icon(
                    result['success'] ? Icons.check_circle : Icons.error,
                    color: Colors.white,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      result['success']
                          ? '訊息已發送給家人'
                          : ' 訊息發送失敗: ${result['error']}',
                    ),
                  ),
                ],
              ),
              backgroundColor: result['success'] ? Colors.green : Colors.red,
              duration: const Duration(seconds: 4),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }

        print('通知家人結果: ${result['message']}');
      }
    } catch (e) {
      print('通知家人失敗: $e');
      _showApiError('通知家人失敗', e.toString());
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // 查看所有警報
  Future<void> _viewAllAlerts() async {
    try {
      // 從資料庫抓取所有 alert
      final alerts = await DatabaseHelper.instance.getAlertsByUserId(userId);

      final alertsCount = alerts.length;

      print(' 警報總數: $alertsCount');
      for (var alert in alerts) {
        print(
            '   - ${alert['id']}: ${alert['category']} at ${alert['time']} (${alert['area']})');
      }

      // 顯示警報列表對話框
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: Text('警報記錄 ($alertsCount 筆)'),
            content: SizedBox(
              width: double.maxFinite,
              height: 300,
              child: alerts.isEmpty
                  ? const Center(child: Text('目前沒有警報記錄'))
                  : ListView.builder(
                      itemCount: alerts.length,
                      itemBuilder: (context, index) {
                        final alert = alerts[index];

                        // 格式化時間
                        final time = DateTime.parse(alert['time']);
                        final formattedTime =
                            DateFormat('yyyy-MM-dd HH:mm:ss').format(time);

                        // 根據 category 選顏色
                        Color getAlertColor(String category) {
                          switch (category) {
                            case '誤觸警報':
                              return Colors.green;
                            case '觸發警報':
                              return Colors.red;
                            case '自動記錄':
                              return Colors.orange;
                            default:
                              return Colors.white;
                          }
                        }

                        return ListTile(
                          leading: Icon(
                            Icons.warning,
                            color: getAlertColor(alert['category']),
                          ),
                          title: Text(alert['category']),
                          subtitle: Text(
                            '區域: ${alert['area']}\n時間: $formattedTime\n',
                          ),
                          isThreeLine: true,
                        );
                      },
                    ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('關閉'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      print('查看警報失敗: $e');
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('錯誤'),
            content: Text('查看警報失敗: $e'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('關閉'),
              ),
            ],
          ),
        );
      }
    }
  }

  //顯示後端未連線錯誤
  void _showBackendNotConnectedError() {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              Icon(Icons.error, color: Colors.white),
              SizedBox(width: 10),
              Expanded(
                child: Text(' 後端未連線\n請先啟動: node backend_mock.js'),
              ),
            ],
          ),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 4),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  //顯示 API 錯誤
  void _showApiError(String title, String error) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error, color: Colors.white),
              const SizedBox(width: 10),
              Expanded(
                child: Text(' $title\n$error'),
              ),
            ],
          ),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 4),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  // --- API 呼叫 ---
  Future<void> _checkRiskArea() async {
    // 檢查後端連線
    if (!_isBackendConnected) {
      _showBackendNotConnectedError();
      return;
    }

    setState(() => _isLoading = true);

    try {
      final response = await http
          .post(
            Uri.parse('$backendUrl/check-risk'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'latitude': _currentPosition.latitude,
              'longitude': _currentPosition.longitude,
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

        _startTypingEffect(riskInfo.message);
      }
    } catch (e) {
      print('API Error: $e');
      _showApiError('風險檢查失敗', e.toString());
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _triggerBackendAlert() async {
    // 檢查後端連線
    if (!_isBackendConnected) {
      _showBackendNotConnectedError();
      return;
    }

    setState(() => _isLoading = true);

    final alert = {
      'area': '無',
      'category': '觸發警報',
      'time': DateTime.now().toIso8601String(),
      'userId': userId,
    };

    // 寫入資料庫
    await DatabaseHelper.instance.insertAlert(alert);

    try {
      final response = await http
          .post(
            Uri.parse('$backendUrl/alert'), // http://localhost:3000/api/alert
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'userId': mockUserId,
              'latitude': _currentPosition.latitude,
              'longitude': _currentPosition.longitude,
              // 'contactNumber': mockContactNumber,
              'triggerType': 'PIN_PULL',
            }),
          )
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final result = jsonDecode(utf8.decode(response.bodyBytes));
        setState(() => _currentAlertId = result['alertId']);

        print(' 警報已觸發: ${result['alertId']}');
        print(' 簡訊已發送: ${result['smsDelivered']}');
      }
    } catch (e) {
      print('API Error: $e');
      _showApiError('警報觸發失敗', e.toString());
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _cancelAlert() async {
    setState(() => _isLoading = true);
    _serialService?.sendCommand('S');
    final alert = {
      'area': '無',
      'category': '誤觸警報',
      'time': DateTime.now().toIso8601String(),
      'userId': userId,
    };

    // 寫入資料庫
    await DatabaseHelper.instance.insertAlert(alert);

    _timer?.cancel();

    _dialogController?.reverse();

    await Future.delayed(const Duration(milliseconds: 300));

    setState(() {
      _isAlerting = false;
      _showCenterDialog = false;
      _countdown = 10;
    });

    // 檢查後端連線
    if (!_isBackendConnected) {
      _showBackendNotConnectedError();
      setState(() => _isLoading = false);
      return;
    }

    try {
      final response = await http
          .post(
            Uri.parse('$backendUrl/cancel'), //http://localhost:3000/api/cancel
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'alertId': _currentAlertId ?? 'mock-id'}),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final result = jsonDecode(utf8.decode(response.bodyBytes));

        setState(() => _currentAlertId = null);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  Icon(
                    result['smsDelivered'] == true
                        ? Icons.check_circle
                        : Icons.error,
                    color: Colors.white,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      result['smsDelivered'] == true
                          ? '已通知緊急聯絡人：您已平安'
                          : '警報已取消，但簡訊發送失敗',
                    ),
                  ),
                ],
              ),
              backgroundColor:
                  result['smsDelivered'] == true ? Colors.green : Colors.orange,
              duration: const Duration(seconds: 4),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }

        print('取消警報成功: ${result['message']}');
        print('簡訊發送狀態: ${result['smsDelivered']}');
      } else {
        throw Exception('API 回應錯誤: ${response.statusCode}');
      }
    } catch (e) {
      print('API Error: $e');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.warning, color: Colors.white),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(' 取消警報失敗: $e'),
                ),
              ],
            ),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

// 電量模擬器（每 10 秒降低 1%）
  void _startBatterySimulator() {
    _batterySimulator = Timer.periodic(const Duration(seconds: 10), (timer) {
      setState(() {
        if (_batteryLevel > 0) {
          _batteryLevel -= 1; // 每 10 秒降低 1%
        }
      });

      // 每次電量變化後檢查是否需要顯示警告
      _showLowBatteryWarning();
    });
  }

// 充電動畫（模擬從當前電量充到 100%）
  Future<void> _chargeBattery() async {
    print(' === 開始充電流程 ===');
    print('   當前電量: $_batteryLevel%');

    // 如果電量已滿，不需要充電
    if (_batteryLevel >= 100) {
      print('   電量已滿，無需充電');
      return;
    }

    // 暫停電量消耗
    _batterySimulator?.cancel();

    // 快速充電動畫（每 0.1 秒增加 10%）
    Timer.periodic(const Duration(milliseconds: 100), (chargeTimer) {
      setState(() {
        if (_batteryLevel < 100) {
          _batteryLevel += 10;
          if (_batteryLevel > 100) _batteryLevel = 100;
        } else {
          // 充電完成
          chargeTimer.cancel();

          print(' 充電完成：電量 = $_batteryLevel%');

          // 顯示充電完成訊息
          _riskMessage = ' 充電完成！電量已恢復到 100%';
          _startTypingEffect(' 充電完成！電量已恢復到 100%');
          _hasShownLowBatteryWarning = false;

          //  3 秒後清除訊息，然後延遲 5 秒再顯示預設訊息
          Future.delayed(const Duration(seconds: 5), () {
            setState(() {
              _riskMessage = '';
            });

            print(' 延遲 5 秒後顯示預設訊息');

            // 重新啟動電量消耗
            _startBatterySimulator();
          });
        }
      });
    });
  }

// 顯示低電量警告// 在 State 類別中加入這個變數（與其他變數一起）
  Set<int> _shownBatteryWarnings = {}; // 記錄已顯示警告的電量等級

// 顯示低電量警告（每 10% 跳一次，從 50% 開始）
  void _showLowBatteryWarning() {
    // 定義需要顯示警告的電量等級
    const warningLevels = [50, 40, 30, 20, 10, 0];

    // 如果當前電量不在警告範圍，跳過
    if (!warningLevels.contains(_batteryLevel)) {
      return;
    }

    // 如果已經顯示過，跳過
    if (_shownBatteryWarnings.contains(_batteryLevel)) {
      return;
    }

    // 記錄已顯示的電量等級
    _shownBatteryWarnings.add(_batteryLevel);

    print(' 電量警告: $_batteryLevel%');

    // 觸發 UI 更新（讓 _buildSafeBuddyDialog 重新檢查訊息）
    setState(() {});
  }

// 打字機效果方法
  void _startTypingEffect(String message) {
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
      const Duration(milliseconds: 50),
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
  void _isAlert() {
    if (_isAlerting) return;

    // 檢查後端連線
    if (!_isBackendConnected) {
      _showBackendNotConnectedError();
      return;
    }
  _serialService?.sendCommand('W');
    setState(() {
      _isAlerting = true;
      _showCenterDialog = true;
      _countdown = 10;
    });

    // 播放對話框彈出動畫
    _dialogController?.forward();

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_countdown == 0) {
        _serialService?.sendCommand('A');
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

  // void _startBleSimulator() {
  //   _bleSimulator = Timer.periodic(const Duration(seconds: 30), (timer) {
  //     setState(() {
  //       _bleStatus = (_bleStatus == '已連線') ? '未連線' : '已連線';
  //       _isBleConnected = (_bleStatus == '已連線');
  //     });

  //     print('藍芽狀態: $_bleStatus (連線: $_isBleConnected)');
  //   });
  // }

void _startSerialListener() {
    // 只有在 _serialService 存在 (即 Windows 平台) 時才執行
    if (_serialService == null) return;

    // 1. 監聽連線狀態 (Connection Status Stream)
    // 這會處理連線過程中的斷線或重連狀態更新
    _serialService!.connectionStatusStream.listen((isConnected) {
      if (mounted) {
        setState(() {
          _isBleConnected = isConnected;
          _bleStatus = isConnected ? '已連線' : '未連線';
        });

        // 如果斷線，印出 Log (可選擇是否要顯示 SnackBar，避免太頻繁打擾使用者)
        if (!isConnected) {
          print(' BLE/Serial Connection Lost / Disconnected');
        }
      }
    });

    // 2. 嘗試啟動連線 (Start Listening)
    bool isStarted = _serialService!.startListening();

    if (isStarted) {
      // --- 連線成功區塊 ---
      
      // 手動設定一次狀態 (確保 UI 立即更新為綠色)
      if (mounted) {
        setState(() {
          _isBleConnected = true;
          _bleStatus = '已連線';
        });
      }

      // 3. 訂閱數據流 (Data Stream) - 處理業務邏輯
      _serialService!.dataStream.listen((line) {
        // ----------------------------------------------------
        // A. 收到 "pressed" -> 觸發警報
        // ----------------------------------------------------
        if (line.contains('pressed')) {
          print('>>> [Hardware] Trigger Signal Received');
          if (mounted && !_isAlerting) {
            _isAlert(); // 呼叫您的觸發函數 (注意是 _isAlert)
          }
        }
        // ----------------------------------------------------
        // B. 收到 "stopped" -> 取消警報 (綠色按鈕)
        // ----------------------------------------------------
        else if (line.contains('stopped')) {
          print('>>> [Hardware] Cancel Signal Received');

          // 只有在 "正在警報中" 的時候才需要執行取消
          if (mounted && _isAlerting) {
            // 直接呼叫原本的取消函數
            _cancelAlert();

            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('已透過硬體按鈕解除警報'),
                backgroundColor: Colors.green,
                duration: Duration(seconds: 2),
              ),
            );
          }
        }
      });

    } else {
      // --- 連線失敗區塊 (isStarted == false) ---
      
      // 處理初次連線失敗的邏輯
      if (mounted) {
        setState(() {
          _isBleConnected = false;
          _bleStatus = '未連線';
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('串列埠連接失敗：無法開啟 COM8。請檢查設備。'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 5),
          ),
        );
      }
    }
  }

// main.dart 內，在其他類似的函數旁邊新增：

void _retryConnection() async { // 1. 改為 async
    if (_serialService == null) {
      return;
    }
  _isBleConnected=false;
    // 2. 停止舊的監聽
    print('>>> Stopping old connection to release resources...');
    _serialService!.stopListening();

    // 3. 顯示提示
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('正在重置連線，請稍候...'),
        duration: Duration(seconds: 1),
      ),
    );

    // 4. ⚠️ 關鍵：等待 1 秒讓 Windows 釋放 COM Port 鎖定
    await Future.delayed(const Duration(seconds: 1));

    // 5. 重新啟動串列埠監聽器
    print('>>> Retrying Serial Connection...');
    _startSerialListener();
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
          _buildSafeBuddyCharacter(),
          _buildSafeBuddyDialog(),
          if (_showTopNotification) _buildTopNotification(),
          if (_showCenterDialog) _buildCenterDialog(),
        ],
      ),
    );
  }

  // 背景圖
  Widget _buildMapBackground() {
    return Stack(
      fit: StackFit.expand,
      children: [
        // 背景 GIF
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
        //  點擊手動充電
        onTap: () {
          if (isConnected) {
            // 情況 A: 已連線 -> 執行原本的充電邏輯
            if (_batteryLevel < 100) {
              print(' 手動觸發充電');
              _chargeBattery();
            } else {
              print('電量已滿，無需充電');
            }
          } else {
            // 情況 B: 未連線 -> 執行重連邏輯
            print(' 藍牙未連線，嘗試重連...');
            _retryConnection();
            ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text('藍牙/串列埠重新連線中......'),
                            backgroundColor: Colors.orange,
                            duration: Duration(seconds: 4),
                        ),
                    );
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
              //  充電中顯示閃電圖示
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
                isConnected ? '$_batteryLevel%' : '未連線',
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
    final bool isLoggedIn = userId.isNotEmpty;
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
                    userId: isLoggedIn ? userId.toString() : '0',
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
                    _riskMessage = '目前位置安全，請放心！'; // 設定安全訊息
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
            onPressed: _isAlert,
            backgroundColor: Colors.red.shade500,
            child: const Icon(Icons.warning_amber_rounded, color: Colors.white),
          ),
        ],
      ),
    );
  }

  // 使用者資訊卡片
  Widget _buildUserInfoCard() {
    final bool isLoggedIn = userId.isNotEmpty;
    File? avatarFile;
    if (isLoggedIn) {
      final avatarPath =
          '${Directory.current.path}\\database\\avatars\\$userId.png';
      avatarFile = File(avatarPath);
      if (!avatarFile.existsSync()) avatarFile = null;
    }

    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 15, 20, 16),
        decoration: BoxDecoration(
          color: const Color.fromARGB(255, 153, 168, 153).withOpacity(0.8),
          borderRadius: const BorderRadius.vertical(
            bottom: Radius.circular(30),
          ),
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
                GestureDetector(
                  onTap: () async {
                    if (!isLoggedIn) return;
                    final result = await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => EditUserPage(userId: userId),
                      ),
                    );
                    if (result == true) {
                      setState(() {
                        // 重新載入 avatar / username
                      });
                    }
                  },
                  child: CircleAvatar(
                    radius: 28,
                    backgroundColor: Colors.teal.shade100,
                    backgroundImage:
                        (avatarFile != null) ? FileImage(avatarFile) : null,
                    child: (avatarFile == null)
                        ? const Icon(Icons.person, size: 32, color: Colors.teal)
                        : null,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isLoggedIn ? userName : '未登入',
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        isLoggedIn ? '使用者 ID: $userId' : '',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                OutlinedButton.icon(
                  onPressed: () async {
                    if (isLoggedIn) {
                      setState(() {
                        userId = '';
                        userName = '';
                      });
                    } else {
                      final result = await Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (context) => const LoginPage()),
                      );
                      if (result != null && result is Map<String, dynamic>) {
                        setState(() {
                          userId = result['userId'] ?? '';
                          userName = result['name'] ?? '';
                        });
                      }
                    }
                  },
                  icon: Icon(isLoggedIn ? Icons.logout : Icons.login, size: 16),
                  label: Text(
                    isLoggedIn ? '登出' : '登入',
                    style: const TextStyle(fontSize: 12),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.teal,
                    side: BorderSide(color: Colors.teal.shade400),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(
                        vertical: 12, horizontal: 16),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      showDialog(
                        context: context,
                        builder: (context) {
                          final controller = TextEditingController();
                          return AlertDialog(
                            title: const Text('聯絡家人'),
                            content: TextField(
                              controller: controller,
                              decoration: const InputDecoration(
                                hintText: '輸入要發送的訊息',
                              ),
                              maxLines: 3,
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context),
                                child: const Text('取消'),
                              ),
                              TextButton(
                                onPressed: () {
                                  if (controller.text.isNotEmpty) {
                                    _notifyFamily(controller.text);
                                    Navigator.pop(context);
                                  }
                                },
                                child: const Text('發送'),
                              ),
                            ],
                          );
                        },
                      );
                    },
                    icon: const Icon(Icons.message, size: 16),
                    label: const Text('聯絡家人', style: TextStyle(fontSize: 12)),
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
                    onPressed: _viewAllAlerts,
                    icon: const Icon(Icons.history, size: 16),
                    label: const Text('警報記錄', style: TextStyle(fontSize: 12)),
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
    String fairyImage;
    double imageScale;

    if (_fullMessage.contains('嗨嗨～我是 SafeBuddy') ||
        _fullMessage.contains('有什麼我能幫忙的嗎')) {
      fairyImage = 'assets/image/fairy_handshake.png';
      imageScale = 1.15; // 握手圖片放大 1.5 倍
    } else if (_fullMessage.contains('充電中') ||
        _fullMessage.contains('正在快速充電')) {
      fairyImage = 'assets/image/fairy_charging.png';
      imageScale = 1.1; // 其他圖片保持原大小
    } else if (_fullMessage.contains('充電完成')) {
      fairyImage = 'assets/image/fairy_charging.png';
      imageScale = 1.1;
    } else if (_fullMessage.contains('只剩 10%') ||
        _fullMessage.contains('剩餘 20%') ||
        _fullMessage.contains('只剩 30%') ||
        _fullMessage.contains('剩下 40%') ||
        _fullMessage.contains('只剩一半') ||
        _fullMessage.contains('電量耗盡')) {
      fairyImage = 'assets/image/fairy_discharged.png';
      imageScale = 1.13;
    } else if (_fullMessage.contains('藍芽未連接')) {
      fairyImage = 'assets/image/fairy_no_conn.png';
      imageScale = 1.1;
    } else {
      fairyImage = 'assets/image/fairy_map.png';
      imageScale = 1.1;
    }
    return Positioned(
      left: 0,
      right: 0,
      top: 460,
      child: Center(
        child: _floatingAnimation != null
            ? AnimatedBuilder(
                animation: _floatingAnimation!,
                builder: (context, child) {
                  return Transform.translate(
                    offset: Offset(0, _floatingAnimation!.value),
                    child: child,
                  );
                },
                child: _buildFairyContent(fairyImage, imageScale),
              )
            : _buildFairyContent(fairyImage, imageScale), // 備用方案
      ),
    );
  }

  Widget _buildFairyContent(String fairyImage, double imageScale) {
    return GestureDetector(
      onTap: () {
        setState(() {
          _showGreetingMessage = true;
        });

        Future.delayed(const Duration(seconds: 10), () {
          if (mounted) {
            setState(() {
              _showGreetingMessage = false;
            });
          }
        });
      },
      child: Transform.scale(
        scale: imageScale,
        child: SizedBox(
          width: 300,
          height: 300,
          child: Image.asset(
            fairyImage,
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) {
              return Image.asset(
                'assets/image/fairy_map.png',
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) {
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

// 對話框（顯示電量警告 + 打招呼訊息）
  Widget _buildSafeBuddyDialog() {
    String targetMessage;
    Color borderColor;
    Color shadowColor;
    Color textColor;
    FontWeight fontWeight;
    borderColor = Colors.green.shade400;
    shadowColor = Colors.green.withValues(alpha: 0.00000001);
    textColor = Colors.green.shade900;
    fontWeight = FontWeight.w700;
    //  充電中訊息

    if (_showGreetingMessage) {
      // 點擊小精靈時顯示打招呼
      targetMessage = '嗨嗨～我是 SafeBuddy 你的專屬小精靈！有什麼我能幫忙的嗎？';
    } else if (!_isBleConnected) {
      targetMessage = ' 注意！藍芽未連接，請確認小物是否在身邊！';
    } else if (_isBleConnected && _riskMessage.contains('充電完成')) {
      targetMessage = ' 充電完成！電量已恢復到 100%';
    } else if (_isBleConnected && _batteryLevel == 50) {
      targetMessage = ' 嘿！電量只剩一半囉～快去充電吧！';
    } else if (_isBleConnected && _batteryLevel == 40) {
      targetMessage = ' 哎呀！剩下 40% 電量了，記得找地方充電喔～';
    } else if (_isBleConnected && _batteryLevel == 30) {
      targetMessage = ' 救命啊！電量只剩 30% 了，我快撐不住啦～';
    } else if (_isBleConnected && _batteryLevel == 20) {
      targetMessage = ' 電量剩餘 20%！再不充電我就要說再見了！';
    } else if (_isBleConnected && _batteryLevel == 10) {
      targetMessage = ' 完蛋了！只剩 10% 了，我快要變成小天使了...！';
    } else if (_isBleConnected && _batteryLevel == 0) {
      targetMessage = ' 電量耗盡！裝置即將關機...';
    } else {
      // 其他時間顯示地圖提示
      targetMessage = '點擊左邊按鈕查看地圖及周邊風險區域喔！';
    }

    // 統一的訊息切換邏輯（只在這裡觸發打字效果）
    if (_fullMessage != targetMessage && !_isTyping) {
      final now = DateTime.now();

      if (_lastMessageChangeTime != null) {
        final timeSinceLastChange =
            now.difference(_lastMessageChangeTime!).inSeconds;
        final remainingTime =
            (timeSinceLastChange < 5) ? (5 - timeSinceLastChange) : 0;

        if (remainingTime > 0) {
          // 延遲切換（確保間隔 5 秒）
          Future.delayed(Duration(seconds: remainingTime), () {
            if (mounted && _fullMessage != targetMessage && !_isTyping) {
              setState(() {
                _lastMessageChangeTime = DateTime.now();
              });
              _startTypingEffect(targetMessage);
            }
          });
        } else {
          // 立即切換（已經超過 5 秒）
          setState(() {
            _lastMessageChangeTime = DateTime.now();
          });
          _startTypingEffect(targetMessage);
        }
      } else {
        // 首次顯示，立即切換
        setState(() {
          _lastMessageChangeTime = DateTime.now();
        });
        _startTypingEffect(targetMessage);
      }
    }

    return Positioned(
      right: 16,
      top: 300,
      child: Container(
        width: 220,
        height: 110,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.9),
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
                      fontWeight: fontWeight,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
                if (_isTyping)
                  Container(
                    margin: const EdgeInsets.only(left: 2),
                    child: const _BlinkingCursor(),
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
      // 危險區域警告
      notificationMessage =
          _dangerZoneMessage.isNotEmpty ? _dangerZoneMessage : '您位於危險區域，請提高警覺！';
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
      notificationMessage = '目前位置安全';
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
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Color(0xFFFFF9E6), // 淡黃色
                          Color(0xFFFFFBF0), // 象牙白
                          Color(0xFFFFFAE6), // 淡奶油黃
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
                            '倒數結束後將通知緊急聯絡人',
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
                                side: const BorderSide(
                                  color: Color(0xFFFFD54F),
                                  width: 2,
                                ),
                              ),
                              elevation: 0,
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(
                                  Icons.check_circle,
                                  size: 22,
                                  color: Color(0xFFFFC107),
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

                  //  右下角小精靈圖片
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
                          return Container(
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(
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

                  //  裝飾小星星（左上角）
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

                  //  裝飾小星星（右上角）
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
