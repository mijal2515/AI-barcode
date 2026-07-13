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

import 'app_theme.dart';

// ⚠️ 클라우드타입 배포 후에는 대시보드에서 발급된 주소(예: https://xxxx.svc.cloudtype.app)로 바꿔주세요.
// 로컬 PC에서만 테스트할 때는 "ipconfig"로 확인한 PC의 Wi-Fi IPv4 주소를 사용하면 됩니다
// (이 경우 폰과 PC가 반드시 같은 Wi-Fi에 연결되어 있어야 합니다).
const String serverUrl = 'http://192.168.198.136:8000';

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
        final barcode = (log['barcode'] ?? '').toString().toLowerCase();
        final name = (log['name'] ?? '').toString().toLowerCase();
        final school = (log['school'] ?? '').toString().toLowerCase();
        final time = (log['time'] ?? '').toString().toLowerCase();
        final type = (log['type'] ?? '').toString().toLowerCase();
        return barcode.contains(query) || name.contains(query) || school.contains(query) ||
            time.contains(query) || type.contains(query);
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

    final DateTime now = DateTime.now();
    String timeNow = "${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} "
        "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}";
    String newStatus = actionType == '출고' ? '대여중' : '보관중';
    int count = targetCart.length;

    try {
      for (var scannedItem in targetCart) {
        // 🎯 출고는 지금 입력한 학교로, 입고는 반납되기 직전까지 대여 중이던 학교로 기록
        String schoolForHistory = actionType == '출고'
            ? schoolText
            : (scannedItem['school'] ?? '').toString();

        var url = Uri.parse('$serverUrl/history');
        await http.post(
          url,
          headers: {"Content-Type": "application/json"},
          body: jsonEncode({
            "time": timeNow,
            "type": actionType,
            "barcode": scannedItem['barcode'].toString(),
            "name": scannedItem['name'].toString(),
            "school": schoolForHistory,
          }),
        );

        String newSchool = actionType == '출고' ? schoolText : '';

        int index = _allInstruments.indexWhere((item) => item['barcode'].toString() == scannedItem['barcode'].toString());
        if (index != -1) {
          _allInstruments[index]['status'] = newStatus;
          _allInstruments[index]['school'] = newSchool;
        }

        // 🎯 상태 변경을 DB(instruments 테이블)에도 저장해서 앱/서버를 재시작해도 상태가 유지되도록 함
        var updateUrl = Uri.parse('$serverUrl/instruments/${scannedItem['barcode']}');
        await http.put(
          updateUrl,
          headers: {"Content-Type": "application/json"},
          body: jsonEncode({
            "name": scannedItem['name'].toString(),
            "status": newStatus,
            "school": newSchool,
          }),
        );
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

    if (!mounted) return;
    FocusScope.of(context).unfocus();
  }

  // 🔥 핵심 수정: id 목록을 바디에 묶어 서버로 보내는 로직으로 변경
  Future<void> _deleteSelectedHistoryLogs() async {
    if (_selectedIds.isEmpty) {
      _showSnackBar('⚠️ 삭제할 기록을 먼저 선택해 주세요!');
      return;
    }

    try {
      var url = Uri.parse('$serverUrl/history/delete-multiple');
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
      var url = Uri.parse('$serverUrl/instruments');
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
    if (!mounted) return;
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
          title: Text('[${instrument['name']}] 정보 수정'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: TextEditingController(text: instrument['barcode']),
                  decoration: const InputDecoration(labelText: '바코드 (수정 불가)', prefixIcon: Icon(Icons.qr_code_rounded)),
                  readOnly: true,
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(labelText: '악기 이름', prefixIcon: Icon(Icons.music_note_rounded)),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: statusController,
                  decoration: const InputDecoration(labelText: '상태 (보관중 / 대여중)', prefixIcon: Icon(Icons.flag_rounded)),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: schoolController,
                  decoration: const InputDecoration(labelText: '대여처 (학교명)', prefixIcon: Icon(Icons.school_rounded)),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('취소'),
            ),
            ElevatedButton(
              onPressed: () async {
                String newName = nameController.text.trim();
                String newStatus = statusController.text.trim();
                String newSchool = schoolController.text.trim();

                if (newName.isEmpty) {
                  _showSnackBar('⚠️ 악기 이름을 입력해주세요.');
                  return;
                }

                try {
                  var url = Uri.parse('$serverUrl/instruments/${instrument['barcode']}');
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
                      if (!context.mounted) return;
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
      var url = Uri.parse('$serverUrl/instruments');
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
      var url = Uri.parse('$serverUrl/instruments/$safeBarcode');
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
      var url = Uri.parse('$serverUrl/history');
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
        var uri = Uri.parse('$serverUrl/upload-excel');
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

  // 📜 엑셀(.xlsx)로 입출고 기록을 읽어 DB(history)에 대량 저장
  Future<void> _uploadHistoryExcelToServer() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls'],
        withData: true,
      );
      if (result == null) return;

      var fileBytes = result.files.first.bytes;
      var fileName = result.files.first.name;
      if (fileBytes == null) return;

      _showSnackBar('⏳ 기록 엑셀 데이터를 서버로 전송 중입니다...');
      var uri = Uri.parse('$serverUrl/history/import');
      var request = http.MultipartRequest('POST', uri);
      request.files.add(http.MultipartFile.fromBytes('file', fileBytes, filename: fileName));

      var response = await request.send();
      var responseBody = await http.Response.fromStream(response);

      if (response.statusCode == 200) {
        var decodedData = jsonDecode(utf8.decode(responseBody.bodyBytes));
        if (decodedData['status'] == 'success') {
          _showSnackBar('🎉 ${decodedData['message']}');
          await _fetchHistoryLogs();
        } else {
          _showSnackBar('❌ 기록 업로드 실패: ${decodedData['message']}');
        }
      } else {
        _showSnackBar('❌ 서버가 기록 엑셀 처리에 실패했습니다. (코드: ${response.statusCode})');
      }
    } catch (e) {
      _showSnackBar("❌ 오류 발생: $e");
    }
  }

  // 🔥 핵심 수정: id 기반 매칭으로 엑셀 출력하도록 변경
  Future<void> _downloadSelectedToExcel() async {
    if (_selectedIds.isEmpty) {
      _showSnackBar('❗ 다운로드할 기록을 먼저 선택해 주세요.');
      return;
    }

    try {
      // 1. 새로운 엑셀 워크북 및 시트 생성
      var excel = Excel.createExcel();
      String sheetName = "입출고기록";
      
      // [수정] defaultSheet 이름 변경 방식을 안전하게 수정하거나, 링크가 깨지지 않게 직접 접근
      String defaultSheet = excel.getDefaultSheet() ?? 'Sheet1';
      excel.rename(defaultSheet, sheetName);
      Sheet sheetObject = excel[sheetName];

      // 3. 타이틀 헤더 추가
      List<String> headers = ["시간", "구분", "바코드", "물품명", "대여처"];
      for (int i = 0; i < headers.length; i++) {
        var cell = sheetObject.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0));
        
        // [수정] 최신 excel 패키지는 TextCellValue 형태로 값을 넣어야 에러가 나지 않습니다.
        cell.value = TextCellValue(headers[i]);
      }

      // 4. 선택된 ID에 해당하는 데이터 필터링 (아래 5번 루프에서도 동일하게 수정)
      List<dynamic> selectedLogs = _historyLogs
          .where((log) => _selectedIds.contains(log['id']))
          .toList();
          
      selectedLogs.sort((a, b) => (b['id'] ?? 0).compareTo(a['id'] ?? 0));

      // 5. 엑셀 시트에 데이터 채우기
      for (int i = 0; i < selectedLogs.length; i++) {
        final log = selectedLogs[i];
        
        String timeValue = log['time'] ?? '';
        String typeValue = log['type'] ?? '';
        String barcodeValue = log['barcode'] ?? '';
        String nameValue = log['name'] ?? '';
        String schoolValue = log['school'] ?? '';

        // [수정] 일반 문자열을 TextCellValue로 감싸서 대입
        sheetObject.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: i + 1)).value = TextCellValue(timeValue);
        sheetObject.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: i + 1)).value = TextCellValue(typeValue);
        sheetObject.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: i + 1)).value = TextCellValue(barcodeValue);
        sheetObject.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: i + 1)).value = TextCellValue(nameValue);
        sheetObject.cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: i + 1)).value = TextCellValue(schoolValue);
      }

      // ... 하단 저장 및 공유(kIsWeb) 로직은 그대로 유지하시면 됩니다 ...

      // 6. 파일 저장 및 다운로드 처리 (웹 환경 및 모바일 환경 대응)
      // 웹(Web) 환경 브라우저 다운로드 대응
      if (kIsWeb) {
        final bytes = excel.encode();
        if (bytes != null) {
          final blob = html.Blob([bytes], 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
          final url = html.Url.createObjectUrlFromBlob(blob);
          html.AnchorElement(href: url)
            ..setAttribute("download", "DB_악기_입출고_기록.xlsx")
            ..click();
          html.Url.revokeObjectUrl(url);
          _showSnackBar('📥 선택한 ${_selectedIds.length}건의 기록이 엑셀 파일로 다운로드되었습니다.');
        }
      } else {
        // 모바일/PC 네이티브 환경 대응 (공유 및 저장 폴더 지정)
        final bytes = excel.encode();
        if (bytes != null) {
          final directory = await getApplicationDocumentsDirectory();
          final filePath = "${directory.path}/DB_history_${DateTime.now().millisecondsSinceEpoch}.xlsx";
          final file = io.File(filePath);
          await file.writeAsBytes(bytes);
          
          // 다운로드 완료 후 파일 열기 또는 공유 기능 연동 (Share 패키지 등 사용 시)
          _showSnackBar('📥 파일이 성공적으로 저장되었습니다: $filePath');
        }
      }
    } catch (e) {
      _showSnackBar('❌ 엑셀 다운로드 중 오류가 발생했습니다: $e');
    }
  }

  // 🏠 시작메뉴: 현황을 한눈에 보여주고 각 기능으로 바로 이동하는 홈 화면
  Widget _buildHomeTab() {
    final int total = _allInstruments.length;
    final int storedCount = _allInstruments.where((e) => (e['status'] ?? '보관중') == '보관중').length;
    final int rentedCount = _allInstruments.where((e) => (e['status'] ?? '') == '대여중').length;

    return ListView(
      children: [
        Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.library_music_rounded, color: Colors.white, size: 24),
            ),
            const SizedBox(width: 14),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('해봄악기도서관', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
                  SizedBox(height: 2),
                  Text('필요한 메뉴를 선택해 주세요', style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 22),
        Row(
          children: [
            Expanded(child: _HomeStatTile(label: '전체 악기', value: total, palette: StatusPalette.checkin)),
            const SizedBox(width: 10),
            Expanded(child: _HomeStatTile(label: '보관중', value: storedCount, palette: StatusPalette.stored)),
            const SizedBox(width: 10),
            Expanded(child: _HomeStatTile(label: '대여중', value: rentedCount, palette: StatusPalette.rented)),
          ],
        ),
        const SizedBox(height: 22),
        Column(
          children: [
            _HomeMenuCard(
              icon: Icons.swap_horiz_rounded,
              title: '입출고관리',
              subtitle: '바코드로 대여·반납 처리',
              palette: StatusPalette.rented,
              onTap: () => setState(() => _currentIndex = 1),
            ),
            const SizedBox(height: 10),
            _HomeMenuCard(
              icon: Icons.inventory_2_rounded,
              title: '악기현황',
              subtitle: '보유 악기 목록 조회',
              palette: StatusPalette.stored,
              onTap: () => setState(() => _currentIndex = 2),
            ),
            const SizedBox(height: 10),
            _HomeMenuCard(
              icon: Icons.history_rounded,
              title: '기록확인',
              subtitle: '입출고 이력 검색·다운로드',
              palette: StatusPalette.checkin,
              onTap: () => setState(() => _currentIndex = 3),
            ),
            const SizedBox(height: 10),
            _HomeMenuCard(
              icon: Icons.settings_rounded,
              title: '데이터관리',
              subtitle: '엑셀 업로드·악기 등록',
              palette: StatusPalette.primary,
              onTap: () => setState(() => _currentIndex = 4),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildCheckInOutTab() {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.border),
            ),
            child: TabBar(
              labelColor: Colors.white,
              unselectedLabelColor: AppColors.textSecondary,
              indicatorSize: TabBarIndicatorSize.tab,
              dividerColor: Colors.transparent,
              indicator: BoxDecoration(borderRadius: BorderRadius.circular(7), color: AppColors.primary),
              tabs: const [
                Tab(child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.upload_rounded, size: 18), SizedBox(width: 6), Text('악기 출고 (대여)', style: TextStyle(fontWeight: FontWeight.bold))])),
                Tab(child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.download_rounded, size: 18), SizedBox(width: 6), Text('악기 입고 (반납)', style: TextStyle(fontWeight: FontWeight.bold))])),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: TabBarView(
              children: [
                _buildSubActionPage('출고', _checkoutBarcodeController, _checkoutCart, StatusPalette.rented),
                _buildSubActionPage('입고', _checkinBarcodeController, _checkinCart, StatusPalette.checkin),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubActionPage(String type, TextEditingController controller, List<dynamic> cart, StatusPalette palette) {
    final Color themeColor = palette.fg;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 6.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: controller,
            autofocus: true,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
            decoration: InputDecoration(
              hintText: '바코드를 스캔하거나 입력 후 Enter ($type 모드)',
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: themeColor, width: 1.6)),
              prefixIcon: Icon(Icons.qr_code_scanner_rounded, color: themeColor),
              suffixIcon: IconButton(
                icon: Icon(Icons.camera_alt_rounded, color: AppColors.primary),
                tooltip: '휴대폰 카메라로 스캔',
                onPressed: () async {
                  var res = await SimpleBarcodeScanner.scanBarcode(context);
                  if (res is String && res != '-1') {
                    _addToCart(res, type); // 카메라로 스캔한 결과물 자동 장바구니 추가
                  }
                },
              ),
            ),
            onSubmitted: (value) => _addToCart(value, type),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.list_alt_rounded, color: AppColors.textSecondary, size: 20),
                          const SizedBox(width: 6),
                          Text('$type 대기 목록', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                            decoration: BoxDecoration(color: palette.bg, borderRadius: BorderRadius.circular(10)),
                            child: Text('${cart.length}개', style: TextStyle(color: themeColor, fontWeight: FontWeight.bold, fontSize: 13)),
                          ),
                        ],
                      ),
                      if (cart.isNotEmpty)
                        TextButton.icon(
                          onPressed: () => setState(() => type == '출고' ? _checkoutCart.clear() : _checkinCart.clear()),
                          icon: const Icon(Icons.delete_outline_rounded, size: 16, color: AppColors.danger),
                          label: const Text('전체 비우기', style: TextStyle(color: AppColors.danger, fontWeight: FontWeight.bold)),
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
                                Icon(Icons.center_focus_weak_rounded, size: 40, color: AppColors.border),
                                const SizedBox(height: 8),
                                const Text('스캔된 악기가 없습니다. 바코드를 찍어주세요.', style: TextStyle(color: AppColors.textSecondary, fontSize: 14)),
                              ],
                            ),
                          )
                        : ListView.separated(
                            itemCount: cart.length,
                            separatorBuilder: (_, _) => const SizedBox(height: 8),
                            itemBuilder: (context, index) {
                              final item = cart[index];
                              return Container(
                                decoration: BoxDecoration(
                                  color: AppColors.background,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: ListTile(
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                                  leading: Container(
                                    width: 38,
                                    height: 38,
                                    decoration: BoxDecoration(color: palette.bg, borderRadius: BorderRadius.circular(8)),
                                    child: Icon(Icons.music_note_rounded, color: themeColor, size: 19),
                                  ),
                                  title: Text(item['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppColors.textPrimary)),
                                  subtitle: Text('바코드: ${item['barcode']}', style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                                  trailing: IconButton(
                                    icon: const Icon(Icons.cancel_rounded, color: AppColors.textSecondary),
                                    onPressed: () => setState(() => cart.removeAt(index)),
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 15),
          if (type == '출고') ...[
            TextField(
              controller: _schoolController,
              style: TextStyle(fontWeight: FontWeight.bold, color: themeColor),
              decoration: InputDecoration(
                labelText: '출고 대상 학교 입력',
                labelStyle: TextStyle(color: themeColor, fontWeight: FontWeight.bold),
                hintText: '예시: 서울초등학교',
                fillColor: palette.bg,
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: themeColor.withValues(alpha: 0.35), width: 1.2)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: themeColor, width: 1.6)),
                prefixIcon: Icon(Icons.school_rounded, color: themeColor),
              ),
            ),
            const SizedBox(height: 15),
          ],
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: () => _completeBatchAction(type),
              style: ElevatedButton.styleFrom(
                backgroundColor: themeColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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

  /// 악기 이름별로 묶어 총 보유 수량 / 보관중 / 대여중 개수를 계산.
  List<MapEntry<String, List<dynamic>>> _groupInstrumentsByName() {
    final Map<String, List<dynamic>> grouped = {};
    for (final item in _allInstruments) {
      final String name = (item['name'] ?? '이름 없음').toString();
      grouped.putIfAbsent(name, () => []).add(item);
    }
    final entries = grouped.entries.toList()
      ..sort((a, b) => b.value.length.compareTo(a.value.length));
    return entries;
  }

  Widget _buildInstrumentSummaryStrip() {
    final entries = _groupInstrumentsByName();
    if (entries.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 2, bottom: 8),
          child: Text('품목별 보유 수량', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.textSecondary)),
        ),
        SizedBox(
          height: 98,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: entries.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              final String name = entries[index].key;
              final List<dynamic> items = entries[index].value;
              final int total = items.length;
              final int stored = items.where((e) => (e['status'] ?? '보관중') == '보관중').length;
              final int rented = total - stored;

              return Container(
                width: 134,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.textPrimary)),
                    const SizedBox(height: 4),
                    Text('$total개', style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: AppColors.primary)),
                    const Spacer(),
                    Text('보관 $stored · 대여 $rented', style: const TextStyle(fontSize: 10.5, color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildInventoryTab() {
    return Column(
      children: [
        _buildInstrumentSummaryStrip(),
        const SizedBox(height: 16),
        TextField(
          controller: _searchController,
          decoration: const InputDecoration(
            hintText: '바코드, 악기명 또는 대여 중인 학교 검색...',
            prefixIcon: Icon(Icons.search_rounded, color: AppColors.textSecondary),
          ),
        ),
        const SizedBox(height: 15),
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _filteredInstruments.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.inventory_2_outlined, size: 40, color: AppColors.border),
                          const SizedBox(height: 8),
                          const Text('검색 결과가 없습니다.', style: TextStyle(color: AppColors.textSecondary)),
                        ],
                      ),
                    )
                  : ListView.builder(
                      itemCount: _filteredInstruments.length,
                      itemBuilder: (context, index) {
                        final item = _filteredInstruments[index];
                        final String status = item['status'] ?? '보관중';
                        final String school = item['school'] ?? '';
                        final bool isRented = status == '대여중';
                        final StatusPalette palette = isRented ? StatusPalette.rented : StatusPalette.stored;

                        return Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  width: 44,
                                  height: 44,
                                  decoration: BoxDecoration(color: palette.bg, borderRadius: BorderRadius.circular(10)),
                                  child: Icon(isRented ? Icons.local_shipping_rounded : Icons.inventory_2_rounded, color: palette.fg, size: 22),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(item['name'] ?? '이름 없음', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.textPrimary)),
                                      const SizedBox(height: 4),
                                      Text('바코드: ${item['barcode']}', style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                                      if (isRented && school.isNotEmpty) ...[
                                        const SizedBox(height: 6),
                                        Row(
                                          children: [
                                            Icon(Icons.school_rounded, size: 14, color: palette.fg),
                                            const SizedBox(width: 4),
                                            Text(school, style: TextStyle(color: palette.fg, fontWeight: FontWeight.bold, fontSize: 12.5)),
                                          ],
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                                      decoration: BoxDecoration(color: palette.bg, borderRadius: BorderRadius.circular(6)),
                                      child: Text(status, style: TextStyle(color: palette.fg, fontSize: 12, fontWeight: FontWeight.bold)),
                                    ),
                                    const SizedBox(height: 10),
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        _RoundIconButton(
                                          icon: Icons.edit_rounded,
                                          color: AppColors.info,
                                          tooltip: '악기 정보 수정',
                                          onPressed: () => _showEditDialog(item),
                                        ),
                                        const SizedBox(width: 6),
                                        _RoundIconButton(
                                          icon: Icons.delete_rounded,
                                          color: AppColors.danger,
                                          tooltip: '악기 삭제',
                                          onPressed: () {
                                            showDialog(
                                              context: context,
                                              builder: (BuildContext context) {
                                                return AlertDialog(
                                                  title: const Text('삭제 확인'),
                                                  content: Text('[${item['name']}] 악기를 영구 삭제하시겠습니까?'),
                                                  actions: [
                                                    TextButton(
                                                      child: const Text('취소'),
                                                      onPressed: () => Navigator.of(context).pop(),
                                                    ),
                                                    TextButton(
                                                      child: const Text('삭제', style: TextStyle(color: AppColors.danger, fontWeight: FontWeight.bold)),
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
    // 검색된 결과와 선택된 항목의 개수가 일치하는지 확인하여 전체 선택 상태 결정
    bool isAllSelected = _filteredHistoryLogs.isNotEmpty &&
        _selectedIds.length == _filteredHistoryLogs.length;

    return Column(
      children: [
        // 상단: 검색 바
        TextField(
          controller: _historySearchController,
          decoration: const InputDecoration(
            hintText: 'DB 기록 검색 (학교명, 악기명 등)...',
            prefixIcon: Icon(Icons.search_rounded, color: AppColors.textSecondary),
          ),
        ),
        const SizedBox(height: 10),
        // 액션 버튼: 엑셀 다운로드 / 선택 삭제
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _downloadSelectedToExcel,
                icon: const Icon(Icons.file_download_rounded, size: 18),
                label: Text('엑셀 다운로드 (${_selectedIds.length})'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.success,
                  side: const BorderSide(color: AppColors.success, width: 1.4),
                  padding: const EdgeInsets.symmetric(vertical: 13),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () {
                  if (_selectedIds.isEmpty) return;
                  showDialog(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('기록 삭제 확인'),
                      content: Text('선택한 ${_selectedIds.length}개의 입출고 기록을 데이터베이스에서 영구 삭제하시겠습니까?'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('취소'),
                        ),
                        TextButton(
                          onPressed: () {
                            Navigator.pop(context);
                            _deleteSelectedHistoryLogs();
                          },
                          child: const Text('삭제', style: TextStyle(color: AppColors.danger, fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                  );
                },
                icon: const Icon(Icons.delete_forever_rounded, size: 18),
                label: const Text('선택 삭제'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _selectedIds.isEmpty ? AppColors.textSecondary : AppColors.danger,
                  side: BorderSide(color: _selectedIds.isEmpty ? AppColors.border : AppColors.danger, width: 1.4),
                  padding: const EdgeInsets.symmetric(vertical: 13),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),

        // 검색 결과가 있을 때만 전체 선택 체크박스 노출
        if (_filteredHistoryLogs.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4.0),
            child: Row(
              children: [
                Checkbox(
                  value: isAllSelected,
                  onChanged: (bool? value) {
                    setState(() {
                      if (value == true) {
                        // 현재 검색 결과에 보이는 모든 ID 일괄 추가
                        _selectedIds.addAll(_filteredHistoryLogs.map((e) => e['id'] as int));
                      } else {
                        _selectedIds.clear();
                      }
                    });
                  },
                ),
                Text(
                  isAllSelected ? '전체 선택 해제' : '검색 결과 전체 선택',
                  style: const TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ],
            ),
          ),
        const SizedBox(height: 5),

        // 하단: 기록 리스트 노출 영역 (당겨서 새로고침 기능 포함)
        Expanded(
          child: _filteredHistoryLogs.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.history_toggle_off_rounded, size: 40, color: AppColors.border),
                      const SizedBox(height: 8),
                      const Text('데이터베이스에 저장된 입출고 내역이 없습니다.', style: TextStyle(color: AppColors.textSecondary)),
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
                      final String barcode = log['barcode'] ?? '';
                      final String name = log['name'] ?? '';
                      final String school = log['school'] ?? '';
                      final bool isCheckout = type == '출고';
                      final String content = isCheckout
                          ? '$name ($barcode) ➡️ [$school]'
                          : '$name ($barcode) [반납 완료${school.isNotEmpty ? ' · $school' : ''}]';
                      final bool isSelected = _selectedIds.contains(logId);
                      final StatusPalette palette = isCheckout ? StatusPalette.rented : StatusPalette.checkin;

                      return Container(
                        key: ValueKey(logId),
                        margin: const EdgeInsets.only(bottom: 10),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isSelected ? AppColors.primary : AppColors.border,
                            width: isSelected ? 1.5 : 1,
                          ),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: IntrinsicHeight(
                          child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // 출고/입고를 구분하는 왼쪽 컬러 악센트 바
                            Container(width: 4, color: palette.fg),
                            Checkbox(
                              value: isSelected,
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

                            // 🛠️ 날짜 및 시간 출력부 (공백 분리형 구조)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 14.0),
                              child: Row(
                                children: [
                                  const SizedBox(width: 5),
                                  SizedBox(
                                    width: 85, // 가로 폭을 고정하여 날짜가 길어져도 UI가 밀리지 않도록 고정
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      crossAxisAlignment: CrossAxisAlignment.center,
                                      children: [
                                        // 'YYYY-MM-DD HH:mm' 형태일 경우 앞의 날짜만 추출, 구형 포맷('15:30')이면 문자열 전체 출력
                                        Text(
                                          time.contains(' ') ? time.split(' ')[0] : time,
                                          style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary, fontSize: 11),
                                          textAlign: TextAlign.center,
                                        ),
                                        // 공백 뒤에 시간('HH:mm') 세부 정보가 존재할 때만 아래 줄에 추가 렌더링
                                        if (time.contains(' ')) ...[
                                          const SizedBox(height: 3),
                                          Text(
                                            time.split(' ')[1],
                                            style: const TextStyle(color: AppColors.textSecondary, fontSize: 11, fontWeight: FontWeight.w600),
                                            textAlign: TextAlign.center,
                                          ),
                                        ]
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 5),
                                  Container(width: 1, height: 32, color: AppColors.border),
                                  const SizedBox(width: 10),

                                  // 출고/입고 상태 태그 블록
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: palette.bg,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(
                                          isCheckout ? Icons.upload_rounded : Icons.download_rounded,
                                          size: 14,
                                          color: palette.fg,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          type,
                                          style: TextStyle(color: palette.fg, fontWeight: FontWeight.bold, fontSize: 12),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 14),

                            // 우측: 입출고 상세 텍스트 내용 (행 높이 안에서 세로 중앙 정렬)
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.only(right: 16.0),
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    content,
                                    style: const TextStyle(fontSize: 14, color: AppColors.textPrimary, fontWeight: FontWeight.w500),
                                    overflow: TextOverflow.ellipsis, // 텍스트가 기기 화면 바깥으로 넘치면 자동으로 ... 처리
                                    maxLines: 2,
                                  ),
                                ),
                              ),
                            ),
                          ],
                          ),
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
          margin: const EdgeInsets.only(bottom: 16),
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _SectionHeader(icon: Icons.inventory_2_rounded, color: AppColors.success, title: '대량 데이터 등록'),
                const SizedBox(height: 10),
                const Text('악기 목록이 담긴 엑셀(.xlsx) 파일을 업로드하여 일괄 등록합니다.', style: TextStyle(color: AppColors.textSecondary)),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _uploadExcelToServer,
                    icon: const Icon(Icons.upload_rounded, size: 20),
                    label: const Text('엑셀 파일 업로드하기'),
                    style: OutlinedButton.styleFrom(foregroundColor: AppColors.success, side: const BorderSide(color: AppColors.success, width: 1.4)),
                  ),
                ),
              ],
            ),
          ),
        ),
        Card(
          margin: const EdgeInsets.only(bottom: 16),
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _SectionHeader(icon: Icons.receipt_long_rounded, color: AppColors.info, title: '입출고 기록 대량 등록'),
                const SizedBox(height: 10),
                const Text(
                  "입출고 기록이 담긴 엑셀(.xlsx) 파일을 업로드하여 일괄 등록합니다.\n첫 줄(헤더)은 '시간', '구분', '바코드', '물품명', '대여처' 순서여야 합니다.",
                  style: TextStyle(color: AppColors.textSecondary),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _uploadHistoryExcelToServer,
                    icon: const Icon(Icons.upload_file_rounded, size: 20),
                    label: const Text('기록 엑셀 파일 업로드하기'),
                    style: OutlinedButton.styleFrom(foregroundColor: AppColors.info, side: const BorderSide(color: AppColors.info, width: 1.4)),
                  ),
                ),
              ],
            ),
          ),
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _SectionHeader(icon: Icons.edit_note_rounded, color: AppColors.primary, title: '개별 악기 수동 추가'),
                const SizedBox(height: 16),
                TextField(
                  controller: _barcodeController,
                  decoration: const InputDecoration(labelText: '바코드 번호 입력', prefixIcon: Icon(Icons.qr_code_rounded)),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _nameController,
                  decoration: const InputDecoration(labelText: '악기 이름 입력', prefixIcon: Icon(Icons.music_note_rounded)),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _addSingleInstrument,
                    child: const Text('악기 등록하기'),
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
      _buildHomeTab(),
      _buildCheckInOutTab(),
      _buildInventoryTab(),
      _buildHistoryTab(),
      _buildManagementTab(),
    ];

    final List<String> titles = [
      '해봄악기도서관',
      '악기 입출고 관리',
      '보유 악기 현황',
      '실시간 입출고 기록',
      '데이터 관리',
    ];

    final List<IconData> titleIcons = [
      Icons.home_rounded,
      Icons.swap_horiz_rounded,
      Icons.inventory_2_rounded,
      Icons.history_rounded,
      Icons.settings_rounded,
    ];

    return Scaffold(
      extendBody: true,
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(titleIcons[_currentIndex], size: 19, color: AppColors.primary),
            const SizedBox(width: 8),
            Text(titles[_currentIndex]),
          ],
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: AppColors.border),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: AppColors.textSecondary),
            tooltip: '새로고침',
            onPressed: () async {
              await _fetchInstruments();
              await _fetchHistoryLogs();
            },
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: tabs[_currentIndex],
        ),
      ),
      bottomNavigationBar: DecoratedBox(
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: AppColors.border)),
        ),
        child: SafeArea(
          top: false,
          child: NavigationBar(
            selectedIndex: _currentIndex,
            onDestinationSelected: (index) => setState(() => _currentIndex = index),
            destinations: const [
              NavigationDestination(icon: Icon(Icons.home_rounded), label: '홈'),
              NavigationDestination(icon: Icon(Icons.swap_horiz_rounded), label: '입출고'),
              NavigationDestination(icon: Icon(Icons.inventory_2_rounded), label: '악기현황'),
              NavigationDestination(icon: Icon(Icons.history_rounded), label: '기록'),
              NavigationDestination(icon: Icon(Icons.settings_rounded), label: '관리'),
            ],
          ),
        ),
      ),
    );
  }
}

/// 작은 원형 배경의 아이콘 버튼. 목록 카드의 수정/삭제 액션에 사용.
class _RoundIconButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String tooltip;
  final VoidCallback onPressed;

  const _RoundIconButton({
    required this.icon,
    required this.color,
    required this.tooltip,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onPressed,
        child: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(color: color.withValues(alpha: 0.1), shape: BoxShape.circle),
          child: Icon(icon, color: color, size: 18),
        ),
      ),
    );
  }
}

/// 데이터 관리 탭 각 카드 상단의 아이콘 배지 + 제목 헤더.
class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;

  const _SectionHeader({required this.icon, required this.color, required this.title});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, color: color, size: 18),
        ),
        const SizedBox(width: 10),
        Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
      ],
    );
  }
}

/// 홈 화면 상단의 요약 통계 타일 (전체/보관중/대여중 개수).
class _HomeStatTile extends StatelessWidget {
  final String label;
  final int value;
  final StatusPalette palette;

  const _HomeStatTile({required this.label, required this.value, required this.palette});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(color: palette.bg, borderRadius: BorderRadius.circular(10)),
      child: Column(
        children: [
          Text('$value', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: palette.fg)),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

/// 홈 화면(시작메뉴)에서 각 기능으로 이동하는 카드 버튼.
class _HomeMenuCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final StatusPalette palette;
  final VoidCallback onTap;

  const _HomeMenuCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.palette,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        splashColor: palette.fg.withValues(alpha: 0.08),
        highlightColor: palette.fg.withValues(alpha: 0.04),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(color: palette.bg, borderRadius: BorderRadius.circular(12)),
                child: Icon(icon, color: palette.fg, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary, size: 22),
            ],
          ),
        ),
      ),
    );
  }
}