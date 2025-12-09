import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'dart:convert';
import 'package:flutter/services.dart';

import '../database/database_helper.dart';

class MapPage extends StatefulWidget {
  final LatLng initialPosition; //  接收初始位置
  final String userId;

  const MapPage({
    super.key,
    required this.initialPosition, //  必須傳入初始位置
    required this.userId,
  });

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  late MapController _mapController;
  late LatLng _currentPosition; //  當前位置（可移動）

  List<LatLng> _crimePolygons = [];
  List<LatLng> _accidentPolygons = [];
  List<LatLng> _dangerIntersections = [];

  bool _showCrimeZones = true;
  bool _showAccidentZones = true;
  bool _showDangerIntersections = true;

  LatLng? _lastAlertPosition; // 紀錄上一次 alert 的位置
  final double _alertDistanceThreshold = 50; // 公尺

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    _currentPosition = widget.initialPosition; //  使用傳入的初始位置
    _loadHotZoneData();
  }

  bool _isInDangerZone() {
    // 檢查犯罪熱點（每 4 個點組成一個多邊形）
    if (_showCrimeZones && _crimePolygons.isNotEmpty) {
      for (int i = 0; i < _crimePolygons.length; i += 4) {
        if (i + 3 < _crimePolygons.length) {
          List<LatLng> polygon = [
            _crimePolygons[i],
            _crimePolygons[i + 1],
            _crimePolygons[i + 2],
            _crimePolygons[i + 3],
          ];
          if (_isPointInPolygon(_currentPosition, polygon)) {
            return true;
          }
        }
      }
    }

    // 檢查事故熱點（每 4 個點組成一個多邊形）
    if (_showAccidentZones && _accidentPolygons.isNotEmpty) {
      for (int i = 0; i < _accidentPolygons.length; i += 4) {
        if (i + 3 < _accidentPolygons.length) {
          List<LatLng> polygon = [
            _accidentPolygons[i],
            _accidentPolygons[i + 1],
            _accidentPolygons[i + 2],
            _accidentPolygons[i + 3],
          ];
          if (_isPointInPolygon(_currentPosition, polygon)) {
            return true;
          }
        }
      }
    }

    // 檢查危險路口（50 公尺範圍內）
    if (_showDangerIntersections && _dangerIntersections.isNotEmpty) {
      for (var intersection in _dangerIntersections) {
        double distance = _calculateDistance(_currentPosition, intersection);
        if (distance < 50) {
          return true;
        }
      }
    }

    return false;
  }

  String _getDangerZoneMessage() {
    List<String> dangers = [];

    // 檢查犯罪熱點
    if (_showCrimeZones && _crimePolygons.isNotEmpty) {
      for (int i = 0; i < _crimePolygons.length; i += 4) {
        if (i + 3 < _crimePolygons.length) {
          List<LatLng> polygon = [
            _crimePolygons[i],
            _crimePolygons[i + 1],
            _crimePolygons[i + 2],
            _crimePolygons[i + 3],
          ];
          if (_isPointInPolygon(_currentPosition, polygon)) {
            dangers.add('犯罪熱點');
            break;
          }
        }
      }
    }

    // 檢查事故熱點
    if (_showAccidentZones && _accidentPolygons.isNotEmpty) {
      for (int i = 0; i < _accidentPolygons.length; i += 4) {
        if (i + 3 < _accidentPolygons.length) {
          List<LatLng> polygon = [
            _accidentPolygons[i],
            _accidentPolygons[i + 1],
            _accidentPolygons[i + 2],
            _accidentPolygons[i + 3],
          ];
          if (_isPointInPolygon(_currentPosition, polygon)) {
            dangers.add('事故多發區');
            break;
          }
        }
      }
    }

    // 檢查危險路口
    if (_showDangerIntersections && _dangerIntersections.isNotEmpty) {
      for (var intersection in _dangerIntersections) {
        double distance = _calculateDistance(_currentPosition, intersection);
        if (distance < 50) {
          dangers.add('危險路口附近');
          break;
        }
      }
    }

    if (dangers.isEmpty) {
      return '目前位置安全';
    }

    final now = DateTime.now();
    final isNightTime = now.hour >= 22 || now.hour < 6;

    String message = '您位於${dangers.join('、')}';
    if (isNightTime) {
      message += '，且現在是夜間時段，請特別注意安全或結伴同行！';
    } else {
      message += '，請注意周邊環境！';
    }

    return message;
  }

  // 判斷是否在多邊形內
  bool _isPointInPolygon(LatLng point, List<LatLng> polygon) {
    if (polygon.length < 3) return false;

    bool inside = false;
    int j = polygon.length - 1;

    for (int i = 0; i < polygon.length; i++) {
      if ((polygon[i].latitude > point.latitude) !=
              (polygon[j].latitude > point.latitude) &&
          point.longitude <
              (polygon[j].longitude - polygon[i].longitude) *
                      (point.latitude - polygon[i].latitude) /
                      (polygon[j].latitude - polygon[i].latitude) +
                  polygon[i].longitude) {
        inside = !inside;
      }
      j = i;
    }

    return inside;
  }

  //計算兩點距離
  double _calculateDistance(LatLng point1, LatLng point2) {
    const Distance distance = Distance();
    return distance.as(LengthUnit.Meter, point1, point2);
  }

  Future<void> _loadHotZoneData() async {
    try {
      // 載入犯罪熱點（多邊形區域）
      final crimeData =
          await rootBundle.loadString('assets/hotzones/crime_zones.json');
      final crimeJson = jsonDecode(crimeData) as List;

      List<LatLng> allCrimePoints = [];
      for (var zone in crimeJson) {
        final coords = zone['coordinates'] as List;
        for (var coord in coords) {
          allCrimePoints.add(LatLng(coord[0] as double, coord[1] as double));
        }
      }

      setState(() {
        _crimePolygons = allCrimePoints;
      });
      print('犯罪熱點載入成功: ${allCrimePoints.length} 個點');

      // 載入事故熱點（多邊形區域）
      final accidentData =
          await rootBundle.loadString('assets/hotzones/accident_zones.json');
      final accidentJson = jsonDecode(accidentData) as List;

      List<LatLng> allAccidentPoints = [];
      for (var zone in accidentJson) {
        final coords = zone['coordinates'] as List;
        for (var coord in coords) {
          allAccidentPoints.add(LatLng(coord[0] as double, coord[1] as double));
        }
      }

      setState(() {
        _accidentPolygons = allAccidentPoints;
      });
      print('事故區域載入成功: ${allAccidentPoints.length} 個點');

      // 載入危險路口（單點）
      final intersectionData = await rootBundle
          .loadString('assets/hotzones/danger_intersections.json');
      final intersectionJson = jsonDecode(intersectionData) as List;

      List<LatLng> intersectionPoints = [];
      for (var intersection in intersectionJson) {
        final coord = intersection['coordinate'] as List;
        intersectionPoints.add(LatLng(coord[0] as double, coord[1] as double));
      }

      setState(() {
        _dangerIntersections = intersectionPoints;
      });
      print('危險路口載入成功: ${intersectionPoints.length} 個點');
    } catch (e, stackTrace) {
      print(' 熱點資料載入失敗: $e');
      print('堆疊追蹤: $stackTrace');
    }
  }

  Future<void> _checkAndInsertAlert(String userId) async {
    // 如果使用者 ID 是 0 或 "0"，不新增 alert
    if (userId == '0' || userId == 0) return;

    if (_isInDangerZone()) {
      if (_lastAlertPosition == null ||
          _calculateDistance(_currentPosition, _lastAlertPosition!) >
              _alertDistanceThreshold) {
        String category = '';
        if (_showCrimeZones) {
          for (int i = 0; i < _crimePolygons.length; i += 4) {
            if (i + 3 < _crimePolygons.length) {
              List<LatLng> polygon = [
                _crimePolygons[i],
                _crimePolygons[i + 1],
                _crimePolygons[i + 2],
                _crimePolygons[i + 3],
              ];
              if (_isPointInPolygon(_currentPosition, polygon)) {
                category = '犯罪熱點';
                break;
              }
            }
          }
        }

        if (category.isEmpty && _showAccidentZones) {
          for (int i = 0; i < _accidentPolygons.length; i += 4) {
            if (i + 3 < _accidentPolygons.length) {
              List<LatLng> polygon = [
                _accidentPolygons[i],
                _accidentPolygons[i + 1],
                _accidentPolygons[i + 2],
                _accidentPolygons[i + 3],
              ];
              if (_isPointInPolygon(_currentPosition, polygon)) {
                category = '事故多發區';
                break;
              }
            }
          }
        }

        if (category.isEmpty && _showDangerIntersections) {
          for (var intersection in _dangerIntersections) {
            if (_calculateDistance(_currentPosition, intersection) < 50) {
              category = '危險路口';
              break;
            }
          }
        }

        if (category.isNotEmpty) {
          final alert = {
            'area': '${category}',
            'category': '自動記錄',
            'time': DateTime.now().toIso8601String(),
            'userId': userId,
          };
          await DatabaseHelper.instance.insertAlert(alert);
          _lastAlertPosition = _currentPosition;
          print('新增 alert: $category at $_currentPosition');
        }
      }
    }
  }

  //  返回時傳遞位置資料
  void _goBack() {
    Navigator.pop(context, {
      'position': _currentPosition, //  傳回當前位置
      'isInDangerZone': _isInDangerZone(), //  傳回是否在危險區域
      'message': _getDangerZoneMessage(), //  傳回危險訊息
    });
  }

  @override
  Widget build(BuildContext context) {
    final isInDanger = _isInDangerZone();

    return Scaffold(
      appBar: AppBar(
        title: const Text('SafeBuddy Map'),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _goBack,
        ),
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _currentPosition,
              initialZoom: 15.0,
              onTap: (tapPosition, point) {
                setState(() {
                  _currentPosition = point;
                });
                _checkAndInsertAlert(widget.userId);
                print(' 位置已更新: ${point.latitude}, ${point.longitude}');
              },
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.safebuddy',
              ),

              // 犯罪熱點（紅色多邊形
              if (_showCrimeZones && _crimePolygons.isNotEmpty)
                PolygonLayer(
                  polygons: _buildCrimePolygons(),
                ),

              // 事故熱點（橙色多邊形
              if (_showAccidentZones && _accidentPolygons.isNotEmpty)
                PolygonLayer(
                  polygons: _buildAccidentPolygons(),
                ),

              // 危險路口（黃色圓圈）
              if (_showDangerIntersections && _dangerIntersections.isNotEmpty)
                CircleLayer(
                  circles: _dangerIntersections
                      .map((point) => CircleMarker(
                            point: point,
                            color: Colors.yellow.withValues(alpha: 0.5),
                            borderColor: Colors.orange,
                            borderStrokeWidth: 2,
                            radius: 20,
                          ))
                      .toList(),
                ),

              // 當前位置標記
              MarkerLayer(
                markers: [
                  Marker(
                    point: _currentPosition,
                    width: 40,
                    height: 40,
                    child: Container(
                      decoration: BoxDecoration(
                        color: isInDanger ? Colors.red : Colors.blue,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white,
                          width: 3,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: (isInDanger ? Colors.red : Colors.blue)
                                .withValues(alpha: 0.5),
                            blurRadius: 10,
                            spreadRadius: 3,
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.person_pin_circle,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),

          // 危險狀態提示
          if (isInDanger)
            Positioned(
              top: 16,
              left: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.all(12),
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
                    Icon(Icons.warning_amber_rounded,
                        color: Colors.red.shade700),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _getDangerZoneMessage(),
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

          // 圖層切換按鈕
          Positioned(
            bottom: 80,
            right: 16,
            child: Column(
              children: [
                _buildLayerToggle(
                  '犯罪',
                  _showCrimeZones,
                  Colors.red,
                  () => setState(() => _showCrimeZones = !_showCrimeZones),
                ),
                const SizedBox(height: 8),
                _buildLayerToggle(
                  '事故',
                  _showAccidentZones,
                  Colors.orange,
                  () =>
                      setState(() => _showAccidentZones = !_showAccidentZones),
                ),
                const SizedBox(height: 8),
                _buildLayerToggle(
                  '路口',
                  _showDangerIntersections,
                  Colors.yellow,
                  () => setState(() =>
                      _showDangerIntersections = !_showDangerIntersections),
                ),
              ],
            ),
          ),

          // 返回按鈕
          Positioned(
            bottom: 16,
            left: 16,
            right: 16,
            child: ElevatedButton.icon(
              onPressed: _goBack,
              icon: Icon(isInDanger ? Icons.warning : Icons.check_circle),
              label: Text(isInDanger ? '返回（位於危險區域）' : '返回主畫面'),
              style: ElevatedButton.styleFrom(
                backgroundColor: isInDanger ? Colors.red.shade600 : Colors.teal,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLayerToggle(
    String label,
    bool isActive,
    Color color,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isActive ? color : Colors.grey.shade300,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isActive ? Colors.white : Colors.grey.shade700,
            fontWeight: FontWeight.bold,
            fontSize: 12,
          ),
        ),
      ),
    );
  }

  List<Polygon> _buildCrimePolygons() {
    List<Polygon> polygons = [];

    for (int i = 0; i < _crimePolygons.length; i += 4) {
      if (i + 3 < _crimePolygons.length) {
        polygons.add(
          Polygon(
            points: [
              _crimePolygons[i],
              _crimePolygons[i + 1],
              _crimePolygons[i + 2],
              _crimePolygons[i + 3],
            ],
            color: Colors.red.withValues(alpha: 0.3),
            borderColor: Colors.red,
            borderStrokeWidth: 2.0,
            isFilled: true,
          ),
        );
      }
    }

    return polygons;
  }

  // 建立事故區域多邊形列表
  List<Polygon> _buildAccidentPolygons() {
    // 假設每 4 個點組成一個多邊形
    List<Polygon> polygons = [];

    for (int i = 0; i < _accidentPolygons.length; i += 4) {
      if (i + 3 < _accidentPolygons.length) {
        polygons.add(
          Polygon(
            points: [
              _accidentPolygons[i],
              _accidentPolygons[i + 1],
              _accidentPolygons[i + 2],
              _accidentPolygons[i + 3],
            ],
            color: Colors.orange.withValues(alpha: 0.3),
            borderColor: Colors.orange,
            borderStrokeWidth: 2.0,
            isFilled: true,
          ),
        );
      }
    }

    return polygons;
  }
}
