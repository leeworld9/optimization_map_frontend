import 'package:flutter/material.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';

// 다른 파일에서 가져온 MapScreen 위젯 임포트
import 'map_screen.dart';

void main() async {
  // Flutter 엔진 초기화 확인
  WidgetsFlutterBinding.ensureInitialized();
  
  // 네이버 맵 SDK 초기화
  await NaverMapSdk.instance.initialize(
    clientId: 'j9g95d8hyu',
    onAuthFailed: (error) {
      print('네이버 지도 SDK 초기화 실패: $error');
    },
  );
  
  // 앱 실행
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '경로 안내 앱',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: MapScreen(),
    );
  }
}