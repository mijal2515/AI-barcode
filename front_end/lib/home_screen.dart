import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:file_picker/file_picker.dart';
import 'dart:convert';
import 'package:excel/excel.dart' hide Border;

import 'package:flutter/foundation.dart' show kIsWeb; 
import 'dart:io' as io;
import 'package:path_provider/path_provider.dart';
import 'package:universal_html/html.dart' as html;
import 'package:simple_barcode_scanner/simple_barcode_scanner.dart';

import 'app_widgets.dart';

const String SERVER_URL = 'http://172.16.165.143:8000';

class InstrumentLibraryScreen extends StatefulWidget {
  const InstrumentLibraryScreen({super.key});

  @override
  State<InstrumentLibraryScreen> createState() => _InstrumentLibraryScreenState();
}

class _InstrumentLibraryScreenState extends State<InstrumentLibraryScreen> {
  int _currentIndex = 0;

  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _barcodeController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  
  final TextEditingController _checkoutBarcodeController = TextEditingController();
  final TextEditingController _checkinBarcodeController = TextEditingController();
  
  final TextEditingController _schoolController = TextEditingController();
  final TextEditingController _historySearchController = TextEditingController();

  List<dynamic> _checkoutCart = [];
  List<dynamic> _checkinCart = [];

  List<dynamic> _allInstruments = [];
  List<dynamic> _filteredInstruments = [];
  
  List<dynamic> _historyLogs = [];
  List<dynamic> _filteredHistoryLogs = [];
  
  // 🔥 핵심 수정: 텍스트 대신 숫자(id)를 담는 Set으로 변경
  final Set<int> _selectedIds = <int>{};
  
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _fetchInstruments();
    _fetchHistoryLogs();
    _searchController.addListener(_filterInstruments);
    _historySearchController.addListener(_filterHistoryLogs);
  }

  void _filterInstruments() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      _filteredInstruments = _allInstruments.where((item) {
        final name = (item['name'] ?? '').toString().toLowerCase();
        final barcode = (item['barcode'] ?? '').toString().toLowerCase();
        final school = (item['school'] ?? '').toString().toLowerCase();
        return name.contains(query) || barcode.contains(query) || school.contains(query);
      }).toList();
    });
  }

  void _filterHistoryLogs() {
    final query = _historySearchController.text.toLowerCase();
    setState(() {
      _filteredHistoryLogs = _historyLogs.where((log) {
        final content = (log['content'] ?? '').toString().toLowerCase();
        final time = (log['time'] ?? '').toString().toLowerCase();
        final type = (log['type'] ?? '').toString().toLowerCase();
        return content.contains(query) || time.contains(query) || type.contains(query);
      }).toList();
    });
  }

  void _addToCart(String barcode, String actionType) {
    barcode = barcode.trim();
    if (barcode.isEmpty) return;

    int index = _allInstruments.indexWhere((item) => item['barcode'].toString() == barcode);
    if (index == -1) {
      _showSnackBar('❌ 미등록 바코드입니다! 데이터 관리에 먼저 등록하세요. ($barcode)');
      _clearBarcodeTextField(actionType);
      return;
    }

    var instrument = _allInstruments[index];

    if (actionType == '출고' && instrument['status'] == '대여중') {
      _showSnackBar('❌ 이미 대여 중인 악기입니다! (현재 대여처: ${instrument['school']})');
      _clearBarcodeTextField(actionType);
      return;
    }

    if (actionType == '입고' && instrument['status'] == '보관중') {
      _showSnackBar('⚠️ 이미 보관 중인 악기입니다. 입고 대기 목록에 넣을 수 없습니다.');
      _clearBarcodeTextField(actionType);
      return;
    }

    List<dynamic> targetCart = actionType == '출고' ? _checkoutCart : _checkinCart;

    if (targetCart.any((item) => item['barcode'].toString() == barcode)) {
      _showSnackBar('⚠️ 이미 대기 목록에 포함된 악기입니다.');
      _clearBarcodeTextField(actionType);
      return;
    }

    setState(() {
      targetCart.add(instrument);
    });

    _clearBarcodeTextField(actionType);
  }

  void _clearBarcodeTextField(String actionType) {
    if (actionType == '출고') {
      _checkoutBarcodeController.clear();
    } else {
      _checkinBarcodeController.clear();
    }
  }

  Future<void> _completeBatchAction(String actionType) async {
    List<dynamic> targetCart = actionType == '출고' ? _checkoutCart : _checkinCart;

    if (targetCart.isEmpty) {
      _showSnackBar('❗ 처리할 악기가 없습니다. 바코드를 먼저 찍어주세요.');
      return;
    }

    String schoolText = _schoolController.text.trim();
    if (actionType == '출고' && schoolText.isEmpty) {
      _showSnackBar('🏫 출고할 학교 이름을 입력해 주세요!');
      return;
    }

    String timeNow = "${DateTime.now().hour.toString().padLeft(2, '0')}:${DateTime.now().minute.toString().padLeft(2, '0')}";
    String newStatus = actionType == '출고' ? '대여중' : '보관중';
    int count = targetCart.length;

    try {
      for (var scannedItem in targetCart) {
        String contentText = actionType == '출고'
            ? '${scannedItem['name']} (${scannedItem['barcode']}) ➡️ [$schoolText]'
            : '${scannedItem['name']} (${scannedItem['barcode']}) [반납 완료]';

        var url = Uri.parse('$SERVER_URL/history');
        await http.post(
          url,
          headers: {"Content-Type": "application/json"},
          body: jsonEncode({
            "time": timeNow,
            "type": actionType,
            "content": contentText,
          }),
        );

        int index = _allInstruments.indexWhere((item) => item['barcode'].toString() == scannedItem['barcode'].toString());
        if (index != -1) {
          _allInstruments[index]['status'] = newStatus;
          _allInstruments[index]['school'] = actionType == '출고' ? schoolText : '';
        }
      }

      await _fetchHistoryLogs();

      setState(() {
        if (actionType == '출고') {
          _checkoutCart = [];
          _schoolController.clear();
        } else {
          _checkinCart = [];
        }
        _filterInstruments();
      });

      _showSnackBar('🎉 총 $count건의 $actionType 처리가 완료되어 DB에 저장되었습니다!');
    } catch (e) {
      _showSnackBar('❌ DB 기록 저장 중 네트워크 오류 발생');
    }

    FocusScope.of(context).unfocus();
  }

  // 🔥 핵심 수정: id 목록을 바디에 묶어 서버로 보내는 로직으로 변경
  Future<void> _deleteSelectedHistoryLogs() async {
    if (_selectedIds.isEmpty) {
      _showSnackBar('⚠️ 삭제할 기록을 먼저 선택해 주세요!');
      return;
    }

    try {
      var url = Uri.parse('$SERVER_URL/history/delete-multiple');
      var response = await http.post(
        url,
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"ids": _selectedIds.toList()}),
      );

      if (response.statusCode == 200) {
        _showSnackBar('🗑️ 선택한 ${_selectedIds.length}건의 기록이 완전히 삭제되었습니다.');
        setState(() {
          _selectedIds.clear();
        });
        await _fetchHistoryLogs(); // 삭제 완료 후 목록 동기화 새로고침
      } else {
        var errorData = jsonDecode(utf8.decode(response.bodyBytes));
        _showSnackBar('❌ 삭제 실패: ${errorData['detail'] ?? '서버 오류'}');
      }
    } catch (e) {
      _showSnackBar('❌ 네트워크 오류: 백엔드 서버 상태를 확인하세요.');
    }
  }

  Future<void> _addSingleInstrument() async {
    String barcode = _barcodeController.text.trim();
    String name = _nameController.text.trim();

    if (barcode.isEmpty || name.isEmpty) {
      _showSnackBar('⚠️ 바코드와 악기 이름을 모두 입력해주세요.');
      return;
    }

    try {
      var url = Uri.parse('$SERVER_URL/instruments');
      var response = await http.post(
        url,
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          'barcode': barcode,
          'name': name,
          'status': '보관중',
          'school': '',
        }),
      );

      if (response.statusCode == 200) {
        var decodedData = jsonDecode(utf8.decode(response.bodyBytes));
        if (decodedData['status'] == 'success') {
          _showSnackBar('🎉 악기가 데이터베이스에 영구 저장되었습니다!');
          await _fetchInstruments();
          _barcodeController.clear();
          _nameController.clear();
        } else {
          _showSnackBar('❌ DB 등록 실패: ${decodedData['message']}');
        }
      } else {
        _showSnackBar('❌ 서버 에러 (통신 코드: ${response.statusCode})');
      }
    } catch (e) {
      _showSnackBar('❌ 네트워크 오류: 파이썬 백엔드 서버가 켜져 있는지 확인하세요.');
    }
    FocusScope.of(context).unfocus();
  }

  void _showEditDialog(Map<String, dynamic> instrument) {
    final nameController = TextEditingController(text: instrument['name']);
    final statusController = TextEditingController(text: instrument['status']);
    final schoolController = TextEditingController(text: instrument['school']);

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('✏️ [${instrument['name']}] 정보 수정', style: const TextStyle(fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: TextEditingController(text: instrument['barcode']),
                  decoration: const InputDecoration(labelText: '바코드 (수정 불가)'),
                  readOnly: true,
                  style: const TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(labelText: '악기 이름'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: statusController,
                  decoration: const InputDecoration(labelText: '상태 (보관중 / 대여중)'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: schoolController,
                  decoration: const InputDecoration(labelText: '대여처 (학교명)'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('취소', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF6B7BFF)),
              onPressed: () async {
                String newName = nameController.text.trim();
                String newStatus = statusController.text.trim();
                String newSchool = schoolController.text.trim();

                if (newName.isEmpty) {
                  _showSnackBar('⚠️ 악기 이름을 입력해주세요.');
                  return;
                }

                try {
                  var url = Uri.parse('$SERVER_URL/instruments/${instrument['barcode']}');
                  var response = await http.put(
                    url,
                    headers: {"Content-Type": "application/json"},
                    body: jsonEncode({
                      'name': newName,
                      'status': newStatus,
                      'school': newSchool,
                    }),
                  );

                  if (response.statusCode == 200) {
                    var decodedData = jsonDecode(utf8.decode(response.bodyBytes));
                    if (decodedData['status'] == 'success') {
                      Navigator.pop(context);
                      _showSnackBar('🎉 악기 정보가 수정되었습니다.');
                      await _fetchInstruments();
                    } else {
                      _showSnackBar('❌ 수정 실패: ${decodedData['message']}');
                    }
                  } else {
                    _showSnackBar('❌ 서버 에러 (${response.statusCode})');
                  }
                } catch (e) {
                  _showSnackBar('❌ 네트워크 오류: 서버 연결을 확인하세요.');
                }
              },
              child: const Text('저장', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message), duration: const Duration(seconds: 2)));
  }

  Future<void> _fetchInstruments() async {
    setState(() => _isLoading = true);
    try {
      var url = Uri.parse('$SERVER_URL/instruments');
      var response = await http.get(url);
      if (response.statusCode == 200) {
        var decodedData = jsonDecode(utf8.decode(response.bodyBytes));
        setState(() {
          _allInstruments = decodedData['data'];
          _filteredInstruments = _allInstruments;
        });
      }
    } catch (e) {
      _showSnackBar("❌ 서버 데이터를 불러오지 못했습니다.");
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _deleteInstrument(String barcode) async {
    try {
      final String safeBarcode = Uri.encodeComponent(barcode.trim());
      var url = Uri.parse('http://localhost:8000/instruments/$safeBarcode');
      var response = await http.delete(url);
      
      if (response.statusCode == 200) {
        var decodedData = jsonDecode(response.body);
        if (decodedData['status'] == 'success') {
          _showSnackBar('🗑️ 악기가 완전히 삭제되었습니다.');
          await _fetchInstruments(); 
        } else {
          _showSnackBar('❌ DB 삭제 실패: ${decodedData['message']}');
        }
      } else {
        _showSnackBar('❌ 통신 에러 (코드: ${response.statusCode})');
      }
    } catch (e) {
      _showSnackBar('❌ 통신 실패: 백엔드 서버 확인 필요');
    }
  }

  Future<void> _fetchHistoryLogs() async {
    try {
      var url = Uri.parse('$SERVER_URL/history');
      var response = await http.get(url);
      if (response.statusCode == 200) {
        var decodedData = jsonDecode(utf8.decode(response.bodyBytes));
        setState(() {
          _historyLogs = decodedData['data'];
          _filteredHistoryLogs = _historyLogs;
        });
      }
    } catch (e) {
      _showSnackBar("❌ DB 기록을 불러오지 못했습니다.");
    }
  }

  Future<void> _uploadExcelToServer() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls'],
        withData: true,
      );
      if (result != null) {
        var fileBytes = result.files.first.bytes;
        var fileName = result.files.first.name;
        if (fileBytes == null) return;

        _showSnackBar('⏳ 엑셀 데이터를 서버로 전송 중입니다...');
        var uri = Uri.parse('$SERVER_URL/upload-excel');
        var request = http.MultipartRequest('POST', uri);
        request.files.add(http.MultipartFile.fromBytes('file', fileBytes, filename: fileName));

        var response = await request.send();
        if (response.statusCode == 200) {
          _showSnackBar('🎉 엑셀 대량 등록 성공!');
          await _fetchInstruments();
        } else {
          _showSnackBar('❌ 서버가 엑셀 처리에 실패했습니다.');
        }
      }
    } catch (e) {
      _showSnackBar("❌ 오류 발생: $e");
    }
  }

  // 🔥 핵심 수정: id 기반 매칭으로 엑셀 출력하도록 변경
  void _downloadSelectedToExcel() {
    if (_selectedIds.isEmpty) {
      _showSnackBar('⚠️ 다운로드할 기록을 먼저 선택해 주세요!');
      return;
    }

    final workbook = Excel.createExcel();
    final sheetObject = workbook['Sheet1'];

    sheetObject.appendRow([
      TextCellValue('시간'),
      TextCellValue('구분'),
      TextCellValue('악기명'),
      TextCellValue('바코드'),
      TextCellValue('대여처/상태'),
    ]);

    for (var log in _historyLogs) {
      if (log['id'] != null && _selectedIds.contains(log['id'])) {
        String content = log['content'] ?? '';
        String instrumentName = content;
        String barcode = '';
        String locationOrStatus = '';

        RegExp exp = RegExp(r'\((.*?)\)');
        Match? match = exp.firstMatch(content);

        if (match != null) {
          barcode = match.group(1) ?? '';
          instrumentName = content.substring(0, match.start).trim();
          instrumentName = instrumentName.replaceAll('수동 추가: ', '').replaceAll('악기 삭제됨: ', '').trim();

          String afterText = content.substring(match.end).trim();
          if (afterText.startsWith('➡️ [')) {
            locationOrStatus = afterText.replaceAll('➡️ [', '').replaceAll(']', '').trim();
          } else if (afterText.contains('[반납 완료]')) {
            locationOrStatus = '반납 완료';
          } else {
            locationOrStatus = afterText;
          }
        }

        sheetObject.appendRow([
          TextCellValue(log['time'] ?? ''),
          TextCellValue(log['type'] ?? ''),
          TextCellValue(instrumentName),
          TextCellValue(barcode),
          TextCellValue(locationOrStatus),
        ]);
      }
    }

    final fileBytes = workbook.encode();
    if (fileBytes != null) {
      final fileName = "DB_악기_입출고_기록_${DateTime.now().toString().substring(0,10)}.xlsx";

      if (kIsWeb) {
        // 💻 기존 PC (웹 브라우저) 전용 다운로드 방식
        final blob = html.Blob([fileBytes], 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
        final url = html.Url.createObjectUrlFromBlob(blob);
        final anchor = html.AnchorElement(href: url)
          ..setAttribute("download", fileName)
          ..click();
        html.Url.revokeObjectUrl(url);
        _showSnackBar('📊 선택한 ${_selectedIds.length}건의 기록이 엑셀로 다운로드되었습니다!');
      } else {
        // 📱 모바일 (Android/iOS) 전용 다운로드 방식
        getDownloadsDirectory().then((directory) async {
          if (directory != null) {
            final filePath = '${directory.path}/$fileName';
            final file = io.File(filePath);
            await file.writeAsBytes(fileBytes);
            _showSnackBar('📁 모바일 다운로드 폴더에 저장되었습니다!');
          }
        }).catchError((e) {
          _showSnackBar('❌ 모바일 파일 저장 실패: $e');
        });
      }
    }
  }

  Widget _buildCheckInOutTab() {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          Container(
            decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(12)),
            child: TabBar(
              labelColor: Colors.white,
              unselectedLabelColor: Colors.grey.shade600,
              indicatorSize: TabBarIndicatorSize.tab,
              indicator: BoxDecoration(borderRadius: BorderRadius.circular(12), color: const Color(0xFF6B7BFF)),
              tabs: const [
                Tab(child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.upload_sharp, size: 18), SizedBox(width: 6), Text('악기 출고 (대여)', style: TextStyle(fontWeight: FontWeight.bold))])),
                Tab(child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.download_sharp, size: 18), SizedBox(width: 6), Text('악기 입고 (반납)', style: TextStyle(fontWeight: FontWeight.bold))])),
              ],
            ),
          ),
          const SizedBox(height: 15),
          Expanded(
            child: TabBarView(
              children: [
                _buildSubActionPage('출고', _checkoutBarcodeController, _checkoutCart, Colors.orange),
                _buildSubActionPage('입고', _checkinBarcodeController, _checkinCart, Colors.blue),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubActionPage(String type, TextEditingController controller, List<dynamic> cart, Color themeColor) {
    return Padding(
      padding: const EdgeInsets.all(4.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: controller,
            autofocus: true,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
            decoration: InputDecoration(
              hintText: '바코드를 스캔하거나 입력 후 Enter ($type 모드)',
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: Colors.grey.shade300, width: 1.5)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: themeColor, width: 2)),
              prefixIcon: Icon(Icons.qr_code_scanner, color: themeColor),
              suffixIcon: IconButton(
                icon: const Icon(Icons.camera_alt, color: Colors.blueAccent),
                tooltip: '휴대폰 카메라로 스캔',
                onPressed: () async {
                  var res = await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const SimpleBarcodeScannerPage(),
                    ),
                  );
                  if (res is String && res != '-1') {
                    _addToCart(res, type); // 카메라로 스캔한 결과물 자동 장바구니 추가
                  }
                },
              ),
            ),
            onSubmitted: (value) => _addToCart(value, type),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.list_alt_rounded, color: Colors.grey.shade700, size: 20),
                  const SizedBox(width: 6),
                  Text('$type 대기 목록', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(color: themeColor.withOpacity(0.12), borderRadius: BorderRadius.circular(10)),
                    child: Text('${cart.length}개', style: TextStyle(color: themeColor, fontWeight: FontWeight.bold, fontSize: 13)),
                  ),
                ],
              ),
              if (cart.isNotEmpty)
                TextButton.icon(
                  onPressed: () => setState(() => type == '출고' ? _checkoutCart.clear() : _checkinCart.clear()),
                  icon: const Icon(Icons.delete_outline, size: 16, color: Colors.redAccent),
                  label: const Text('전체 비우기', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
                )
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            child: cart.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.center_focus_weak_rounded, size: 40, color: Colors.grey.shade300),
                        const SizedBox(height: 8),
                        Text('스캔된 악기가 없습니다. 바코드를 찍어주세요.', style: TextStyle(color: Colors.grey.shade400, fontSize: 14)),
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: cart.length,
                    itemBuilder: (context, index) {
                      final item = cart[index];
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: themeColor.withOpacity(0.2), width: 1),
                          boxShadow: [BoxShadow(color: Colors.grey.withOpacity(0.04), blurRadius: 4, offset: const Offset(0, 2))],
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                          title: Text(item['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                          subtitle: Text('바코드: ${item['barcode']}', style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                          trailing: IconButton(
                            icon: const Icon(Icons.cancel_rounded, color: Colors.grey),
                            onPressed: () => setState(() => cart.removeAt(index)),
                          ),
                        ),
                      );
                    },
                  ),
          ),
          const SizedBox(height: 15),
          if (type == '출고') ...[
            TextField(
              controller: _schoolController,
              style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange.shade800),
              decoration: InputDecoration(
                labelText: '🏫 출고 대상 학교 입력',
                labelStyle: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold),
                hintText: '예시: 서울초등학교',
                filled: true,
                fillColor: Colors.orange.withOpacity(0.03),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.orangeAccent, width: 1.5)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.orange, width: 2)),
                prefixIcon: const Icon(Icons.school, color: Colors.orange),
              ),
            ),
            const SizedBox(height: 15),
          ],
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              onPressed: () => _completeBatchAction(type),
              style: ElevatedButton.styleFrom(
                backgroundColor: themeColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                elevation: 1,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(type == '출고' ? Icons.local_shipping_rounded : Icons.assignment_returned_rounded),
                  const SizedBox(width: 8),
                  Text('$type 처리 완료하기', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInventoryTab() {
    return Column(
      children: [
        TextField(
          controller: _searchController,
          decoration: InputDecoration(
            hintText: '🔍 바코드, 악기명 또는 대여 중인 학교 검색...',
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            prefixIcon: const Icon(Icons.search),
          ),
        ),
        const SizedBox(height: 15),
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _filteredInstruments.isEmpty
                  ? const Center(child: Text('검색 결과가 없습니다.'))
                  : ListView.builder(
                      itemCount: _filteredInstruments.length,
                      itemBuilder: (context, index) {
                        final item = _filteredInstruments[index];
                        final String status = item['status'] ?? '보관중';
                        final String school = item['school'] ?? '';
                        final bool isRented = status == '대여중';

                        return Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          elevation: 1.5,
                          child: Padding(
                            padding: const EdgeInsets.all(18.0),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                CircleAvatar(
                                  radius: 22,
                                  backgroundColor: isRented ? Colors.orange.withOpacity(0.1) : Colors.green.withOpacity(0.1),
                                  child: Icon(isRented ? Icons.output_sharp : Icons.gavel_sharp, color: isRented ? Colors.orange : Colors.green),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(item['name'] ?? '이름 없음', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                      const SizedBox(height: 6),
                                      Text('바코드: ${item['barcode']}', style: TextStyle(color: Colors.grey[600], fontSize: 13)),
                                    ],
                                  ),
                                ),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                          decoration: BoxDecoration(color: isRented ? Colors.orange : Colors.green, borderRadius: BorderRadius.circular(20)),
                                          child: Text(status, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                                        ),
                                        const SizedBox(width: 8),
                                        IconButton(
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(),
                                          icon: const Icon(Icons.edit, color: Colors.blue, size: 24),
                                          tooltip: '악기 정보 수정',
                                          onPressed: () => _showEditDialog(item),
                                        ),
                                        const SizedBox(width: 8),
                                        IconButton(
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(),
                                          icon: const Icon(Icons.delete_forever_rounded, color: Colors.redAccent, size: 24),
                                          tooltip: '악기 삭제',
                                          onPressed: () {
                                            showDialog(
                                              context: context,
                                              builder: (BuildContext context) {
                                                return AlertDialog(
                                                  title: const Text('⚠️ 삭제 확인', style: TextStyle(fontWeight: FontWeight.bold)),
                                                  content: Text('[${item['name']}] 악기를 영구 삭제하시겠습니까?'),
                                                  actions: [
                                                    TextButton(
                                                      child: const Text('취소', style: TextStyle(color: Colors.grey)),
                                                      onPressed: () => Navigator.of(context).pop(),
                                                    ),
                                                    TextButton(
                                                      child: const Text('삭제', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                                                      onPressed: () {
                                                        Navigator.of(context).pop();
                                                        _deleteInstrument(item['barcode'].toString());
                                                      },
                                                    ),
                                                  ],
                                                );
                                              },
                                            );
                                          },
                                        ),
                                      ],
                                    ),
                                    if (isRented && school.isNotEmpty) ...[
                                      const SizedBox(height: 8),
                                      Text('🏫 $school', style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold, fontSize: 13)),
                                    ],
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }

  // 🔥 핵심 수정: UI 체크박스를 ID 기반으로 연동하도록 변경한 탭
  Widget _buildHistoryTab() {
    bool isAllSelected = _filteredHistoryLogs.isNotEmpty && 
        _selectedIds.length == _filteredHistoryLogs.length;

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _historySearchController,
                decoration: InputDecoration(
                  hintText: '🔍 DB 기록 검색 (학교명, 악기명 등)...',
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  prefixIcon: const Icon(Icons.search, color: Colors.grey),
                  contentPadding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
            const SizedBox(width: 10),
            ElevatedButton.icon(
              onPressed: _downloadSelectedToExcel,
              icon: const Icon(Icons.border_all_rounded, size: 18),
              label: Text('엑셀 다운로드 (${_selectedIds.length})'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green.shade700,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              onPressed: () {
                if (_selectedIds.isEmpty) return;
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('⚠️ 기록 삭제 확인', style: TextStyle(fontWeight: FontWeight.bold)),
                    content: Text('선택한 ${_selectedIds.length}개의 입출고 기록을 데이터베이스에서 영구 삭제하시겠습니까?'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('취소', style: TextStyle(color: Colors.grey)),
                      ),
                      TextButton(
                        onPressed: () {
                          Navigator.pop(context);
                          _deleteSelectedHistoryLogs();
                        },
                        child: const Text('삭제', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                );
              },
              icon: const Icon(Icons.delete_forever_rounded, size: 18),
              label: const Text('선택 삭제'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _selectedIds.isEmpty ? Colors.grey.shade300 : Colors.redAccent,
                foregroundColor: _selectedIds.isEmpty ? Colors.grey.shade500 : Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (_filteredHistoryLogs.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4.0),
            child: Row(
              children: [
                Checkbox(
                  value: isAllSelected,
                  activeColor: const Color(0xFF6B7BFF),
                  onChanged: (bool? value) {
                    setState(() {
                      if (value == true) {
                        _selectedIds.addAll(_filteredHistoryLogs.map((e) => e['id'] as int));
                      } else {
                        _selectedIds.clear();
                      }
                    });
                  },
                ),
                Text(
                  isAllSelected ? '전체 선택 해제' : '검색 결과 전체 선택',
                  style: TextStyle(color: Colors.grey.shade700, fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ],
            ),
          ),
        const SizedBox(height: 5),
        Expanded(
          child: _filteredHistoryLogs.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.history_toggle_off_rounded, size: 40, color: Colors.grey.shade300),
                      const SizedBox(height: 8),
                      Text('데이터베이스에 저장된 입출고 내역이 없습니다.', style: TextStyle(color: Colors.grey.shade400)),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _fetchHistoryLogs,
                  child: ListView.builder(
                    itemCount: _filteredHistoryLogs.length,
                    itemBuilder: (context, index) {
                      final log = _filteredHistoryLogs[index];
                      final int logId = log['id'] ?? 0;
                      final String type = log['type'] ?? '출고';
                      final String time = log['time'] ?? '';
                      final String content = log['content'] ?? '';
                      final bool isCheckout = type == '출고';
                      final bool isSelected = _selectedIds.contains(logId);

                      return Container(
                        key: ValueKey(logId),
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isSelected ? const Color(0xFF6B7BFF) : Colors.grey.shade200,
                            width: isSelected ? 1.5 : 1,
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Checkbox(
                              value: isSelected,
                              activeColor: const Color(0xFF6B7BFF),
                              onChanged: (bool? value) {
                                setState(() {
                                  if (value == true) {
                                    _selectedIds.add(logId);
                                  } else {
                                    _selectedIds.remove(logId);
                                  }
                                });
                              },
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 14.0),
                              child: Row(
                                children: [
                                  Column(
                                    children: [
                                      Text(time, style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey.shade700, fontSize: 13)),
                                      const Text('기록', style: TextStyle(color: Colors.grey, fontSize: 10)),
                                    ],
                                  ),
                                  const SizedBox(width: 12),
                                  Container(width: 1, height: 30, color: Colors.grey.shade300),
                                  const SizedBox(width: 12),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: isCheckout ? Colors.orange.withOpacity(0.12) : Colors.blue.withOpacity(0.12),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(isCheckout ? Icons.upload_sharp : Icons.download_sharp, size: 14, color: isCheckout ? Colors.orange.shade700 : Colors.blue.shade700),
                                        const SizedBox(width: 4),
                                        Text(type, style: TextStyle(color: isCheckout ? Colors.orange.shade700 : Colors.blue.shade700, fontWeight: FontWeight.bold, fontSize: 12)),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Text(content, style: const TextStyle(fontSize: 14, color: Colors.black87, fontWeight: FontWeight.w500)),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildManagementTab() {
    return ListView(
      children: [
        Card(
          elevation: 2,
          margin: const EdgeInsets.only(bottom: 20),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('📊 대량 데이터 등록', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),
                const Text('악기 목록이 담긴 엑셀(.xlsx) 파일을 업로드하여 일괄 등록합니다.', style: TextStyle(color: Colors.grey)),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: OutlinedButton.icon(
                    onPressed: _uploadExcelToServer,
                    icon: const Icon(Icons.upload, color: Colors.green),
                    label: const Text('엑셀 파일 업로드하기', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.green), 
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        Card(
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('✍️ 개별 악기 수동 추가', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 15),
                TextField(
                  controller: _barcodeController,
                  decoration: const InputDecoration(labelText: '바코드 번호 입력', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 15),
                TextField(
                  controller: _nameController,
                  decoration: const InputDecoration(labelText: '악기 이름 입력', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _addSingleInstrument,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF6B7BFF), 
                      foregroundColor: Colors.white, 
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text('악기 등록하기', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> tabs = [
      _buildCheckInOutTab(),
      _buildInventoryTab(),
      _buildHistoryTab(),
      _buildManagementTab(),
    ];

    final List<String> titles = [
      '🔄 악기 입출고 관리 시스템',
      '📋 보유 악기 현황',
      '🕒 실시간 입출고 기록',
      '⚙️ 데이터 관리 시스템'
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(titles[_currentIndex], style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        backgroundColor: const Color(0xFF6B7BFF),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: () async {
              await _fetchInstruments();
              await _fetchHistoryLogs();
            },
          )
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: tabs[_currentIndex],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        type: BottomNavigationBarType.fixed,
        selectedItemColor: const Color(0xFF6B7BFF),
        unselectedItemColor: Colors.grey,
        showUnselectedLabels: true,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.swap_horiz), label: '입출고관리'),
          BottomNavigationBarItem(icon: Icon(Icons.inventory), label: '악기현황'),
          BottomNavigationBarItem(icon: Icon(Icons.history), label: '기록확인'),
          BottomNavigationBarItem(icon: Icon(Icons.analytics), label: '데이터관리'),
        ],
      ),
    );
  }
}