import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'dart:convert';
import 'package:flutter/services.dart';

class MapPage extends StatefulWidget {
  final LatLng initialPosition; //  接收初始位置

  const MapPage({
    super.key,
    required this.initialPosition, //  必須傳入初始位置
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

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    _currentPosition = widget.initialPosition; //  使用傳入的初始位置
    _loadHotZoneData();
  }

  //  新增：檢查是否在危險區域內
  bool _isInDangerZone() {
    // 檢查犯罪熱點
    if (_showCrimeZones &&
        _isPointInPolygon(_currentPosition, _crimePolygons)) {
      return true;
    }

    // 檢查事故熱點
    if (_showAccidentZones &&
        _isPointInPolygon(_currentPosition, _accidentPolygons)) {
      return true;
    }

    // 檢查危險路口（50 公尺範圍內）
    if (_showDangerIntersections) {
      for (var intersection in _dangerIntersections) {
        double distance = _calculateDistance(_currentPosition, intersection);
        if (distance < 50) {
          return true;
        }
      }
    }

    return false;
  }

  //  新增：取得危險區域訊息
  String _getDangerZoneMessage() {
    List<String> dangers = [];

    if (_showCrimeZones &&
        _isPointInPolygon(_currentPosition, _crimePolygons)) {
      dangers.add('犯罪熱點');
    }

    if (_showAccidentZones &&
        _isPointInPolygon(_currentPosition, _accidentPolygons)) {
      dangers.add('事故多發區');
    }

    if (_showDangerIntersections) {
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

    String message = '⚠️ 您位於${dangers.join('、')}';
    if (isNightTime) {
      message += '，且現在是夜間時段，請特別注意安全或結伴同行！';
    } else {
      message += '，請注意周邊環境！';
    }

    return message;
  }

  //  新增：判斷點是否在多邊形內（射線法）
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

  //  新增：計算兩點距離（公尺）
  double _calculateDistance(LatLng point1, LatLng point2) {
    const Distance distance = Distance();
    return distance.as(LengthUnit.Meter, point1, point2);
  }

  Future<void> _loadHotZoneData() async {
    try {
      // 載入犯罪熱點
      final crimeData =
          await rootBundle.loadString('assets/hotzones/crime_zones.json');
      final crimeJson = jsonDecode(crimeData) as List;
      setState(() {
        _crimePolygons = crimeJson
            .map((coords) => LatLng(coords[0] as double, coords[1] as double))
            .toList();
      });

      // 載入事故熱點
      final accidentData =
          await rootBundle.loadString('assets/hotzones/accident_zones.json');
      final accidentJson = jsonDecode(accidentData) as List;
      setState(() {
        _accidentPolygons = accidentJson
            .map((coords) => LatLng(coords[0] as double, coords[1] as double))
            .toList();
      });

      // 載入危險路口
      final intersectionData = await rootBundle
          .loadString('assets/hotzones/danger_intersections.json');
      final intersectionJson = jsonDecode(intersectionData) as List;
      setState(() {
        _dangerIntersections = intersectionJson
            .map((coords) => LatLng(coords[0] as double, coords[1] as double))
            .toList();
      });

      print(' 熱點資料載入成功');
    } catch (e) {
      print('❌ 熱點資料載入失敗: $e');
    }
  }

  //  修改：返回時傳遞位置資料
  void _goBack() {
    Navigator.pop(context, {
      'position': _currentPosition, //  傳回當前位置
      'isInDangerZone': _isInDangerZone(), //  傳回是否在危險區域
      'message': _getDangerZoneMessage(), //  傳回危險訊息
    });
  }

  @override
  Widget build(BuildContext context) {
    //  檢查當前位置是否在危險區域
    final isInDanger = _isInDangerZone();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Map Page'),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _goBack, //  使用自訂返回方法
        ),
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _currentPosition, //  使用當前位置
              initialZoom: 15.0,
              onTap: (tapPosition, point) {
                //  點擊地圖更新位置
                setState(() {
                  _currentPosition = point;
                });
                print('📍 位置已更新: ${point.latitude}, ${point.longitude}');
              },
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.safebuddy',
              ),

              // 犯罪熱點（紅色）
              if (_showCrimeZones && _crimePolygons.isNotEmpty)
                PolygonLayer(
                  polygons: [
                    Polygon(
                      points: _crimePolygons,
                      color: Colors.red.withValues(alpha: 0.3),
                      borderColor: Colors.red,
                      borderStrokeWidth: 2.0,
                      isFilled: true,
                    ),
                  ],
                ),

              // 事故熱點（橙色）
              if (_showAccidentZones && _accidentPolygons.isNotEmpty)
                PolygonLayer(
                  polygons: [
                    Polygon(
                      points: _accidentPolygons,
                      color: Colors.orange.withValues(alpha: 0.3),
                      borderColor: Colors.orange,
                      borderStrokeWidth: 2.0,
                      isFilled: true,
                    ),
                  ],
                ),

              // 危險路口（黃色圓圈）
              if (_showDangerIntersections)
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

              //  當前位置標記（會閃爍提示如果在危險區域）
              MarkerLayer(
                markers: [
                  Marker(
                    point: _currentPosition,
                    width: 40,
                    height: 40,
                    child: Container(
                      decoration: BoxDecoration(
                        color: isInDanger //  危險區域顯示紅色
                            ? Colors.red
                            : Colors.blue,
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
                      child: Icon(
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

          //  新增：當前位置危險狀態提示
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

          //  返回按鈕（顯示危險狀態）
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
}
