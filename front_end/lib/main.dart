import 'package:flutter/material.dart';

// 💡 메인 화면을 담당하는 우리가 만든 파일을 불러옵니다.
import 'home_screen.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '해봄악기도서관',
      theme: ThemeData(
        primarySwatch: Colors.indigo,
        scaffoldBackgroundColor: Colors.grey[100],
      ),
      home: const InstrumentLibraryScreen(), // 메인 화면 실행
    );
  }
}