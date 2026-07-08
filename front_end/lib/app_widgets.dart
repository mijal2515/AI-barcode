import 'package:flutter/material.dart';

// 🎸 좌측: 악기 목록을 보여주는 리스트 위젯
class InstrumentListView extends StatelessWidget {
  final bool isLoading;
  final List<dynamic> instruments;

  const InstrumentListView({
    super.key,
    required this.isLoading,
    required this.instruments,
  });

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (instruments.isEmpty) {
      return const Center(child: Text("등록된 악기가 없습니다."));
    }

    return ListView.builder(
      itemCount: instruments.length,
      itemBuilder: (context, index) {
        final item = instruments[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 10),
          child: ListTile(
            leading: const Icon(Icons.inventory_2, color: Colors.green),
            title: Text(item['name'] ?? '이름 없음', style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text('바코드: ${item['barcode']}'),
            trailing: Text(
              item['status'] ?? '보관중',
              style: TextStyle(
                color: item['status'] == '대여중' ? Colors.orange : Colors.green,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        );
      },
    );
  }
}

// 🕒 우측: 입고/반출 기록을 보여주는 로그 위젯
class HistoryLogView extends StatelessWidget {
  final List<String> logs;

  const HistoryLogView({super.key, required this.logs});

  @override
  Widget build(BuildContext context) {
    if (logs.isEmpty) {
      return const Center(child: Text("기록이 없습니다.", style: TextStyle(color: Colors.grey)));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(10),
      itemCount: logs.length,
      itemBuilder: (context, index) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 8.0),
          child: Text(logs[index], style: const TextStyle(fontSize: 13)),
        );
      },
    );
  }
} 