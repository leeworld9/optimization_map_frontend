import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';

class RouteService {
  // 경로 데이터
  List<NLatLng> pathCoordinates = [];
  List<Map<String, dynamic>> guidePoints = [];
  List<List<double>> waypoints = [];
  
  // 네이버맵 컨트롤러
  NaverMapController? mapController;
  
  // 진행 상태 관련 변수
  int lastPassedPathIndex = 0;
  int lastGuideIndex = -1;
  Set<int> visitedWaypointIndices = {};
  
  // 안내 상태 관련 변수
  Map<int, bool> preAnnouncedGuides = {}; // 미리 안내한 가이드 포인트 기록
  
  // 경로 오버레이
  NPathOverlay? completedPathOverlay;
  NPathOverlay? remainingPathOverlay;
  
  // 콜백 함수
  final Function(String) onNavigationInstructionChanged;
  final Function(int) onWaypointReached;
  
  // 설정값
  final double waypointProximityThreshold = 30.0; // 웨이포인트 도달 거리 (미터)
  final double nextGuidePointPreAnnouncementDistance = 100.0; // 안내 미리 알림 거리 (미터)
  final double nextGuidePointThreshold = 20.0; // 안내 포인트 도달 거리 (미터)
  
  // 디버깅용 로그
  bool enableDebugLog = true;
  
  RouteService({
    required this.onNavigationInstructionChanged,
    required this.onWaypointReached,
  });
  
  // 초기화
  void initialize(NaverMapController controller) {
    mapController = controller;
    debugLog("RouteService initialized");
  }
  
  // 경로 데이터 설정
  void setRouteData(List<NLatLng> path, List<Map<String, dynamic>> guide) {
    pathCoordinates = path;
    guidePoints = guide;
    lastPassedPathIndex = 0;
    lastGuideIndex = -1;
    preAnnouncedGuides.clear();
    
    debugLog("Route data set: ${path.length} coordinates, ${guide.length} guide points");
    
    // 경로 오버레이 초기화
    updateRouteOverlay();
  }
  
  // 웨이포인트 데이터 설정
  void setWaypointsData(List<List<double>> points) {
    waypoints = points;
    visitedWaypointIndices.clear();
    debugLog("Waypoints data set: ${points.length} waypoints");
  }
  
  // 모든 데이터 초기화
  void reset() {
    pathCoordinates.clear();
    guidePoints.clear();
    waypoints.clear();
    lastPassedPathIndex = 0;
    lastGuideIndex = -1;
    visitedWaypointIndices.clear();
    preAnnouncedGuides.clear();
    
    // 경로 오버레이 제거
    if (mapController != null) {
      if (completedPathOverlay != null) {
        mapController!.deleteOverlay(completedPathOverlay!.info);
        completedPathOverlay = null;
      }
      if (remainingPathOverlay != null) {
        mapController!.deleteOverlay(remainingPathOverlay!.info);
        remainingPathOverlay = null;
      }
    }
    
    debugLog("RouteService reset");
  }
  
  // 현재 위치 업데이트 시 호출되는 메서드
  void updatePosition(NLatLng currentPosition) {
    if (pathCoordinates.isEmpty || mapController == null) return;
    
    // 1. 경로 진행상황 업데이트
    updateRouteProgress(currentPosition);
    
    // 2. 경로 안내 메시지 업데이트
    updateNavigationGuidance(currentPosition);
    
    // 3. 웨이포인트 체크
    checkWaypointProximity(currentPosition);
  }
  
  // 경로 진행상황 업데이트
  void updateRouteProgress(NLatLng currentPosition) {
    if (pathCoordinates.isEmpty || mapController == null) return;
    
    // 현재 위치에서 가장 가까운 경로 인덱스 찾기
    int closestPathIndex = findClosestPathIndex(currentPosition);
    
    // 이미 지나간 부분이면 업데이트
    if (closestPathIndex > lastPassedPathIndex) {
      lastPassedPathIndex = closestPathIndex;
      updateRouteOverlay();
      debugLog("Updated route progress: now at index $lastPassedPathIndex");
    }
  }
  
  // 경로 오버레이 업데이트 (지난 경로와 남은 경로 표시)
  void updateRouteOverlay() {
    if (pathCoordinates.isEmpty || mapController == null) return;
    
    try {
      // 기존 오버레이 제거
      if (completedPathOverlay != null) {
        mapController!.deleteOverlay(completedPathOverlay!.info);
      }
      if (remainingPathOverlay != null) {
        mapController!.deleteOverlay(remainingPathOverlay!.info);
      }
      
      // 지나간 경로 (청록색으로 표시)
      if (lastPassedPathIndex > 0) {
        completedPathOverlay = NPathOverlay(
          id: 'completed_path_overlay',
          coords: pathCoordinates.sublist(0, lastPassedPathIndex + 1),
          color: Colors.white, // 지나간 경로는 청록색
          width: 7,
        );
        mapController!.addOverlay(completedPathOverlay!);
      }
      
      // 남은 경로 (파란색으로 표시)
      if (lastPassedPathIndex < pathCoordinates.length - 1) {
        remainingPathOverlay = NPathOverlay(
          id: 'remaining_path_overlay',
          coords: pathCoordinates.sublist(lastPassedPathIndex),
          patternImage: NOverlayImage.fromAssetImage("assets/arrow-pattern.png"),
          color: Colors.blue, // 남은 경로는 파란색
          width: 7,
        );
        mapController!.addOverlay(remainingPathOverlay!);
      }
    } catch (e) {
      debugLog('경로 오버레이 업데이트 중 오류 발생: $e');
    }
  }
  
  // 경로 안내 업데이트
  void updateNavigationGuidance(NLatLng currentPosition) {
    if (guidePoints.isEmpty) return;
    
    // 다음 안내 포인트들 찾기
    List<int> upcomingGuideIndices = [];
    for (int i = 0; i < guidePoints.length; i++) {
      int pointIndex = guidePoints[i]['pointIndex'];
      
      // 아직 지나지 않은 안내 포인트들 수집
      if (pointIndex > lastPassedPathIndex) {
        upcomingGuideIndices.add(i);
      }
    }
    
    if (upcomingGuideIndices.isEmpty) return;
    
    // 가장 가까운 안내 포인트
    int nextGuideIndex = upcomingGuideIndices.first;
    int guidePointIndex = guidePoints[nextGuideIndex]['pointIndex'];
    
    if (guidePointIndex < pathCoordinates.length) {
      NLatLng guidePoint = pathCoordinates[guidePointIndex];
      double distance = calculateDistance(currentPosition, guidePoint);
      
      // 안내 포인트 접근 여부 확인
      
      // 1. 미리 알림 단계 (100m 전)
      if (distance <= nextGuidePointPreAnnouncementDistance && 
          distance > nextGuidePointThreshold && 
          !preAnnouncedGuides.containsKey(nextGuideIndex)) {
        
        String instructions = guidePoints[nextGuideIndex]['instructions'];
        String distanceText = "${distance.toInt()}m 앞";
        onNavigationInstructionChanged("$distanceText $instructions");
        
        preAnnouncedGuides[nextGuideIndex] = true;
        debugLog("Pre-announced guide at index $nextGuideIndex, distance: ${distance.toInt()}m");
      }
      
      // 2. 도달 단계 (20m 이내)
      if (distance <= nextGuidePointThreshold && nextGuideIndex != lastGuideIndex) {
        String instructions = guidePoints[nextGuideIndex]['instructions'];
        onNavigationInstructionChanged("지금 $instructions");
        
        lastGuideIndex = nextGuideIndex;
        debugLog("Reached guide point at index $nextGuideIndex");
      }
    }
  }
  
  // 웨이포인트 접근 체크
void checkWaypointProximity(NLatLng currentPosition) {
  if (waypoints.isEmpty || waypoints.length <= 1) return;
  
  for (int i = 1; i < waypoints.length; i++) {  // 첫 번째 웨이포인트(출발지) 제외
    // 이미 방문한 웨이포인트는 건너뛰기
    if (visitedWaypointIndices.contains(i)) continue;
    
    NLatLng waypointPosition = NLatLng(waypoints[i][0], waypoints[i][1]);
    double distance = calculateDistance(currentPosition, waypointPosition);
    
    debugLog("Checking waypoint $i: distance = ${distance.toInt()}m, threshold = ${waypointProximityThreshold}m");
    
    // 웨이포인트 근처에 도달하면 알림
    if (distance <= waypointProximityThreshold) {
      visitedWaypointIndices.add(i);
      onWaypointReached(i); // 인덱스 그대로 전달 (실제 웨이포인트 번호)
      debugLog("Reached waypoint ${i}!");
    }
  }
}
  // 가장 가까운 경로 인덱스 찾기
  int findClosestPathIndex(NLatLng position) {
    if (pathCoordinates.isEmpty) return 0;
    
    int closestIndex = lastPassedPathIndex;
    double minDistance = double.infinity;
    
    // 현재 인덱스부터 앞으로만 검색 (뒤로는 가지 않는다고 가정)
    for (int i = lastPassedPathIndex; i < pathCoordinates.length; i++) {
      double distance = calculateDistance(position, pathCoordinates[i]);
      if (distance < minDistance) {
        minDistance = distance;
        closestIndex = i;
      }
    }
    
    return closestIndex;
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
  
  // 디버그 로그 출력
  void debugLog(String message) {
    if (enableDebugLog) {
      print("🚗 RouteService: $message");
    }
  }
}