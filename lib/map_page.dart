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

  List<List<LatLng>> high = [];
  List<List<LatLng>> medium = [];
  List<List<LatLng>> low = [];

  bool _showHighZones = true;
  bool _showMediumZones = true;
  bool _showLowZones = true;

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
    //  檢查高風險熱點（每個多邊形獨立）
    if (_showHighZones && high.isNotEmpty) {
      for (var polygon in high) {
        if (_isPointInPolygon(_currentPosition, polygon)) {
          return true;
        }
      }
    }

    //  檢查中風險熱點（每個多邊形獨立）
    if (_showMediumZones && medium.isNotEmpty) {
      for (var polygon in medium) {
        if (_isPointInPolygon(_currentPosition, polygon)) {
          return true;
        }
      }
    }

    //  檢查低風險熱點（每個多邊形獨立）
    if (_showMediumZones && low.isNotEmpty) {
      for (var polygon in low) {
        if (_isPointInPolygon(_currentPosition, polygon)) {
          return true;
        }
      }
    }

    return false;
  }

  String _getDangerZoneMessage() {
    List<String> dangers = [];

    // 檢查高風險熱區
    if (_showHighZones && high.isNotEmpty) {
      for (var polygon in high) {
        if (_isPointInPolygon(_currentPosition, polygon)) {
          dangers.add('高風險熱區');
          break;
        }
      }
    }

    // 檢查中風險熱區
    if (_showMediumZones && medium.isNotEmpty) {
      for (var polygon in medium) {
        if (_isPointInPolygon(_currentPosition, polygon)) {
          dangers.add('中風險熱區');
          break;
        }
      }
    }

    // 檢查低風險熱區
    if (_showLowZones && low.isNotEmpty) {
      for (var polygon in low) {
        if (_isPointInPolygon(_currentPosition, polygon)) {
          dangers.add('低風險熱區');
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
      // 載入高風險熱區（改用 GeoJSON）
      final highData = await rootBundle
          .loadString('assets/hotzones/accident_hotzones_high.geojson');
      final highGeoJson = jsonDecode(highData);

      List<List<LatLng>> highPolygonsList = [];

      // 解析 GeoJSON FeatureCollection
      if (highGeoJson['type'] == 'FeatureCollection') {
        final features = highGeoJson['features'] as List;

        for (var feature in features) {
          if (feature['geometry']['type'] == 'Polygon') {
            final coordinates = feature['geometry']['coordinates'][0] as List;

            List<LatLng> polygon = [];
            for (var coord in coordinates) {
              polygon.add(LatLng(
                coord[1] as double, // 緯度
                coord[0] as double, // 經度
              ));
            }

            highPolygonsList.add(polygon);
          }
        }
      }

      setState(() {
        high = highPolygonsList;
      });
      print('高風險熱區載入成功: ${high.length} 個區域');

      // 載入中風險熱區（改用 GeoJSON）
      final mediumData = await rootBundle
          .loadString('assets/hotzones/accident_hotzones_medium.geojson');
      final mediumGeoJson = jsonDecode(mediumData);

      List<List<LatLng>> mediumPolygonsList = [];

      // 解析 GeoJSON FeatureCollection
      if (mediumGeoJson['type'] == 'FeatureCollection') {
        final features = mediumGeoJson['features'] as List;

        for (var feature in features) {
          if (feature['geometry']['type'] == 'Polygon') {
            final coordinates = feature['geometry']['coordinates'][0] as List;

            List<LatLng> polygon = [];
            for (var coord in coordinates) {
              polygon.add(LatLng(
                coord[1] as double, // 緯度
                coord[0] as double, // 經度
              ));
            }

            mediumPolygonsList.add(polygon);
          }
        }
      }

      setState(() {
        medium = mediumPolygonsList;
      });
      print('中風險熱區載入成功: ${medium.length} 個區域');

      // 載入低風險熱區（改用 GeoJSON）
      final lowData = await rootBundle
          .loadString('assets/hotzones/accident_hotzones_low.geojson');
      final lowGeoJson = jsonDecode(lowData);

      List<List<LatLng>> lowPolygonsList = [];

      // 解析 GeoJSON FeatureCollection
      if (lowGeoJson['type'] == 'FeatureCollection') {
        final features = lowGeoJson['features'] as List;

        for (var feature in features) {
          if (feature['geometry']['type'] == 'Polygon') {
            final coordinates = feature['geometry']['coordinates'][0] as List;

            List<LatLng> polygon = [];
            for (var coord in coordinates) {
              polygon.add(LatLng(
                coord[1] as double, // 緯度
                coord[0] as double, // 經度
              ));
            }

            lowPolygonsList.add(polygon);
          }
        }
      }

      setState(() {
        low = lowPolygonsList;
      });
      print('低風險熱區載入成功: ${low.length} 個點');
    } catch (e, stackTrace) {
      print('❌ 熱點資料載入失敗: $e');
      print('堆疊追蹤: $stackTrace');
    }
  }

  Future<void> _checkAndInsertAlert(String userId) async {
    if (userId == '0' || userId == 0) return;

    if (_isInDangerZone()) {
      if (_lastAlertPosition == null ||
          _calculateDistance(_currentPosition, _lastAlertPosition!) >
              _alertDistanceThreshold) {
        String category = '';

        // 檢查高風險熱區
        if (_showHighZones) {
          for (var polygon in high) {
            if (_isPointInPolygon(_currentPosition, polygon)) {
              category = '高風險熱區';
              break;
            }
          }
        }

        // 檢查中風險熱區
        if (category.isEmpty && _showMediumZones) {
          for (var polygon in medium) {
            if (_isPointInPolygon(_currentPosition, polygon)) {
              category = '中風險熱區';
              break;
            }
          }
        }

        // 檢查低風險熱區
        if (category.isEmpty && _showLowZones) {
          for (var polygon in low) {
            if (_isPointInPolygon(_currentPosition, polygon)) {
              category = '低風險熱區';
              break;
            }
          }
        }

        if (category.isNotEmpty) {
          final alert = {
            'area': category,
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
              if (_showHighZones && high.isNotEmpty)
                PolygonLayer(
                  polygons: _buildHighRiskPolygons(),
                ),

              // 事故熱點（橙色多邊形
              if (_showMediumZones && medium.isNotEmpty)
                PolygonLayer(
                  polygons: _buildMediumPolygons(),
                ),

              // 危險路口（黃色圓圈）
              // 事故熱點（橙色多邊形
              if (_showLowZones && low.isNotEmpty)
                PolygonLayer(
                  polygons: _buildLowRiskPolygons(),
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
                  '高風險', // 改這裡
                  _showHighZones,
                  Colors.red,
                  () => setState(() => _showHighZones = !_showHighZones),
                ),
                const SizedBox(height: 8),
                _buildLayerToggle(
                  '中風險', // 改這裡
                  _showMediumZones,
                  Colors.orange,
                  () => setState(() => _showMediumZones = !_showMediumZones),
                ),
                const SizedBox(height: 8),
                _buildLayerToggle(
                  '低風險', // 改這裡
                  _showLowZones,
                  Colors.yellow,
                  () => setState(() => _showLowZones = !_showLowZones),
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

  // 改函數名稱和註解
  List<Polygon> _buildHighRiskPolygons() {
    return high.map((polygon) {
      return Polygon(
        points: polygon,
        color: Colors.red.withValues(alpha: 0.3),
        borderColor: Colors.red,
        borderStrokeWidth: 2.0,
        isFilled: true,
      );
    }).toList();
  }

  // 保持中風險不變
  List<Polygon> _buildMediumPolygons() {
    return medium.map((polygon) {
      return Polygon(
        points: polygon,
        color: Colors.orange.withValues(alpha: 0.3),
        borderColor: Colors.orange,
        borderStrokeWidth: 2.0,
        isFilled: true,
      );
    }).toList();
  }

  // 新增低風險多邊形函數
  List<Polygon> _buildLowRiskPolygons() {
    return low.map((polygon) {
      return Polygon(
        points: polygon,
        color: Colors.yellow.withValues(alpha: 0.3),
        borderColor: Colors.yellow.shade700,
        borderStrokeWidth: 2.0,
        isFilled: true,
      );
    }).toList();
  }
}
