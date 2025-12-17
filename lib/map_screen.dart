import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'gps_service.dart';
import 'route_service.dart'; // Ensure this file contains the RouteService class definition
import 'route_waypoint.dart';  // 추가된 import
import 'route_sidebar.dart';   // 추가된 import

class MapScreen extends StatefulWidget {
  @override
  _MapScreenState createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> with SingleTickerProviderStateMixin {
  final String directionsUrl = 'http://127.0.0.1:8081/test/directions';
  final String waypointsUrl = 'http://127.0.0.1:8081/test/route';
  late NaverMapController _mapController;
  List<NLatLng> _pathCoordinates = [];
  List<NMarker> _markers = [];
  bool _isMapReady = false;
  bool _isLoading = false;
  
  // GPS 서비스
  late GpsService _gpsService;
  
  // 경로 서비스
  late RouteService _routeService;
  
  // 웨이포인트 관리자
  final RouteWaypointManager _waypointManager = RouteWaypointManager();
  
  // 알림 서비스
  late FlutterLocalNotificationsPlugin _notificationsPlugin;
  late NotificationDetails _notificationDetails;
  
  // 상태 변수 
  bool _isMoving = false;
  NLatLng? _currentPosition;
  
  // 안내 메시지
  String? _currentInstruction;
  bool _showInstruction = false;
  Timer? _instructionTimer;
  
  // 사이드바 컨트롤러
  late AnimationController _sidebarController;
  bool _isSidebarOpen = false;
  
  @override
  void initState() {
    super.initState();
    
    // 사이드바 애니메이션 컨트롤러 초기화
    _sidebarController = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 300),
    );
    
    // 알림 초기화
    _initializeNotifications();
    
    // 경로 서비스 초기화
    _routeService = RouteService(
      onNavigationInstructionChanged: (instruction) {
        _showNavigationInstruction(instruction);
      },
      onWaypointReached: (waypointNumber) {
        _showWaypointNotification(waypointNumber);
        _waypointManager.updateWaypointStatus(waypointNumber);
        setState(() {}); // UI 업데이트
      },
    );
    
    // GPS 서비스 초기화
    _gpsService = GpsService(
      onPositionChanged: (position) {
        setState(() {
          _currentPosition = position;
        });
        
        // 경로 서비스에 위치 업데이트 전달
        _routeService.updatePosition(position);
      },
      onMarkerUpdated: () {
        // 마커가 업데이트되었을 때 필요한 UI 업데이트
        setState(() {});
      },
      onMovingStatusChanged: (isMoving) {
        setState(() {
          _isMoving = isMoving;
        });
      },
    );
    
    // 위치 권한 요청
    _gpsService.requestLocationPermission();
  }
  
  // 알림 초기화
  void _initializeNotifications() async {
    _notificationsPlugin = FlutterLocalNotificationsPlugin();
    
    // Android 설정
    var androidInitSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    
    // iOS 설정
    var iOSInitSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    
    // 초기화 설정
    var initSettings = InitializationSettings(
      android: androidInitSettings, 
      iOS: iOSInitSettings
    );
    
    // 초기화 및 알림 권한 요청
    await _notificationsPlugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (NotificationResponse details) {
        print("알림 응답 수신: ${details.payload}");
      },
    );
    
    // Android에서 알림 채널 생성
    var androidChannelSpecifics = AndroidNotificationDetails(
      'waypoint_channel', 
      '웨이포인트 알림',
      channelDescription: '웨이포인트 도달 시 알림',
      importance: Importance.high,
      priority: Priority.high,
      enableVibration: true,
      playSound: true,
    );
    
    // iOS 알림 설정
    var iOSChannelSpecifics = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );
    
    // 알림 채널 설정 저장
    _notificationDetails = NotificationDetails(
      android: androidChannelSpecifics,
      iOS: iOSChannelSpecifics,
    );
    
    print("알림 서비스 초기화 완료");
  }
  
  @override
  void dispose() {
    _gpsService.dispose();
    _instructionTimer?.cancel();
    _sidebarController.dispose();
    super.dispose();
  }
  
  // 사이드바 토글 함수
  void _toggleSidebar() {
    setState(() {
      _isSidebarOpen = !_isSidebarOpen;
      if (_isSidebarOpen) {
        _sidebarController.forward();
      } else {
        _sidebarController.reverse();
      }
    });
  }
  
  /// 📌 경로 및 경유지 데이터 가져오기
  Future<void> _fetchRouteAndWaypoints() async {
    if (!_isMapReady) return;
    
    try {
      await _fetchRoute();
      await _fetchWaypoints();
      _updateRouteInformation();
    } catch (e) {
      print('경로 및 경유지 가져오기 중 오류: $e');
      _showSnackBarMessage('경로 데이터 가져오기 실패: $e');
    }
  }

  /// 📌 경유지 가져오기 (`/test/route`)
  Future<void> _fetchWaypoints() async {
    if (!_isMapReady) return;
    
    try {
      final response = await http.get(
        Uri.parse(waypointsUrl),
        headers: {
          'Accept-Charset': 'UTF-8',
          'Content-Type': 'application/json; charset=UTF-8',
        },
      );
      
      if (response.statusCode == 200) {
        // 응답을 UTF-8로 디코딩
        final String decodedBody = utf8.decode(response.bodyBytes);
        final data = jsonDecode(decodedBody);
        
        final List<dynamic> waypointsRaw = data['orderedCoordinates'];
        final List<List<double>> waypoints = waypointsRaw.map((coord) => List<double>.from(coord)).toList();

        print("웨이포인트 데이터 가져옴: ${waypoints.length}개");

        // 경로 서비스에 웨이포인트 데이터 전달
        _routeService.setWaypointsData(waypoints);

        // 기존 마커 제거
        for (var marker in _markers) {
          if (_isMapReady) {
            _mapController.deleteOverlay(marker.info);
          }
        }

        List<NMarker> markers = [];
        for (int i = 0; i < waypoints.length; i++) {
          final lat = waypoints[i][0];
          final lng = waypoints[i][1];
          markers.add(
            NMarker(
              id: 'waypoint_marker_$i',
              position: NLatLng(lat, lng),
              caption: NOverlayCaption(
                text: '${i + 1}',
              ),
            ),
          );
        }

        setState(() {
          _markers = markers;
          _drawMarkers();
        });
        
        _showSnackBarMessage('${waypoints.length}개의 경유지 데이터를 가져왔습니다.');
      } else {
        print('경유지 데이터를 가져오지 못했습니다. 상태 코드: ${response.statusCode}');
        _showSnackBarMessage('경유지 데이터를 가져오지 못했습니다.');
      }
    } catch (e) {
      print('경유지 데이터 요청 중 오류 발생: $e');
      _showSnackBarMessage('경유지 데이터 요청 오류: $e');
    }
  }
  
  Future<void> _fetchRoute() async {
    if (!_isMapReady) return;
    
    setState(() => _isLoading = true);
    try {
      final response = await http.get(
        Uri.parse(directionsUrl),
        headers: {
          'Accept-Charset': 'UTF-8',
          'Content-Type': 'application/json; charset=UTF-8',
        },
      );
      
      if (response.statusCode == 200) {
        // 응답을 UTF-8로 디코딩
        final String decodedBody = utf8.decode(response.bodyBytes);
        final data = jsonDecode(decodedBody);
        
        final path = (data['route']['path'] as List).map((coords) {
          return NLatLng((coords[0] as num?)?.toDouble() ?? 0.0, (coords[1] as num?)?.toDouble() ?? 0.0);
        }).toList();
        
        print("경로 데이터 가져옴: ${path.length}개 좌표");
        
        // 가이드 포인트 추출
        List<Map<String, dynamic>> guidePoints = [];
        if (data['route']['guide'] != null) {
          guidePoints = (data['route']['guide'] as List).map((guide) {
            // 문자열이 포함된 필드는 별도 처리
            String instructions = guide['instructions'] as String? ?? '';
            
            return {
              'pointIndex': guide['pointIndex'] as int,
              'instructions': instructions,
              'type': guide['type'] as int,
              'distance': guide['distance'] as int,
              'duration': guide['duration'] as int,
            };
          }).toList();
          
          print("안내 포인트: ${guidePoints.length}개");
        }
        
        setState(() {
          // 기존 경로 삭제
          _mapController.clearOverlays(type: NOverlayType.pathOverlay);
          
          _pathCoordinates = path;
          
          // 경로 서비스에 경로 데이터 전달
          _routeService.setRouteData(path, guidePoints);
          
          if (_pathCoordinates.isNotEmpty) {
            // 1단계: 전체 경로를 볼 수 있게 카메라 조정
            // 경로의 시작점과 끝점으로 경계 생성
            NLatLng firstCoord = _pathCoordinates.first;
            NLatLng lastCoord = _pathCoordinates.last;
            
            // 모든 좌표를 순회하며 최대/최소 좌표 찾기
            double minLat = firstCoord.latitude;
            double maxLat = firstCoord.latitude;
            double minLng = firstCoord.longitude;
            double maxLng = firstCoord.longitude;
            
            for (NLatLng coord in _pathCoordinates) {
              minLat = min(minLat, coord.latitude);
              maxLat = max(maxLat, coord.latitude);
              minLng = min(minLng, coord.longitude);
              maxLng = max(maxLng, coord.longitude);
            }
            
            // 경계 생성
            NLatLngBounds bounds = NLatLngBounds(
              southWest: NLatLng(minLat, minLng),
              northEast: NLatLng(maxLat, maxLng),
            );
            
            // 카메라 업데이트 - 전체 경로 표시
            _mapController.updateCamera(
              NCameraUpdate.fitBounds(
                bounds,
                padding: EdgeInsets.all(50),
              ),
            );
            
            // 2단계: 잠시 후 출발 지점으로 줌인 (딜레이 추가)
            Future.delayed(Duration(milliseconds: 1500), () {
              if (!mounted) return;
              
              // 출발 지점(첫 번째 좌표)으로 이동하고 확대
              _mapController.updateCamera(
                NCameraUpdate.scrollAndZoomTo(
                  target: _pathCoordinates.first,
                  zoom: 17.0, // 확대 레벨
                ),
              );
            });
          }
        });
        
        _showSnackBarMessage('경로 데이터를 가져왔습니다.');
      } else {
        print('경로 데이터를 가져오지 못했습니다. 상태 코드: ${response.statusCode}');
        _showSnackBarMessage('경로 데이터를 가져오지 못했습니다.');
      }
    } catch (e) {
      print('경로 데이터 요청 중 오류 발생: $e');
      _showSnackBarMessage('경로 데이터 요청 오류: $e');
    }
    setState(() => _isLoading = false);
  }
  
    // 1. _updateRouteInformation() 메서드에서 자동 사이드바 열림 제거
    void _updateRouteInformation() {
      // 경로 정보 업데이트
      _waypointManager.updateWaypoints(
        coordinates: _routeService.waypoints,
        visitedIndices: _routeService.visitedWaypointIndices,
        calculateDistance: _routeService.calculateDistance,
      );
      
      // UI 업데이트
      setState(() {});
    }
    // 2. 현재 이동 중인 구간 계산 메서드 추가
    int _getCurrentSegmentIndex() {
      if (_currentPosition == null || _waypointManager.waypoints.isEmpty || _waypointManager.waypoints.length < 2) {
        return -1;
      }
      
      // 가장 최근에 도달한 웨이포인트 찾기
      int lastReachedIndex = -1;
      for (int i = 0; i < _waypointManager.waypoints.length; i++) {
        if (_waypointManager.waypoints[i].isReached) {
          lastReachedIndex = i;
        } else {
          break;
        }
      }
      
      // 다음 웨이포인트로 가는 중
      if (lastReachedIndex >= 0 && lastReachedIndex < _waypointManager.waypoints.length - 1) {
        return lastReachedIndex;
      }
      
      return -1; // 이동 중인 구간 없음
    }
  
  void _drawMarkers() {
    if (!_isMapReady) return;
    
    try {
      for (final marker in _markers) {
        _mapController.addOverlay(marker);
      }
    } catch (e) {
      print('마커 그리기 중 오류 발생: $e');
    }
  }
  
  // 안내 메시지 표시
  void _showNavigationInstruction(String instruction) {
    // 혹시 모를 인코딩 이슈를 방지하기 위해 디코딩 시도
    String decodedInstruction;
    try {
      // 이미 깨진 문자열이 들어올 경우를 대비한 예외 처리
      decodedInstruction = instruction;
    } catch (e) {
      print('메시지 디코딩 중 오류: $e');
      decodedInstruction = instruction; // 원본 유지
    }

    setState(() {
      _currentInstruction = decodedInstruction;
      _showInstruction = true;
    });
    
    // 이전 타이머 취소
    _instructionTimer?.cancel();
    
    // 10초 후 안내 메시지 숨기기
    _instructionTimer = Timer(Duration(seconds: 10), () {
      if (mounted) {
        setState(() {
          _showInstruction = false;
        });
      }
    });
  }
  
  // 웨이포인트 도달 알림
  void _showWaypointNotification(int waypointNumber) async {
    try {
      print("웨이포인트 $waypointNumber 알림 시도");
      
      await _notificationsPlugin.show(
        waypointNumber, // 고유 ID로 웨이포인트 번호 사용
        '웨이포인트 도달',
        '웨이포인트 ${waypointNumber}에 도달했습니다!',
        _notificationDetails,
        payload: 'waypoint_$waypointNumber',
      );
      
      // 알림을 보낸 후에 UI에도 표시
      _showSnackBarMessage('웨이포인트 ${waypointNumber}에 도달했습니다!');
      
      print("웨이포인트 $waypointNumber 알림 전송 완료");
    } catch (e) {
      print("웨이포인트 알림 발송 중 오류: $e");
      
      // 알림에 실패해도 UI에는 표시
      _showSnackBarMessage('웨이포인트 ${waypointNumber}에 도달했습니다!');
    }
  }
  
  // UI 메시지 표시를 위한 SnackBar 함수
  void _showSnackBarMessage(String message) {
    if (!mounted) return;
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: TextStyle(fontFamily: 'NotoSansKR'),
        ),
        duration: Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
        margin: EdgeInsets.only(bottom: 100, left: 20, right: 20),
      ),
    );
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('경로 안내', style: TextStyle(fontFamily: 'NotoSansKR')),
        actions: [
          // 사이드바 토글 버튼
          IconButton(
            icon: Icon(_isSidebarOpen ? Icons.arrow_forward_ios : Icons.arrow_back_ios),
            onPressed: _toggleSidebar,
          ),
        ],
      ),
      body: Stack(
        children: [
          NaverMap(
            options: const NaverMapViewOptions(
              locationButtonEnable: false,
              indoorEnable: false,
              nightModeEnable: false,
              liteModeEnable: false,
              buildingHeight: 1.0,
              logoMargin: EdgeInsets.only(bottom: 20, right: 20),
            ),  
            onMapReady: (controller) {
              setState(() {
                _mapController = controller;
                _isMapReady = true;
                
                // GPS 서비스에 컨트롤러 전달
                _gpsService.initialize(controller);
                
                // 경로 서비스에 컨트롤러 전달
                _routeService.initialize(controller);
              });
            },
            onMapTapped: (point, latLng) {
              _gpsService.onMapTapped(latLng);
            },
          ),
          
          // 사이드바 (경로 정보)
      if (_waypointManager.waypoints.isNotEmpty && _isSidebarOpen)
         RouteSidebar(
    waypoints: _waypointManager.waypoints,
    totalDistance: _waypointManager.totalDistance,
    controller: _sidebarController,
    onClose: _toggleSidebar,
    currentSegmentIndex: _getCurrentSegmentIndex(),
  ),
          
          if (_isLoading) Center(child: CircularProgressIndicator()),
          
          // 경로 안내 메시지
          if (_showInstruction && _currentInstruction != null)
            Positioned(
              top: 20,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.8),
                    borderRadius: BorderRadius.circular(25),
                  ),
                  child: Text(
                    _currentInstruction!,
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      fontFamily: 'NotoSansKR', // 한글 지원 폰트 지정
                    ),
                  ),
                ),
              ),
            ),
          
          // 줌 버튼
          Positioned(
            bottom: 80,
            right: 20,
            child: Column(
              children: [
                FloatingActionButton(
                  onPressed: () {
                    if (_isMapReady) {
                      _mapController.updateCamera(NCameraUpdate.zoomIn());
                    }
                  },
                  child: Icon(Icons.add),
                  mini: true,
                ),
                SizedBox(height: 10),
                FloatingActionButton(
                  onPressed: () {
                    if (_isMapReady) {
                      _mapController.updateCamera(NCameraUpdate.zoomOut());
                    }
                  },
                  child: Icon(Icons.remove),
                  mini: true,
                ),
              ],
            ),
          ),
          
          // 경로 요청 버튼
          Positioned(
            bottom: 140,
            left: 20,
            child: FloatingActionButton(
              onPressed: _fetchRouteAndWaypoints, 
              child: Icon(Icons.directions),
            ),
          ),
          
          // GPS 이동 모드 버튼 (아이콘만 표시하도록 수정)
          Positioned(
            bottom: 70,
            left: 20,
            child: FloatingActionButton(
              onPressed: () {
                _gpsService.toggleGpsMoveMode();
                setState(() {}); // UI 업데이트
              },
              backgroundColor: _gpsService.isGpsMoveEnabled ? Colors.green : Colors.blue,
              child: Icon(_gpsService.isGpsMoveEnabled ? Icons.gps_fixed : Icons.gps_not_fixed),
            ),
          ),
          
          // 현재 이동 상태 및 위치 정보 표시
          Positioned(
            top: 80, // 안내 메시지가 있을 경우를 고려해 위치 조정
            left: 0,
            right: 0,
            child: Center(
              child: Column(
                children: [
                  if (_isMoving)
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.7),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '목적지로 이동 중...',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'NotoSansKR',
                        ),
                      ),
                    ),
                  if (_currentPosition != null && _gpsService.isGpsMoveEnabled)
                    Container(
                      margin: EdgeInsets.only(top: 8),
                      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.5),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '현재 위치: ${_currentPosition!.latitude.toStringAsFixed(6)}, ${_currentPosition!.longitude.toStringAsFixed(6)}',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontFamily: 'NotoSansKR',
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}