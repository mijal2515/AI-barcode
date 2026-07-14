import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:file_picker/file_picker.dart';
import 'dart:convert';
import 'package:excel/excel.dart' hide Border;

import 'package:flutter/foundation.dart' show kIsWeb; 
import 'dart:io' as io;
import 'package:path_provider/path_provider.dart';
import 'package:universal_html/html.dart' as html;
import 'app_widgets.dart';
import 'barcode_scanner_page.dart';

const String SERVER_URL = 'https://port-0-ai-barcode-mripc4hw74b4a446.sel3.cloudtype.app';

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
  final TextEditingController _categoryController = TextEditingController();
  final TextEditingController _instrumentNumberController = TextEditingController();

  final TextEditingController _checkoutBarcodeController = TextEditingController();
  final TextEditingController _checkinBarcodeController = TextEditingController();

  final TextEditingController _schoolController = TextEditingController();
  final TextEditingController _regionController = TextEditingController();
  final TextEditingController _rentalDueController = TextEditingController();
  final TextEditingController _historySearchController = TextEditingController();

  static const List<String> _statusOptions = ['보관중', '대여중', '수리중'];

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

    if (actionType == '출고' && instrument['status'] == '수리중') {
      _showSnackBar('🔧 수리 중인 악기는 출고할 수 없습니다.');
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
      targetCart.add(Map<String, dynamic>.from(instrument)..['quantity'] = 1);
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
    String regionText = _regionController.text.trim();
    String rentalDueText = _rentalDueController.text.trim();
    if (actionType == '출고' && schoolText.isEmpty) {
      _showSnackBar('🏫 출고할 학교(기관) 이름을 입력해 주세요!');
      return;
    }

    final now = DateTime.now();
    String timeNow = "${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} "
        "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}";
    String newStatus = actionType == '출고' ? '대여중' : '보관중';
    int count = targetCart.length;

    try {
      for (var scannedItem in targetCart) {
        // 🎯 출고는 지금 입력한 학교/지역으로, 입고는 반납되기 직전까지 대여 중이던 학교/지역으로 기록
        String schoolForHistory = actionType == '출고'
            ? schoolText
            : (scannedItem['school'] ?? '').toString();
        String regionForHistory = actionType == '출고'
            ? regionText
            : (scannedItem['region'] ?? '').toString();

        var url = Uri.parse('$SERVER_URL/history');
        await http.post(
          url,
          headers: {"Content-Type": "application/json"},
          body: jsonEncode({
            "time": timeNow,
            "type": actionType,
            "barcode": scannedItem['barcode'].toString(),
            "name": scannedItem['name'].toString(),
            "category": (scannedItem['category'] ?? '').toString(),
            "instrument_number": (scannedItem['instrument_number'] ?? '').toString(),
            "quantity": scannedItem['quantity'] ?? 1,
            "school": schoolForHistory,
            "region": regionForHistory,
            "rental_due": actionType == '출고' ? rentalDueText : '',
            "status": newStatus,
          }),
        );

        int index = _allInstruments.indexWhere((item) => item['barcode'].toString() == scannedItem['barcode'].toString());
        if (index != -1) {
          _allInstruments[index]['status'] = newStatus;
          _allInstruments[index]['school'] = actionType == '출고' ? schoolText : '';
          _allInstruments[index]['region'] = actionType == '출고' ? regionText : '';
        }
      }

      await _fetchHistoryLogs();

      setState(() {
        if (actionType == '출고') {
          _checkoutCart = [];
          _schoolController.clear();
          _regionController.clear();
          _rentalDueController.clear();
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
    String category = _categoryController.text.trim();
    String instrumentNumber = _instrumentNumberController.text.trim();

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
          'category': category,
          'instrument_number': instrumentNumber,
          'status': '보관중',
          'school': '',
          'region': '',
        }),
      );

      if (response.statusCode == 200) {
        var decodedData = jsonDecode(utf8.decode(response.bodyBytes));
        if (decodedData['status'] == 'success') {
          _showSnackBar('🎉 악기가 데이터베이스에 영구 저장되었습니다!');
          await _fetchInstruments();
          _barcodeController.clear();
          _nameController.clear();
          _categoryController.clear();
          _instrumentNumberController.clear();
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
    final categoryController = TextEditingController(text: instrument['category']);
    final instrumentNumberController = TextEditingController(text: instrument['instrument_number']);
    final schoolController = TextEditingController(text: instrument['school']);
    final regionController = TextEditingController(text: instrument['region']);
    String selectedStatus = _statusOptions.contains(instrument['status']) ? instrument['status'] : _statusOptions[0];

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
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
                      controller: categoryController,
                      decoration: const InputDecoration(labelText: '악기분류'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: instrumentNumberController,
                      decoration: const InputDecoration(labelText: '악기 고유번호'),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: selectedStatus,
                      decoration: const InputDecoration(labelText: '상태'),
                      items: _statusOptions
                          .map((status) => DropdownMenuItem(value: status, child: Text(status)))
                          .toList(),
                      onChanged: (value) {
                        if (value != null) setDialogState(() => selectedStatus = value);
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: schoolController,
                      decoration: const InputDecoration(labelText: '기관명 (대여처)'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: regionController,
                      decoration: const InputDecoration(labelText: '지역'),
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
                    String newCategory = categoryController.text.trim();
                    String newInstrumentNumber = instrumentNumberController.text.trim();
                    String newSchool = schoolController.text.trim();
                    String newRegion = regionController.text.trim();

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
                          'category': newCategory,
                          'instrument_number': newInstrumentNumber,
                          'status': selectedStatus,
                          'school': newSchool,
                          'region': newRegion,
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
      var url = Uri.parse('$SERVER_URL/instruments/$safeBarcode');
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
      FilePickerResult? result = await FilePicker.pickFiles(
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

  Future<void> _uploadHistoryExcelToServer() async {
    try {
      FilePickerResult? result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls'],
        withData: true,
      );
      if (result != null) {
        var fileBytes = result.files.first.bytes;
        var fileName = result.files.first.name;
        if (fileBytes == null) return;

        _showSnackBar('⏳ 기록 엑셀 데이터를 서버로 전송 중입니다...');
        var uri = Uri.parse('$SERVER_URL/history/import');
        var request = http.MultipartRequest('POST', uri);
        request.files.add(http.MultipartFile.fromBytes('file', fileBytes, filename: fileName));

        var streamedResponse = await request.send();
        var response = await http.Response.fromStream(streamedResponse);
        var decodedData = jsonDecode(utf8.decode(response.bodyBytes));

        if (decodedData['status'] == 'success') {
          _showSnackBar('🎉 ${decodedData['message']}');
          await _fetchHistoryLogs();
        } else {
          _showSnackBar('❌ ${decodedData['message'] ?? '기록 엑셀 업로드에 실패했습니다.'}');
        }
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

      // 2. 헤더 스타일 설정 (버전별 헥사코드 및 폰트 에러 수정)
      // [수정] # 기호를 빼거나 ExcelColor.fromHex를 사용하는 방식으로 안전하게 변경
      CellStyle headerStyle = CellStyle(
        backgroundColorHex: ExcelColor.fromHexString("#E6EEFF"),
        fontFamily: "Arial",          // 함수 형태 대신 문자열로 직접 지정
        bold: true,
        horizontalAlign: HorizontalAlign.Center,
      );

      // 3. 타이틀 헤더 추가
      List<String> headers = ["시간", "구분", "악기분류", "바코드", "악기 고유번호", "물품명", "신청수량", "기관명", "지역", "대여기간", "상태"];
      for (int i = 0; i < headers.length; i++) {
        var cell = sheetObject.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0));
        
        // [수정] 최신 excel 패키지는 TextCellValue 형태로 값을 넣어야 에러가 나지 않습니다.
        cell.value = TextCellValue(headers[i]); 
        //cell.cellStyle = headerStyle;
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
        String categoryValue = log['category'] ?? '';
        String barcodeValue = log['barcode'] ?? '';
        String instrumentNumberValue = log['instrument_number'] ?? '';
        String nameValue = log['name'] ?? '';
        String quantityValue = (log['quantity'] ?? 1).toString();
        String schoolValue = log['school'] ?? '';
        String regionValue = log['region'] ?? '';
        String rentalDueValue = log['rental_due'] ?? '';
        String rentalPeriodValue = rentalDueValue.isEmpty ? '' : '${timeValue.split(' ')[0]} ~ $rentalDueValue';
        String statusValue = log['status'] ?? '';

        // [수정] 일반 문자열을 TextCellValue로 감싸서 대입
        sheetObject.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: i + 1)).value = TextCellValue(timeValue);
        sheetObject.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: i + 1)).value = TextCellValue(typeValue);
        sheetObject.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: i + 1)).value = TextCellValue(categoryValue);
        sheetObject.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: i + 1)).value = TextCellValue(barcodeValue);
        sheetObject.cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: i + 1)).value = TextCellValue(instrumentNumberValue);
        sheetObject.cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: i + 1)).value = TextCellValue(nameValue);
        sheetObject.cell(CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: i + 1)).value = TextCellValue(quantityValue);
        sheetObject.cell(CellIndex.indexByColumnRow(columnIndex: 7, rowIndex: i + 1)).value = TextCellValue(schoolValue);
        sheetObject.cell(CellIndex.indexByColumnRow(columnIndex: 8, rowIndex: i + 1)).value = TextCellValue(regionValue);
        sheetObject.cell(CellIndex.indexByColumnRow(columnIndex: 9, rowIndex: i + 1)).value = TextCellValue(rentalPeriodValue);
        sheetObject.cell(CellIndex.indexByColumnRow(columnIndex: 10, rowIndex: i + 1)).value = TextCellValue(statusValue);
      }

      // ... 하단 저장 및 공유(kIsWeb) 로직은 그대로 유지하시면 됩니다 ...

      // 6. 파일 저장 및 다운로드 처리 (웹 환경 및 모바일 환경 대응)
      // 웹(Web) 환경 브라우저 다운로드 대응
      if (kIsWeb) {
        final bytes = excel.encode();
        if (bytes != null) {
          final blob = html.Blob([bytes], 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
          final url = html.Url.createObjectUrlFromBlob(blob);
          final anchor = html.AnchorElement(href: url)
            ..setAttribute("download", "DB_악기_입출고_기록_${DateTime.now().toString().split(' ')[0]}.xlsx")
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
                      builder: (context) => const BarcodeScannerPage(),
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
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('신청수량', style: TextStyle(color: Colors.grey.shade500, fontSize: 11)),
                              const SizedBox(width: 4),
                              IconButton(
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                icon: const Icon(Icons.remove_circle_outline, size: 20),
                                onPressed: () => setState(() {
                                  final qty = (item['quantity'] ?? 1) as int;
                                  if (qty > 1) item['quantity'] = qty - 1;
                                }),
                              ),
                              SizedBox(
                                width: 20,
                                child: Text('${item['quantity'] ?? 1}', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold)),
                              ),
                              IconButton(
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                icon: const Icon(Icons.add_circle_outline, size: 20),
                                onPressed: () => setState(() {
                                  final qty = (item['quantity'] ?? 1) as int;
                                  item['quantity'] = qty + 1;
                                }),
                              ),
                              const SizedBox(width: 4),
                              IconButton(
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                icon: const Icon(Icons.cancel_rounded, color: Colors.grey),
                                onPressed: () => setState(() => cart.removeAt(index)),
                              ),
                            ],
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
                labelText: '🏫 출고 대상 기관명 입력',
                labelStyle: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold),
                hintText: '예시: 서울초등학교',
                filled: true,
                fillColor: Colors.orange.withOpacity(0.03),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.orangeAccent, width: 1.5)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.orange, width: 2)),
                prefixIcon: const Icon(Icons.school, color: Colors.orange),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _regionController,
              style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange.shade800),
              decoration: InputDecoration(
                labelText: '📍 지역 입력',
                labelStyle: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold),
                hintText: '예시: 서울특별시',
                filled: true,
                fillColor: Colors.orange.withOpacity(0.03),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.orangeAccent, width: 1.5)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.orange, width: 2)),
                prefixIcon: const Icon(Icons.location_on, color: Colors.orange),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _rentalDueController,
              readOnly: true,
              style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange.shade800),
              decoration: InputDecoration(
                labelText: '📅 반납예정일 선택',
                labelStyle: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold),
                hintText: '날짜를 선택하세요',
                filled: true,
                fillColor: Colors.orange.withOpacity(0.03),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.orangeAccent, width: 1.5)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.orange, width: 2)),
                prefixIcon: const Icon(Icons.event, color: Colors.orange),
              ),
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: DateTime.now(),
                  firstDate: DateTime.now().subtract(const Duration(days: 1)),
                  lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
                );
                if (picked != null) {
                  _rentalDueController.text =
                      "${picked.year.toString().padLeft(4, '0')}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}";
                }
              },
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
                        final String region = item['region'] ?? '';
                        final String category = item['category'] ?? '';
                        final bool isRented = status == '대여중';
                        final bool isRepair = status == '수리중';
                        final Color statusColor = isRented ? Colors.orange : (isRepair ? Colors.purple : Colors.green);

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
                                  backgroundColor: statusColor.withOpacity(0.1),
                                  child: Icon(
                                    isRented ? Icons.output_sharp : (isRepair ? Icons.build_rounded : Icons.gavel_sharp),
                                    color: statusColor,
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(item['name'] ?? '이름 없음', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                      if (category.isNotEmpty) ...[
                                        const SizedBox(height: 2),
                                        Text(category, style: TextStyle(color: Colors.grey[500], fontSize: 12)),
                                      ],
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
                                          decoration: BoxDecoration(color: statusColor, borderRadius: BorderRadius.circular(20)),
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
                                      Text(
                                        region.isNotEmpty ? '🏫 $school ($region)' : '🏫 $school',
                                        style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold, fontSize: 13),
                                      ),
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
    // 검색된 결과와 선택된 항목의 개수가 일치하는지 확인하여 전체 선택 상태 결정
    bool isAllSelected = _filteredHistoryLogs.isNotEmpty && 
        _selectedIds.length == _filteredHistoryLogs.length;

    return Column(
      children: [
        // 상단: 검색 바 및 엑셀 다운로드 / 선택 삭제 버튼 레이아웃
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
        
        // 검색 결과가 있을 때만 전체 선택 체크박스 노출
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
                  style: TextStyle(color: Colors.grey.shade700, fontWeight: FontWeight.bold, fontSize: 13),
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
                      final String barcode = log['barcode'] ?? '';
                      final String name = log['name'] ?? '';
                      final String school = log['school'] ?? '';
                      final String category = log['category'] ?? '';
                      final String instrumentNumber = log['instrument_number'] ?? '';
                      final String quantity = (log['quantity'] ?? 1).toString();
                      final String region = log['region'] ?? '';
                      final String rentalDue = log['rental_due'] ?? '';
                      final String status = log['status'] ?? '';
                      final bool isCheckout = type == '출고';
                      final String content = isCheckout
                          ? '$name ($barcode) ➡️ [$school]'
                          : '$name ($barcode) [반납 완료${school.isNotEmpty ? ' · $school' : ''}]';
                      final String rentalPeriod = rentalDue.isEmpty
                          ? ''
                          : '${time.contains(' ') ? time.split(' ')[0] : time} ~ $rentalDue';
                      final List<String> detailParts = [
                        if (category.isNotEmpty) category,
                        if (instrumentNumber.isNotEmpty) '고유번호 $instrumentNumber',
                        '수량 $quantity',
                        if (region.isNotEmpty) region,
                        if (rentalPeriod.isNotEmpty) '대여기간 $rentalPeriod',
                        if (status.isNotEmpty) status,
                      ];
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
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.02),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            )
                          ],
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            // 개별 선택 체크박스
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
                                          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey.shade700, fontSize: 11),
                                          textAlign: TextAlign.center,
                                        ),
                                        // 공백 뒤에 시간('HH:mm') 세부 정보가 존재할 때만 아래 줄에 추가 렌더링
                                        if (time.contains(' ')) ...[
                                          const SizedBox(height: 3),
                                          Text(
                                            time.split(' ')[1],
                                            style: TextStyle(color: Colors.grey.shade600, fontSize: 11, fontWeight: FontWeight.w600),
                                            textAlign: TextAlign.center,
                                          ),
                                        ]
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 5),
                                  Container(width: 1, height: 32, color: Colors.grey.shade300),
                                  const SizedBox(width: 10),
                                  
                                  // 출고/입고 상태 태그 블록
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: isCheckout ? Colors.orange.withOpacity(0.12) : Colors.blue.withOpacity(0.12),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(
                                          isCheckout ? Icons.upload_sharp : Icons.download_sharp, 
                                          size: 14, 
                                          color: isCheckout ? Colors.orange.shade700 : Colors.blue.shade700
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          type, 
                                          style: TextStyle(
                                            color: isCheckout ? Colors.orange.shade700 : Colors.blue.shade700, 
                                            fontWeight: FontWeight.bold, 
                                            fontSize: 12
                                          )
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 14),
                            
                            // 우측: 입출고 상세 텍스트 내용
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.only(right: 16.0, top: 10, bottom: 10),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      content,
                                      style: const TextStyle(fontSize: 14, color: Colors.black87, fontWeight: FontWeight.w500),
                                      overflow: TextOverflow.ellipsis, // 텍스트가 기기 화면 바깥으로 넘치면 자동으로 ... 처리
                                      maxLines: 2,
                                    ),
                                    if (detailParts.isNotEmpty) ...[
                                      const SizedBox(height: 4),
                                      Text(
                                        detailParts.join(' · '),
                                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                                        overflow: TextOverflow.ellipsis,
                                        maxLines: 2,
                                      ),
                                    ],
                                  ],
                                ),
                              ),
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
          margin: const EdgeInsets.only(bottom: 20),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('📜 기록 엑셀 업로드', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),
                const Text(
                  "'시간', '구분', '바코드', '물품명', '기관명' 열은 필수이고, '악기분류', '악기 고유번호', '신청수량', '지역', '대여기간', '상태' 열은 있으면 함께 저장됩니다.",
                  style: TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: OutlinedButton.icon(
                    onPressed: _uploadHistoryExcelToServer,
                    icon: const Icon(Icons.history_toggle_off_rounded, color: Colors.blue),
                    label: const Text('기록 엑셀 업로드하기', style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold)),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.blue),
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
                const SizedBox(height: 15),
                TextField(
                  controller: _categoryController,
                  decoration: const InputDecoration(labelText: '악기분류 입력', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 15),
                TextField(
                  controller: _instrumentNumberController,
                  decoration: const InputDecoration(labelText: '악기 고유번호 입력', border: OutlineInputBorder()),
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