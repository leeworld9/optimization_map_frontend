import 'package:flutter_naver_map/flutter_naver_map.dart';

/// 경로 웨이포인트 클래스 (사이드바 표시용)
class RouteWaypoint {
  final int index;
  final String name;
  final NLatLng position;
  final double distanceFromPrevious; // 이전 지점으로부터의 거리 (km)
  final int timeFromPrevious; // 이전 지점으로부터의 시간 (분)
  bool isReached; // 도달 여부

  RouteWaypoint({
    required this.index,
    required this.name,
    required this.position,
    required this.distanceFromPrevious,
    required this.timeFromPrevious,
    this.isReached = false,
  });
}

/// 웨이포인트 리스트 관리 클래스
class RouteWaypointManager {
  List<RouteWaypoint> waypoints = [];
  double totalDistance = 0;
  
  /// 웨이포인트 정보 업데이트
  void updateWaypoints({
    required List<List<double>> coordinates, 
    required Set<int> visitedIndices,
    required Function(NLatLng, NLatLng) calculateDistance,
  }) {
    if (coordinates.isEmpty) return;
    
    waypoints = [];
    totalDistance = 0;
    
    // 첫 번째 지점은 시작점
    NLatLng startPosition = NLatLng(
      coordinates[0][0],
      coordinates[0][1]
    );
    
    waypoints.add(RouteWaypoint(
      index: 0,
      name: "시작점",
      position: startPosition,
      distanceFromPrevious: 0,
      timeFromPrevious: 0,
      isReached: true, // 시작점은 이미 도달한 상태
    ));
    
    // 경유지 및 목적지 정보 추가
    for (int i = 1; i < coordinates.length; i++) {
      NLatLng waypointPosition = NLatLng(
        coordinates[i][0],
        coordinates[i][1]
      );
      
      // 이전 지점과의 거리 계산
      double distance = 0;
      if (i > 0) {
        NLatLng prevPosition = NLatLng(
          coordinates[i-1][0],
          coordinates[i-1][1]
        );
        distance = calculateDistance(prevPosition, waypointPosition) / 1000; // 미터를 킬로미터로 변환
        totalDistance += distance;
      }
      
      // 예상 소요 시간
      // 평균 이동 속도를 4km/h로 가정 (도보 기준)
      int estimatedTime = (distance / 4 * 60).round(); // 분 단위로 계산
      
      String waypointName = i == coordinates.length - 1 
        ? "목적지" // 마지막은 목적지
        : "주요지점 ${i}";
        
      waypoints.add(RouteWaypoint(
        index: i,
        name: waypointName,
        position: waypointPosition,
        distanceFromPrevious: distance,
        timeFromPrevious: estimatedTime,
        isReached: visitedIndices.contains(i),
      ));
    }
  }
  
  /// 웨이포인트 도달 상태 업데이트
  void updateWaypointStatus(int waypointIndex) {
    for (var waypoint in waypoints) {
      if (waypoint.index == waypointIndex) {
        waypoint.isReached = true;
        break;
      }
    }
  }
  
  /// 현재까지 진행한 경로의 거리 계산
  double getCompletedDistance() {
    double completedDistance = 0;
    
    for (int i = 1; i < waypoints.length; i++) {
      // 도달한 웨이포인트까지의 거리만 합산
      if (waypoints[i].isReached) {
        completedDistance += waypoints[i].distanceFromPrevious;
      } else if (waypoints[i-1].isReached) {
        // 현재 진행 중인 구간은 절반 정도 진행했다고 가정
        completedDistance += waypoints[i].distanceFromPrevious * 0.5;
        break;
      }
    }
    
    return completedDistance;
  }
  
  /// 진행률 계산 (%)
  double getProgressPercentage() {
    if (totalDistance <= 0) return 0;
    
    double completedDistance = getCompletedDistance();
    return (completedDistance / totalDistance) * 100;
  }

  /// 현재 진행 중인 구간 인덱스 찾기
int getCurrentSegmentIndex(NLatLng currentPosition, Function(NLatLng, int) findClosestPathIndex) {
  if (waypoints.isEmpty || waypoints.length < 2) return -1;
  
  // 현재 위치에서 가장 가까운 경로 인덱스 찾기
  int closestPathIndex = findClosestPathIndex(currentPosition, 0);
  
  // 다음으로 도달할 웨이포인트 찾기
  int nextWaypointIndex = -1;
  for (int i = 0; i < waypoints.length; i++) {
    if (!waypoints[i].isReached) {
      nextWaypointIndex = i;
      break;
    }
  }
  
  // 다음 웨이포인트가 없으면 (모두 도달) 마지막 구간을 반환
  if (nextWaypointIndex == -1) {
    return waypoints.length - 2 >= 0 ? waypoints.length - 2 : -1;
  }
  
  // 이전 웨이포인트 인덱스
  int prevWaypointIndex = nextWaypointIndex - 1;
  if (prevWaypointIndex < 0) prevWaypointIndex = 0;
  
  // 현재 구간 = 이전 웨이포인트 인덱스
  return prevWaypointIndex;
}

/// 특정 구간의 경로 진행률 계산 (0.0 ~ 1.0)
double getSegmentProgress(int segmentIndex, NLatLng currentPosition, 
    Function(NLatLng, NLatLng) calculateDistance) {
  if (segmentIndex < 0 || segmentIndex >= waypoints.length - 1) return 0.0;
  
  // 구간의 시작점과 끝점
  NLatLng startPoint = waypoints[segmentIndex].position;
  NLatLng endPoint = waypoints[segmentIndex + 1].position;
  
  // 전체 구간 거리
  double totalDistance = calculateDistance(startPoint, endPoint);
  if (totalDistance <= 0) return 0.0;
  
  // 시작점부터 현재 위치까지의 거리
  double travelledDistance = calculateDistance(startPoint, currentPosition);
  
  // 진행률 계산 (0.0 ~ 1.0)
  double progress = travelledDistance / totalDistance;
  
  // 범위 제한
  progress = progress < 0.0 ? 0.0 : progress;
  progress = progress > 1.0 ? 1.0 : progress;
  
  return progress;
}
}