import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

class GpsService {
  // 현재 위치 및 GPS 관련 변수
  NLatLng? currentPosition;
  NLatLng? targetPosition;
  NLatLng? lastRealGpsPosition;
  NMarker? gpsMarker;
  NMarker? targetMarker;
  
  // 상태 플래그
  bool isMoving = false;
  bool isGpsMoveEnabled = false;
  
  // 컨트롤러 및 타이머
  NaverMapController? mapController;
  Timer? locationUpdateTimer;
  Timer? movementTimer;
  
  // 이동 속도 (m/s)
  final double speed = 30.0;
  
  // 콜백 함수들
  final Function(NLatLng) onPositionChanged;
  final Function() onMarkerUpdated;
  final Function(bool) onMovingStatusChanged;
  
  GpsService({
    required this.onPositionChanged,
    required this.onMarkerUpdated,
    required this.onMovingStatusChanged,
  });
  
  // 위치 권한 요청
  Future<void> requestLocationPermission() async {
    var requestStatus = await Permission.location.request();
    var status = await Permission.location.status;
    if (requestStatus.isPermanentlyDenied || status.isPermanentlyDenied) {
      openAppSettings();
    }
  }
  
  // 서비스 초기화
  void initialize(NaverMapController controller) {
    mapController = controller;
    
    // 현재 위치 가져오기
    getCurrentLocation(true);
    
    // 주기적으로 현재 위치 업데이트
    locationUpdateTimer = Timer.periodic(Duration(seconds: 5), (timer) {
      if (!isMoving) {
        getCurrentLocation(false);
      }
    });
  }
  
  // 서비스 종료 시 리소스 정리
  void dispose() {
    locationUpdateTimer?.cancel();
    movementTimer?.cancel();
    
    // 마커 제거
    if (mapController != null) {
      if (gpsMarker != null) {
        mapController!.deleteOverlay(gpsMarker!.info);
      }
      if (targetMarker != null) {
        mapController!.deleteOverlay(targetMarker!.info);
      }
    }
  }
  
  // 현재 GPS 위치 가져오기
  Future<void> getCurrentLocation(bool isInitial) async {
    try {
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high
      );
      
      // 실제 GPS 위치 저장
      lastRealGpsPosition = NLatLng(position.latitude, position.longitude);
      
      // GPS 이동 모드가 비활성화되었고, 이동 중이 아닐 때만 현재 표시 위치를 업데이트
      if (!isGpsMoveEnabled && !isMoving) {
        currentPosition = lastRealGpsPosition;
        
        // 맵이 준비되었고 최초 위치 설정이면 카메라 이동
        if (mapController != null && isInitial && currentPosition != null) {
          mapController!.updateCamera(
            NCameraUpdate.scrollAndZoomTo(
              target: currentPosition!,
              zoom: 17.0,
            ),
          );
        }
        
        // GPS 마커 업데이트
        updateGpsMarker();
        
        // 위치 변경 알림
        onPositionChanged(currentPosition!);
      }
    } catch (e) {
      print('위치 가져오기 실패: $e');
    }
  }
  
  // GPS 마커 생성 또는 업데이트
  void updateGpsMarker() {
    if (currentPosition == null || mapController == null) return;
    
    try {
      if (gpsMarker != null) {
        mapController!.deleteOverlay(gpsMarker!.info);
      }
      
      gpsMarker = NMarker(
        id: 'gps_marker',
        position: currentPosition!,
        icon: NOverlayImage.fromAssetImage("assets/gps_marker.png"),
        size: Size(24, 24),
        anchor: NPoint(0.5, 0.5),
      );
      
      mapController!.addOverlay(gpsMarker!);
      
      // 마커 업데이트 알림
      onMarkerUpdated();
    } catch (e) {
      print('GPS 마커 업데이트 중 오류 발생: $e');
    }
  }
  
  // 지도 탭 이벤트 처리
  void onMapTapped(NLatLng tappedPosition) {
    if (isGpsMoveEnabled && !isMoving && mapController != null && currentPosition != null) {
      try {
        // 이전 타이머 정리
        movementTimer?.cancel();
        
        // 기존 타겟 마커가 있다면 제거
        if (targetMarker != null) {
          mapController!.deleteOverlay(targetMarker!.info);
          targetMarker = null;
        }
        
        // 타겟 마커 생성
        targetMarker = NMarker(
          id: 'target_marker',
          position: tappedPosition,
          icon: NOverlayImage.fromAssetImage("assets/pin.png"),
          size: Size(36, 36),
          anchor: NPoint(0.5, 1.0),
        );
        mapController!.addOverlay(targetMarker!);
        
        targetPosition = tappedPosition;
        
        // 이동 시작
        startMoving();
      } catch (e) {
        print('지도 클릭 처리 중 오류 발생: $e');
      }
    }
  }
  
  // GPS 이동 시뮬레이션 시작
  void startMoving() {
    if (targetPosition == null || currentPosition == null || mapController == null) return;

    try {
      isMoving = true;
      onMovingStatusChanged(true);
      
      const int updateRateMs = 100; // 업데이트 간격 (ms)
      double distance = calculateDistance(currentPosition!, targetPosition!);
      double totalTime = distance / speed; // 총 이동 시간 (초)
      int steps = (totalTime * 1000 / updateRateMs).round(); // 총 스텝 수
      
      // 최소 스텝 수 설정
      steps = steps < 1 ? 1 : steps;
      int currentStep = 0;
      
      // 시작 위치와 목표 위치 저장 (중간에 변경되지 않도록)
      final NLatLng startPosition = currentPosition!;
      final NLatLng endPosition = targetPosition!;
      
      // 초기 줌 레벨 설정 (이동 시 줌 확대)
      mapController!.updateCamera(
        NCameraUpdate.scrollAndZoomTo(
          target: startPosition,
          zoom: 18.0, // 이동 시작 시 확대된 줌 레벨
        ),
      );

      movementTimer = Timer.periodic(Duration(milliseconds: updateRateMs), (timer) {
        try {
          if (mapController == null) {
            timer.cancel();
            return;
          }

          if (!isMoving) {
            timer.cancel();
            return;
          }

          currentStep++;
          double fraction = currentStep / steps;
          
          if (fraction >= 1.0) {
            // 이동 완료
            timer.cancel();
            currentPosition = endPosition;
            isMoving = false;
            onMovingStatusChanged(false);
            
            // 기존 마커 제거하고 새 위치에 다시 생성
            if (gpsMarker != null) {
              mapController!.deleteOverlay(gpsMarker!.info);
              gpsMarker = NMarker(
                id: 'gps_marker',
                position: endPosition,
                icon: NOverlayImage.fromAssetImage("assets/gps_marker.png"),
                size: Size(24, 24),
                anchor: NPoint(0.5, 0.5),
              );
              mapController!.addOverlay(gpsMarker!);
            }
            
            // 타겟 마커 제거
            if (targetMarker != null) {
              mapController!.deleteOverlay(targetMarker!.info);
              targetMarker = null;
            }
            
            // 목표 위치에 카메라 이동
            mapController!.updateCamera(
              NCameraUpdate.scrollAndZoomTo(target: endPosition),
            );
            
            // 목표 위치 초기화
            targetPosition = null;
            
            // 위치 변경 알림
            onPositionChanged(currentPosition!);
            
            return;
          }

          // 다음 위치 계산 및 업데이트
          NLatLng nextPosition = interpolate(startPosition, endPosition, fraction);
          
          currentPosition = nextPosition;
          
          // 기존 마커 제거하고 새 위치에 다시 생성
          if (gpsMarker != null) {
            mapController!.deleteOverlay(gpsMarker!.info);
            gpsMarker = NMarker(
              id: 'gps_marker',
              position: nextPosition,
              icon: NOverlayImage.fromAssetImage("assets/gps_marker.png"),
              size: Size(24, 24),
              anchor: NPoint(0.5, 0.5),
            );
            mapController!.addOverlay(gpsMarker!);
          }
          
          // 카메라도 함께 이동
          mapController!.updateCamera(
            NCameraUpdate.scrollAndZoomTo(target: nextPosition),
          );
          
          // 위치 변경 알림
          onPositionChanged(currentPosition!);
        } catch (e) {
          print('이동 시뮬레이션 중 오류 발생: $e');
          timer.cancel();
          isMoving = false;
          onMovingStatusChanged(false);
        }
      });
    } catch (e) {
      print('이동 시작 중 오류 발생: $e');
      isMoving = false;
      onMovingStatusChanged(false);
    }
  }
  
  // GPS 이동 모드 토글
  void toggleGpsMoveMode() {
    isGpsMoveEnabled = !isGpsMoveEnabled;
    
    if (!isGpsMoveEnabled) {
      // GPS 이동 모드를 해제할 때:
      // 1. 이동 중이면 이동을 계속 유지
      // 2. 이동 중이 아니면 실제 GPS 위치로 복원
      if (!isMoving && lastRealGpsPosition != null) {
        currentPosition = lastRealGpsPosition;
        updateGpsMarker();
        onPositionChanged(currentPosition!);
      }
    }
  }
  
  // 두 좌표 사이의 거리 계산 (미터 단위)
  double calculateDistance(NLatLng start, NLatLng end) {
    const double earthRadius = 6371000; // 지구 반경 (미터)
    double dLat = degreesToRadians(end.latitude - start.latitude);
    double dLng = degreesToRadians(end.longitude - start.longitude);
    double a = sin(dLat / 2) * sin(dLat / 2) +
        cos(degreesToRadians(start.latitude)) *
            cos(degreesToRadians(end.latitude)) *
            sin(dLng / 2) * sin(dLng / 2);
    double c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return earthRadius * c;
  }

  // 각도를 라디안으로 변환
  double degreesToRadians(double degrees) {
    return degrees * pi / 180;
  }

  // 두 좌표 사이의 보간 (Interpolation)
  NLatLng interpolate(NLatLng start, NLatLng end, double fraction) {
    double lat = start.latitude + (end.latitude - start.latitude) * fraction;
    double lng = start.longitude + (end.longitude - start.longitude) * fraction;
    return NLatLng(lat, lng);
  }
}