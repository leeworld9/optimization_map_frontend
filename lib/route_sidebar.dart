import 'package:flutter/material.dart';
import 'route_waypoint.dart';

class RouteSidebar extends StatelessWidget {
  final List<RouteWaypoint> waypoints;
  final double totalDistance;
  final AnimationController controller;
  final Function() onClose;
  final int currentSegmentIndex; // 현재 이동 중인 구간 인덱스

  const RouteSidebar({
    Key? key,
    required this.waypoints,
    required this.totalDistance,
    required this.controller,
    required this.onClose,
    this.currentSegmentIndex = -1, // 기본값은 -1 (이동 중인 구간 없음)
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        final slideAnimation = Tween<Offset>(
          begin: Offset(1.0, 0.0), // 화면 오른쪽에서 시작
          end: Offset(0.0, 0.0),   // 화면에 표시
        ).animate(controller);
        
        return SlideTransition(
          position: slideAnimation,
          child: child,
        );
      },
      child: Align(
        alignment: Alignment.centerRight,
        child: Container(
          width: 240,
          margin: EdgeInsets.only(top: 4, right: 4, bottom: 4),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black26,
                blurRadius: 8,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            children: [
              // 헤더 (경로 정보)
              Container(
                padding: EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '총 소요시간 ${_calculateTotalTime()}분',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'NotoSansKR',
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      '총 이동 거리 ${totalDistance.toStringAsFixed(1)}km',
                      style: TextStyle(
                        fontSize: 14,
                        fontFamily: 'NotoSansKR',
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      '배달 진행상황 (${_getCompletionPercentage()}%)',
                      style: TextStyle(
                        fontSize: 14,
                        fontFamily: 'NotoSansKR',
                      ),
                    ),
                  ],
                ),
              ),
              
              // 경로 진행 리스트 (타임라인 스타일)
              Expanded(
                child: waypoints.isEmpty
                    ? Center(child: Text('경로 정보가 없습니다', style: TextStyle(fontFamily: 'NotoSansKR')))
                    : ListView.builder(
                        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        itemCount: waypoints.length,
                        itemBuilder: (context, index) {
                          final waypoint = waypoints[index];
                          final isLast = index == waypoints.length - 1;
                          final showSegmentInfo = index < waypoints.length - 1;
                          
                          return Column(
                            children: [
                              // 웨이포인트 아이템
                              _buildTimelineItem(waypoint, index, isLast),
                              
                              // 다음 구간 정보 (마지막 웨이포인트 제외)
                              if (showSegmentInfo)
                                _buildSegmentInfo(index),
                            ],
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  /// 전체 소요 시간 계산
  int _calculateTotalTime() {
    if (waypoints.isEmpty) return 0;
    
    int totalMinutes = 0;
    for (int i = 1; i < waypoints.length; i++) {
      totalMinutes += waypoints[i].timeFromPrevious;
    }
    
    return totalMinutes;
  }
  
  /// 진행률 계산 (완료된 웨이포인트 수 / 전체 웨이포인트 수)
  String _getCompletionPercentage() {
    if (waypoints.isEmpty || waypoints.length <= 1) return "0";
    
    int reachedCount = waypoints.where((w) => w.isReached).length;
    int totalWaypoints = waypoints.length;
    
    // 현재 위치(첫 번째) 제외하고 계산
    return ((reachedCount - 1) / (totalWaypoints - 1) * 100).round().toString();
  }
  
  /// 타임라인 스타일 아이템 UI 생성
  Widget _buildTimelineItem(RouteWaypoint waypoint, int index, bool isLast) {
    // 웨이포인트 이름 (시작점, 또는 주요지점/목적지)
    String waypointName = index == 0 
        ? "시작점" 
        : waypoint.name;
    
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 타임라인 영역 (선과 원)
        SizedBox(
          width: 40,
          child: Column(
            children: [
              // 상단 연결선 (첫 번째 아이템은 제외)
              if (index > 0)
                Container(
                  width: 4,
                  height: 30,
                  color: _getLineColor(index - 1),
                ),
                
              // 원형 숫자 표시
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: waypoint.isReached ? Colors.green : Colors.purple,
                ),
                child: Center(
                  child: Text(
                    '${index + 1}',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'NotoSansKR',
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        
        // 웨이포인트 정보
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(left: 8, top: index == 0 ? 0 : 6),
            child: Text(
              waypointName,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                fontFamily: 'NotoSansKR',
              ),
            ),
          ),
        ),
      ],
    );
  }
  
  /// 구간 정보 UI 생성 (거리와 소요 시간)
  Widget _buildSegmentInfo(int startIndex) {
    // 다음 구간의 웨이포인트
    final nextWaypoint = waypoints[startIndex + 1];
    
    // 이 구간이 현재 이동 중인 구간인지 확인
    bool isActiveSegment = currentSegmentIndex == startIndex;
    
    return Row(
      children: [
        // 타임라인 선
        SizedBox(
          width: 40,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 4,
                height: 40,
                color: _getLineColor(startIndex),
              ),
              
              // 현재 이동 중인 구간에만 차량 아이콘 표시
              if (isActiveSegment)
                Positioned(
                  top: 20, // 선의 중간 위치
                  child: Container(
                    padding: EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.blue, width: 2),
                    ),
                    child: Icon(Icons.directions_car, size: 14, color: Colors.blue),
                  ),
                ),
            ],
          ),
        ),
        
        // 구간 정보 (거리 및 소요 시간)
        Padding(
          padding: EdgeInsets.only(left: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${nextWaypoint.distanceFromPrevious.toStringAsFixed(1)}km',
                style: TextStyle(
                  fontSize: 14,
                  fontFamily: 'NotoSansKR',
                ),
              ),
              Text(
                '${nextWaypoint.timeFromPrevious}분',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey.shade700,
                  fontFamily: 'NotoSansKR',
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
  
  /// 진행 상태에 따른 선 색상 결정
  Color _getLineColor(int segmentIndex) {
    if (segmentIndex >= waypoints.length - 1) return Colors.grey;
    
    final startWaypoint = waypoints[segmentIndex];
    final endWaypoint = waypoints[segmentIndex + 1];
    
    if (startWaypoint.isReached && endWaypoint.isReached) {
      // 두 지점 모두 완료된 경우 - 초록색
      return Colors.green;
    } else if (startWaypoint.isReached && !endWaypoint.isReached) {
      // 시작점만 완료된 경우 - 진행 중 - 파란색
      return Colors.blue;
    } else {
      // 아직 도달하지 않은 구간 - 보라색
      return Colors.purple;
    }
  }
}