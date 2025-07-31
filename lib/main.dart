import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:logger/logger.dart';
import 'dart:io';
import 'dart:async';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Supabaseの初期化（後でAPIキーを設定）
  // ★ あなたのSupabaseプロジェクトのURLとANON KEYに書き換えてください
  await Supabase.initialize(
    url: 'https://pefwaiptgdqwefwljaks.supabase.co',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InBlZndhaXB0Z2Rxd2Vmd2xqYWtzIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTMxMTczNDEsImV4cCI6MjA2ODY5MzM0MX0.zTb6JKPL_bVN0ZTjPE1069g4cM9bo9DdpaGjYPNP9Js',
  );
  
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BLE スキャナー',
      home: const BleTestPage(),
    );
  }
}

class BleTestPage extends StatefulWidget {
  const BleTestPage({super.key});

  @override
  State<BleTestPage> createState() => _BleTestPageState();
}

class _BleTestPageState extends State<BleTestPage> {
  String _status = "準備中...";
  List<String> _foundDevices = [];
  bool _isScanning = false;
  Timer? _scanTimer;
  StreamSubscription<List<ScanResult>>? _scanSubscription;
  
  // Supabaseクライアントとロガー
  final SupabaseClient _supabase = Supabase.instance.client;
  final Logger _logger = Logger();
  
  // マッチング機能用の変数
  final List<Map<String, dynamic>> _detectedDevices = []; // 検出されたデバイスのリスト
  final List<String> _likedDevices = []; // Likeしたデバイスのリスト
  final List<String> _nopedDevices = []; // Nopeしたデバイスのリスト
  final List<Map<String, dynamic>> _matchEvents = []; // マッチイベントの履歴
  bool _isInEvent = false; // イベント画面に遷移中かどうか
  Map<String, dynamic>? _currentMatchEvent; // 現在のマッチイベント
  
  // スワイプマッチング用の変数
  bool _isInSwipeMode = true; // スワイプモード中かどうか（デフォルトでスワイプモード）
  int _currentDeviceIndex = 0; // 現在表示しているデバイスのインデックス
  
  // チャット機能用の変数
  bool _isInChat = false; // チャット画面に遷移中かどうか
  String? _currentChatRoomId; // 現在のチャットルームID
  String? _currentPartnerMac; // チャット相手のMACアドレス
  String? _currentPartnerName; // チャット相手の名前
  final TextEditingController _messageController = TextEditingController();
  final List<Map<String, dynamic>> _messages = []; // チャットメッセージのリスト
  Timer? _messageRefreshTimer; // メッセージ更新用タイマー
  
  // 固定の自分のMACアドレス（アプリ起動時に一度だけ生成）
  late final String _myMac;
  static const String _myName = "あなた";


  @override
  void initState() {
    super.initState();
    // 固定のMACアドレスを生成（一度だけ）
    _myMac = "user_${DateTime.now().millisecondsSinceEpoch}";
    _initializeScanning();
  }

  @override
  void dispose() {
    _scanTimer?.cancel();
    _scanSubscription?.cancel();
    _messageRefreshTimer?.cancel();
    _messageController.dispose();
    FlutterBluePlus.stopScan();
    super.dispose();
  }

  Future<void> _initializeScanning() async {
    // 1. 権限確認と要求
    if (!await _checkAndRequestPermissions()) {
      return;
    }

    // 2. 初期化完了（手動スキャンに変更）
    setState(() {
      _status = "準備完了 - スキャンボタンを押してください";
    });
  }

  Future<bool> _checkAndRequestPermissions() async {
    setState(() {
      _status = "権限を確認中...";
    });

    // 必要な権限を要求
    if (Platform.isAndroid) {
      await Permission.bluetoothScan.request();
      await Permission.bluetoothConnect.request();
      await Permission.locationWhenInUse.request();
    }

    // 権限状態を確認
    final bluetoothScanGranted = await Permission.bluetoothScan.status;
    final locationGranted = await Permission.locationWhenInUse.status;
    
    if (Platform.isAndroid && (!bluetoothScanGranted.isGranted || !locationGranted.isGranted)) {
      setState(() { 
        _status = "権限が不足しています:\n"
                 "Bluetoothスキャン: ${bluetoothScanGranted.isGranted ? '許可' : '拒否'}\n"
                 "位置情報: ${locationGranted.isGranted ? '許可' : '拒否'}"; 
      });
      openAppSettings();
      return false;
    }

    return true;
  }

  // 手動スキャンを開始
  void _startManualScan() {
    if (_isScanning) return; // 既にスキャン中の場合は何もしない
    
    _performScan();
  }

  Future<void> _performScan() async {
    if (!mounted) return;

    setState(() {
      _status = "スキャン中...";
      _isScanning = true;
    });

    try {
      // 既存のスキャンを停止
      await FlutterBluePlus.stopScan();
      
      // 新しいスキャンを開始（10秒間）
      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 10),
      );

      // スキャン結果を監視
      _scanSubscription?.cancel();
      _scanSubscription = FlutterBluePlus.scanResults.listen((results) {
        if (!mounted) return;
        
        for (var r in results) {
          final name = r.device.platformName;
          final macAddress = r.device.remoteId.toString();
          final rssi = r.rssi;
          final displayName = name.isNotEmpty ? name : 'Unknown';
          
          // 既に処理済み（like/nope済み）のデバイスはスキップ
          if (_likedDevices.contains(macAddress) || _nopedDevices.contains(macAddress)) {
            continue;
          }
          
          // 新しいデバイスを検出リストに追加（重複チェック）
          final existingIndex = _detectedDevices.indexWhere((device) => device['mac_address'] == macAddress);
          if (existingIndex == -1) {
            _detectedDevices.add({
              'device_name': displayName,
              'mac_address': macAddress,
              'rssi': rssi,
              'detected_at': DateTime.now(),
            });
          } else {
            // 既存デバイスのRSSI値を更新
            _detectedDevices[existingIndex]['rssi'] = rssi;
          }
        }
        
        // 表示用リストを更新（従来のリスト表示用）
        final newDevices = <String>[];
        for (var device in _detectedDevices) {
          newDevices.add("${device['device_name']} (${device['mac_address']}) RSSI: ${device['rssi']}");
        }
        
        setState(() {
          _foundDevices = newDevices;
          _status = "スキャン中... (${_detectedDevices.length}件検出) Like: ${_likedDevices.length}件";
        });
      });

      // スキャン完了を待機
      await FlutterBluePlus.isScanning.where((val) => val == false).first;

      // スキャン完了後、結果をデータベースに保存
      if (_foundDevices.isNotEmpty) {
        await _saveScanResults();
      }

    } catch (e) {
      if (mounted) {
        setState(() { _status = "スキャンエラー: ${e.toString()}"; });
        _logger.e("スキャンエラー", error: e);
      }
    } finally {
      if (mounted) {
        setState(() {
          _isScanning = false;
          _status = "スキャン完了 (${_detectedDevices.length}件検出) - 再スキャンまたはスワイプしてください";
        });
      }
    }
  }

  // デバイスをLikeする（右スワイプ時）
  void _likeDevice(Map<String, dynamic> device) {
    final macAddress = device['mac_address'] as String;
    final deviceName = device['device_name'] as String;
    final rssi = device['rssi'] as int;
    
    // Likeリストに追加
    _likedDevices.add(macAddress);
    
    // 即座にマッチング成立
    final matchEvent = {
      'device_name': deviceName,
      'mac_address': macAddress,
      'rssi': rssi,
      'matched_at': DateTime.now(),
    };
    
    setState(() {
      _matchEvents.add(matchEvent);
      _currentMatchEvent = matchEvent;
      _isInEvent = true; // イベント画面に遷移
    });
    
    _logger.i("マッチング成功: $deviceName ($macAddress)");
    
    // スキャンを停止
    _stopScanning();
    
    // マッチイベントをデータベースに保存
    _saveMatchEvent(matchEvent);
  }
  
  // デバイスをNopeする（左スワイプ時）
  void _nopeDevice(Map<String, dynamic> device) {
    final macAddress = device['mac_address'] as String;
    
    // Nopeリストに追加
    _nopedDevices.add(macAddress);
    
    // 検出リストから削除
    _detectedDevices.removeWhere((d) => d['mac_address'] == macAddress);
    
    // next deviceを表示
    setState(() {
      if (_currentDeviceIndex >= _detectedDevices.length && _detectedDevices.isNotEmpty) {
        _currentDeviceIndex = 0;
      }
    });
    
    _logger.i("デバイスをNope: $macAddress");
  }
  
  // スキャンを停止する
  void _stopScanning() {
    _scanTimer?.cancel();
    _scanSubscription?.cancel();
    FlutterBluePlus.stopScan();
    
    setState(() {
      _isScanning = false;
      _status = "イベント発生により一時停止中";
    });
    
    _logger.i("スキャンを停止しました");
  }
  
  // スキャンを再開する
  void _resumeScanning() {
    setState(() {
      _isInEvent = false;
      _currentMatchEvent = null;
    });
    
    // スキャンを再開（手動スキャンに変更）
    setState(() {
      _status = "準備完了 - スキャンボタンを押してください";
    });
    _logger.i("スキャンを再開しました");
  }
  
  // マッチング通知を表示
  void _showMatchNotification(String deviceName, String macAddress) {
    if (!mounted) return;
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.favorite, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '💖 マッチング成功!\n$deviceName と接続しました',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        backgroundColor: Colors.pink,
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: '詳細',
          textColor: Colors.white,
          onPressed: () => _showMatchDetails(deviceName, macAddress),
        ),
      ),
    );
  }
  
  // マッチ詳細を表示
  void _showMatchDetails(String deviceName, String macAddress) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.favorite, color: Colors.pink),
            SizedBox(width: 8),
            Text('マッチング成功!'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('デバイス名: $deviceName'),
            Text('MAC: $macAddress'),
            const SizedBox(height: 8),
            const Text('このデバイスと5回以上遭遇しました！'),
            const Text('お近くにいる可能性があります。'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
  
  // マッチイベントをデータベースに保存
  Future<void> _saveMatchEvent(Map<String, dynamic> matchEvent) async {
    try {
      await _supabase.from('match_events').insert({
        'device_name': matchEvent['device_name'],
        'mac_address': matchEvent['mac_address'],
        'rssi': matchEvent['rssi'],
        'matched_at': matchEvent['matched_at'].toIso8601String(),
        'created_at': DateTime.now().toIso8601String(),
      });
      _logger.i("マッチイベントを保存しました");
    } catch (e) {
      _logger.e("マッチイベント保存エラー", error: e);
    }
  }

  Future<void> _saveScanResults() async {
    try {
      final scanSession = DateTime.now().toIso8601String();
      
      // 各デバイスの情報を解析してデータベースに保存
      for (var deviceInfo in _foundDevices) {
        final parts = deviceInfo.split(' ');
        String deviceName = 'Unknown';
        String deviceId = '';
        int rssi = 0;
        
        // パース処理（例: "Device Name (12:34:56:78:90:AB) RSSI: -45"）
        if (parts.isNotEmpty) {
          final rssiIndex = parts.lastIndexOf('RSSI:');
          if (rssiIndex != -1 && rssiIndex + 1 < parts.length) {
            rssi = int.tryParse(parts[rssiIndex + 1]) ?? 0;
          }
          
          // デバイス名とIDの抽出
          final fullInfo = deviceInfo.split(' RSSI:')[0];
          final parenIndex = fullInfo.lastIndexOf('(');
          if (parenIndex != -1) {
            deviceName = fullInfo.substring(0, parenIndex).trim();
            deviceId = fullInfo.substring(parenIndex + 1).replaceAll(')', '').trim();
          }
        }
        
        // データベースに挿入
        await _supabase.from('ble_scan_results').insert({
          'scan_session': scanSession,
          'device_name': deviceName,
          'device_id': deviceId,
          'rssi': rssi,
          'detected_at': DateTime.now().toIso8601String(),
        });
      }
      
      _logger.i("スキャン結果を保存しました: ${_foundDevices.length}件");
      
    } catch (e) {
      _logger.e("データベース保存エラー", error: e);
      if (mounted) {
        setState(() {
          _status = "DB保存エラー: ${e.toString()}";
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // チャット画面の場合
    if (_isInChat) {
      return _buildChatPage();
    }
    
    // イベント画面の場合
    if (_isInEvent && _currentMatchEvent != null) {
      return _buildEventPage();
    }
    
    // 通常のスキャン画面
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text("BLE マッチングアプリ"),
          backgroundColor: Colors.pink,
          foregroundColor: Colors.white,
          bottom: const TabBar(
            indicatorColor: Colors.white,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            tabs: [
              Tab(icon: Icon(Icons.bluetooth_searching), text: "スキャン"),
              Tab(icon: Icon(Icons.favorite), text: "マッチ履歴"),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            // スキャンタブ
            Column(
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16.0),
                  color: Colors.grey[100],
                  child: Column(
                    children: [
                      Text(
                        _status,
                        style: Theme.of(context).textTheme.titleMedium,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      if (_isScanning)
                        const LinearProgressIndicator(color: Colors.pink)
                      else
                        Container(height: 4),
                      const SizedBox(height: 8),
                      // スキャンボタン
                      ElevatedButton.icon(
                        onPressed: _isScanning ? null : _startManualScan,
                        icon: Icon(_isScanning ? Icons.hourglass_empty : Icons.bluetooth_searching),
                        label: Text(_isScanning ? "スキャン中..." : "スキャン開始"),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.pink,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: Colors.grey,
                          disabledForegroundColor: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _buildStatusCard("検出デバイス", _detectedDevices.length.toString(), Icons.bluetooth),
                          _buildStatusCard("マッチング", _likedDevices.length.toString(), Icons.favorite),
                          _buildStatusCard("Nope済み", _nopedDevices.length.toString(), Icons.close),
                        ],
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: _buildSwipeCards(),
                ),
              ],
            ),
            // マッチ履歴タブ
            _buildMatchHistoryTab(),
          ],
        ),
      ),
    );
  }

  // イベントページを構築
  Widget _buildEventPage() {
    final event = _currentMatchEvent!;
    final deviceName = event['device_name'] as String;
    final matchedAt = event['matched_at'] as DateTime;
    
    return Scaffold(
      backgroundColor: Colors.pink[50],
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // メインイベント表示
                Container(
                  padding: const EdgeInsets.all(32.0),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.pink.withValues(alpha: 0.3),
                        blurRadius: 20,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      const Icon(
                        Icons.favorite,
                        size: 80,
                        color: Colors.pink,
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        "💖 マッチング成功！ 💖",
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: Colors.pink,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      Text(
                        "特別なイベントが発生しました！",
                        style: TextStyle(
                          fontSize: 18,
                          color: Colors.grey[700],
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.pink[100],
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          children: [
                            Text(
                              "マッチしたデバイス:",
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey[600],
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              deviceName,
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Colors.pink,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              "時刻: ${_formatDateTime(matchedAt)}",
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 48),
                // ボタン群
                Column(
                  children: [
                    ElevatedButton(
                      onPressed: _resumeScanning,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.pink,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(25),
                        ),
                      ),
                      child: const Text(
                        "スキャンを再開",
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextButton(
                      onPressed: _startChat,
                      child: const Text(
                        "チャットを開始",
                        style: TextStyle(color: Colors.pink),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatusCard(String title, String value, IconData icon) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          children: [
            Icon(icon, color: Colors.pink),
            const SizedBox(height: 4),
            Text(
              value,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            Text(
              title,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMatchHistoryTab() {
    return _matchEvents.isEmpty
        ? const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.favorite_border, size: 64, color: Colors.grey),
                SizedBox(height: 16),
                Text(
                  "まだマッチングがありません",
                  style: TextStyle(fontSize: 16, color: Colors.grey),
                ),
                SizedBox(height: 8),
                Text(
                  "同じBLEデバイスを5回検知するとマッチングします",
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          )
        : ListView.builder(
            itemCount: _matchEvents.length,
            itemBuilder: (context, index) {
              final event = _matchEvents[_matchEvents.length - 1 - index]; // 新しい順に表示
              final matchedAt = event['matched_at'] as DateTime;
              
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: ListTile(
                  leading: const Icon(Icons.favorite, color: Colors.pink),
                  title: Text(
                    event['device_name'],
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('MAC: ${event['mac_address']}'),
                      Text('RSSI: ${event['rssi']}'),
                      Text('マッチ時刻: ${_formatDateTime(matchedAt)}'),
                    ],
                  ),
                  isThreeLine: true,
                  trailing: IconButton(
                    icon: const Icon(Icons.chat, color: Colors.blue),
                    onPressed: () => _startChatWithDevice(
                      event['mac_address'],
                      event['device_name'],
                    ),
                    tooltip: 'チャットを開始',
                  ),
                  onTap: () => _showMatchDetails(event['device_name'], event['mac_address']),
                ),
              );
            },
          );
  }

  String _formatDateTime(DateTime dateTime) {
    return '${dateTime.month}/${dateTime.day} ${dateTime.hour}:${dateTime.minute.toString().padLeft(2, '0')}';
  }

  // スワイプカード形式の画面を構築
  Widget _buildSwipeCards() {
    // 未処理のデバイスのみを表示
    final unprocessedDevices = _detectedDevices
        .where((device) => 
            !_likedDevices.contains(device['mac_address']) && 
            !_nopedDevices.contains(device['mac_address']))
        .toList();

    if (unprocessedDevices.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.bluetooth_searching, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              "BLEデバイスを検索中...",
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
            SizedBox(height: 8),
            Text(
              "右スワイプでLike、左スワイプでNopeできます",
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      );
    }

    // 現在のインデックスを調整
    if (_currentDeviceIndex >= unprocessedDevices.length) {
      _currentDeviceIndex = 0;
    }

    final currentDevice = unprocessedDevices[_currentDeviceIndex];

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: GestureDetector(
          onHorizontalDragEnd: (details) {
            // 右スワイプ（Like）
            if (details.primaryVelocity! > 0) {
              _likeDevice(currentDevice);
            }
            // 左スワイプ（Nope）
            else if (details.primaryVelocity! < 0) {
              _nopeDevice(currentDevice);
            }
          },
          child: Container(
            width: double.infinity,
            height: 400,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.grey.withValues(alpha: 0.3),
                  blurRadius: 10,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // デバイスアイコン
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.blue[100],
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.bluetooth,
                      size: 50,
                      color: Colors.blue[600],
                    ),
                  ),
                  const SizedBox(height: 20),
                  
                  // デバイス名
                  Text(
                    currentDevice['device_name'],
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 10),
                  
                  // MACアドレス
                  Text(
                    currentDevice['mac_address'],
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[600],
                    ),
                  ),
                  const SizedBox(height: 10),
                  
                  // RSSI値
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.grey[200],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'RSSI: ${currentDevice['rssi']}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(height: 30),
                  
                  // スワイプ指示
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      Column(
                        children: [
                          Icon(Icons.arrow_back, color: Colors.red[400], size: 30),
                          const SizedBox(height: 4),
                          Text(
                            'Nope',
                            style: TextStyle(color: Colors.red[400], fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      Column(
                        children: [
                          Icon(Icons.arrow_forward, color: Colors.green[400], size: 30),
                          const SizedBox(height: 4),
                          Text(
                            'Like',
                            style: TextStyle(color: Colors.green[400], fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  
                  // ボタン（タップでもOK）
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      ElevatedButton(
                        onPressed: () => _nopeDevice(currentDevice),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red[400],
                          foregroundColor: Colors.white,
                          shape: const CircleBorder(),
                          padding: const EdgeInsets.all(16),
                        ),
                        child: const Icon(Icons.close, size: 30),
                      ),
                      ElevatedButton(
                        onPressed: () => _likeDevice(currentDevice),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green[400],
                          foregroundColor: Colors.white,
                          shape: const CircleBorder(),
                          padding: const EdgeInsets.all(16),
                        ),
                        child: const Icon(Icons.favorite, size: 30),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // チャット機能の実装
  
  // チャットを開始する（現在のマッチイベントから）
  void _startChat() async {
    if (_currentMatchEvent == null) return;
    
    final partnerMac = _currentMatchEvent!['mac_address'] as String;
    final partnerName = _currentMatchEvent!['device_name'] as String;
    
    await _startChatWithDevice(partnerMac, partnerName);
  }
  
  // 指定されたデバイスとチャットを開始する
  Future<void> _startChatWithDevice(String partnerMac, String partnerName) async {
    try {
      // チャットルームを作成または取得（固定のmyMacを使用）
      final response = await _supabase.rpc('create_or_get_chat_room', params: {
        'mac1': _myMac,
        'mac2': partnerMac,
        'name1': _myName,
        'name2': partnerName,
      });
      
      setState(() {
        _isInChat = true;
        _isInEvent = false;
        _currentChatRoomId = response as String;
        _currentPartnerMac = partnerMac;
        _currentPartnerName = partnerName;
      });
      
      // メッセージを読み込み
      await _loadMessages();
      
      // メッセージの定期更新を開始
      _startMessageRefresh();
      
      _logger.i("チャットを開始しました: $_currentChatRoomId (Partner: $partnerName)");
      
    } catch (e) {
      _logger.e("チャット開始エラー", error: e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("チャット開始に失敗しました: ${e.toString()}"),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
  
  // メッセージを読み込む
  Future<void> _loadMessages() async {
    if (_currentChatRoomId == null) return;
    
    try {
      final response = await _supabase
          .from('chat_messages')
          .select()
          .eq('room_id', _currentChatRoomId!)
          .order('sent_at', ascending: true);
      
      setState(() {
        _messages.clear();
        _messages.addAll(List<Map<String, dynamic>>.from(response));
      });
      
    } catch (e) {
      _logger.e("メッセージ読み込みエラー", error: e);
    }
  }
  
  // メッセージの定期更新を開始
  void _startMessageRefresh() {
    _messageRefreshTimer?.cancel();
    _messageRefreshTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      if (_isInChat) {
        _loadMessages();
      }
    });
  }
  
  // メッセージを送信する
  Future<void> _sendMessage() async {
    final message = _messageController.text.trim();
    if (message.isEmpty || _currentChatRoomId == null) return;
    
    try {
      await _supabase.rpc('send_message', params: {
        'room_id_param': _currentChatRoomId!,
        'sender_mac_param': _myMac,
        'sender_name_param': _myName,
        'message_param': message,
        'message_type_param': 'text',
      });
      
      _messageController.clear();
      
      // 即座にメッセージを更新
      await _loadMessages();
      
      // 自動返信を送信（1-3秒後）
      _scheduleAutoReply(message);
      
    } catch (e) {
      _logger.e("メッセージ送信エラー", error: e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("メッセージ送信に失敗しました: ${e.toString()}"),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
  
  // 自動返信をスケジュール
  void _scheduleAutoReply(String userMessage) {
    if (_currentChatRoomId == null || _currentPartnerMac == null) return;
    
    // 1-3秒後にランダムで返信
    final delay = Duration(seconds: 1 + (DateTime.now().millisecondsSinceEpoch % 3));
    
    Timer(delay, () async {
      if (!_isInChat) return; // チャット画面を離れている場合はスキップ
      
      final replyMessage = _generateAutoReply(userMessage);
      
      try {
        await _supabase.rpc('send_message', params: {
          'room_id_param': _currentChatRoomId!,
          'sender_mac_param': _currentPartnerMac!,
          'sender_name_param': _currentPartnerName!,
          'message_param': replyMessage,
          'message_type_param': 'text',
        });
        
        // メッセージを更新
        await _loadMessages();
        
      } catch (e) {
        _logger.e("自動返信エラー", error: e);
      }
    });
  }
  
  // 自動返信メッセージを生成
  String _generateAutoReply(String userMessage) {
    List<String> candidates = [];
    
    // 挨拶に対する返信
    if (userMessage.contains(RegExp(r'こんにちは|おはよう|こんばんは|はじめまして'))) {
      candidates.addAll([
        "こんにちは！よろしくお願いします😊",
        "はじめまして！近くにいるんですね✨",
        "こんにちは！偶然ですね💖",
      ]);
    }
    
    // 質問に対する返信
    if (userMessage.contains('？') || userMessage.contains('?')) {
      candidates.addAll([
        "そうですね！どう思いますか？",
        "いい質問ですね🤔",
        "う〜ん、考えてみますね💭",
        "気になりますよね！",
      ]);
    }
    
    // 感情表現に対する返信
    if (userMessage.contains(RegExp(r'嬉しい|楽しい|面白い'))) {
      candidates.addAll([
        "私も嬉しいです！🎉",
        "楽しいですよね〜😄",
        "そう言ってもらえて嬉しいです💕",
      ]);
    }
    
    if (userMessage.contains(RegExp(r'疲れた|大変|忙しい'))) {
      candidates.addAll([
        "お疲れ様です😌",
        "大変でしたね💦",
        "ゆっくり休んでくださいね🍵",
      ]);
    }
    
    // 候補がない場合は一般的な返信を追加
    if (candidates.isEmpty) {
      candidates.addAll([
        "そうなんですね！",
        "面白いですね〜✨",
        "なるほど🤔",
        "それは素敵ですね💖",
        "私もそう思います！",
        "教えてくれてありがとう😊",
        "へ〜、知らなかったです！",
        "いいですね〜🌟",
        "確かに！",
        "そういえばそうですね💡",
      ]);
    }
    
    // ランダムに選択
    final randomIndex = DateTime.now().millisecondsSinceEpoch % candidates.length;
    return candidates[randomIndex];
  }
  
  // チャットから戻る
  void _exitChat() {
    _messageRefreshTimer?.cancel();
    setState(() {
      _isInChat = false;
      _currentChatRoomId = null;
      _currentPartnerMac = null;
      _currentPartnerName = null;
      _messages.clear();
    });
  }
  
  // チャット画面を構築
  Widget _buildChatPage() {
    return Scaffold(
      appBar: AppBar(
        title: Text("💬 $_currentPartnerName"),
        backgroundColor: Colors.pink,
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _exitChat,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadMessages,
          ),
        ],
      ),
      body: Column(
        children: [
          // メッセージリスト
          Expanded(
            child: _messages.isEmpty
                ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.chat_bubble_outline, size: 64, color: Colors.grey),
                        SizedBox(height: 16),
                        Text(
                          "まだメッセージがありません",
                          style: TextStyle(fontSize: 16, color: Colors.grey),
                        ),
                        SizedBox(height: 8),
                        Text(
                          "最初のメッセージを送信してみましょう！",
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final message = _messages[index];
                      final isMyMessage = message['sender_name'] == _myName;
                      final sentAt = DateTime.parse(message['sent_at']);
                      
                      return Container(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          mainAxisAlignment: isMyMessage 
                              ? MainAxisAlignment.end 
                              : MainAxisAlignment.start,
                          children: [
                            Container(
                              constraints: BoxConstraints(
                                maxWidth: MediaQuery.of(context).size.width * 0.7,
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                              decoration: BoxDecoration(
                                color: isMyMessage 
                                    ? Colors.pink 
                                    : Colors.grey[200],
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Column(
                                crossAxisAlignment: isMyMessage 
                                    ? CrossAxisAlignment.end 
                                    : CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    message['message'],
                                    style: TextStyle(
                                      color: isMyMessage 
                                          ? Colors.white 
                                          : Colors.black87,
                                      fontSize: 16,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _formatDateTime(sentAt),
                                    style: TextStyle(
                                      color: isMyMessage 
                                          ? Colors.white70 
                                          : Colors.grey[600],
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
          // メッセージ入力エリア
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.grey.withValues(alpha: 0.3),
                  blurRadius: 5,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    decoration: InputDecoration(
                      hintText: "メッセージを入力...",
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(25),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: Colors.grey[100],
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                    ),
                    maxLines: null,
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                const SizedBox(width: 12),
                FloatingActionButton(
                  onPressed: _sendMessage,
                  backgroundColor: Colors.pink,
                  mini: true,
                  child: const Icon(
                    Icons.send,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}