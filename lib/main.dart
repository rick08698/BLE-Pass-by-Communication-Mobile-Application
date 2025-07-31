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
      title: 'Bluetooth Love',
      home: const TitlePage(),
    );
  }
}

// タイトル画面
class TitlePage extends StatelessWidget {
  const TitlePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.pink[100]!,
              Colors.pink[50]!,
              Colors.white,
            ],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Spacer(),
                
                // メインタイトル
                const Icon(
                  Icons.favorite,
                  size: 80,
                  color: Colors.pink,
                ),
                const SizedBox(height: 30),
                
                const Text(
                  'Bluetooth Love',
                  style: TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.bold,
                    color: Colors.pink,
                    letterSpacing: 2.0,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                
                // サブタイトル
                Text(
                  '~romance begins with a chance encounter~',
                  style: TextStyle(
                    fontSize: 16,
                    fontStyle: FontStyle.italic,
                    color: Colors.grey[600],
                    letterSpacing: 1.0,
                  ),
                  textAlign: TextAlign.center,
                ),
                
                const SizedBox(height: 50),
                
                // 説明文
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.8),
                    borderRadius: BorderRadius.circular(15),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.grey.withValues(alpha: 0.2),
                        blurRadius: 10,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Icon(
                        Icons.bluetooth_searching,
                        size: 40,
                        color: Colors.blue[400],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Bluetoothで近くの人と出会おう',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey[800],
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'スワイプでマッチング、チャットで会話\n新しい出会いがあなたを待っています',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[600],
                          height: 1.5,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
                
                const Spacer(),
                
                // スタートボタン
                SizedBox(
                  width: double.infinity,
                  height: 60,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.of(context).pushReplacement(
                        MaterialPageRoute(
                          builder: (context) => const BleTestPage(),
                        ),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.pink,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                      elevation: 5,
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.play_arrow, size: 28),
                        SizedBox(width: 8),
                        Text(
                          'はじめる',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 30),
              ],
            ),
          ),
        ),
      ),
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
  
  // アニメーション関連
  double _cardOffset = 0.0; // カードの水平オフセット
  double _cardRotation = 0.0; // カードの回転角度
  bool _isDragging = false; // ドラッグ中かどうか
  
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
  
  // 告白促進機能用の変数
  final Map<String, int> _messageCountPerRoom = {}; // チャットルームごとのメッセージ数
  final Set<String> _confessionPromptShown = {}; // 告白促進が表示済みのルーム


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
    
    // Tinder風のUI
    return Scaffold(
      backgroundColor: Colors.grey[100],
      body: _buildTinderMainScreen(),
      bottomNavigationBar: _buildTinderBottomBar(),
    );
  }

  // Tinder風のメイン画面
  Widget _buildTinderMainScreen() {
    return SafeArea(
      child: Column(
        children: [
          // Tinder風のヘッダー
          _buildTinderHeader(),
          // カードエリア
          Expanded(
            child: _buildTinderSwipeArea(),
          ),
          // アクションボタン
          _buildTinderActionButtons(),
        ],
      ),
    );
  }

  // Tinder風のヘッダー
  Widget _buildTinderHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          // プロフィールアイコン
          GestureDetector(
            onTap: () {}, // プロフィール画面への遷移
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.person, size: 20, color: Colors.grey[600]),
            ),
          ),
          const Spacer(),
          // Tinderロゴ風
          const Icon(
            Icons.local_fire_department,
            color: Color(0xFFFF6B6B),
            size: 32,
          ),
          const Spacer(),
          // 設定アイコン
          GestureDetector(
            onTap: _showSettingsDialog,
            child: const Icon(
              Icons.tune,
              color: Colors.grey,
              size: 28,
            ),
          ),
        ],
      ),
    );
  }

  // 設定ダイアログ
  void _showSettingsDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('設定'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.bluetooth_searching),
              title: const Text('スキャン開始'),
              onTap: () {
                Navigator.of(context).pop();
                _startManualScan();
              },
            ),
            ListTile(
              leading: const Icon(Icons.info),
              title: const Text('ステータス'),
              subtitle: Text(_status),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('閉じる'),
          ),
        ],
      ),
    );
  }

  // Tinder風のボトムナビゲーションバー
  Widget _buildTinderBottomBar() {
    return Container(
      height: 80,
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildBottomNavItem(
            icon: Icons.local_fire_department,
            color: const Color(0xFFFF6B6B),
            isSelected: true,
            onTap: () {},
          ),
          _buildBottomNavItem(
            icon: Icons.star,
            color: Colors.blue,
            isSelected: false,
            onTap: () {},
          ),
          _buildBottomNavItem(
            icon: Icons.chat_bubble,
            color: Colors.green,
            isSelected: false,
            onTap: () => _showMatchHistory(),
          ),
          _buildBottomNavItem(
            icon: Icons.person,
            color: Colors.grey,
            isSelected: false,
            onTap: () {},
          ),
        ],
      ),
    );
  }

  Widget _buildBottomNavItem({
    required IconData icon,
    required Color color,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        child: Icon(
          icon,
          size: 28,
          color: isSelected ? color : Colors.grey[400],
        ),
      ),
    );
  }

  // マッチ履歴を表示
  void _showMatchHistory() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.8,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            // ハンドル
            Container(
              margin: const EdgeInsets.symmetric(vertical: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // タイトル
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'マッチ履歴',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            // リスト
            Expanded(child: _buildMatchHistoryTab()),
          ],
        ),
      ),
    );
  }

  // Tinder風のマッチ画面
  Widget _buildEventPage() {
    final event = _currentMatchEvent!;
    final deviceName = event['device_name'] as String;
    final macAddress = event['mac_address'] as String;
    
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 背景の花火エフェクト風
          Container(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment.center,
                colors: [
                  const Color(0xFFFF6B6B).withValues(alpha: 0.3),
                  Colors.black,
                ],
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                // 閉じるボタン
                Align(
                  alignment: Alignment.topRight,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: GestureDetector(
                      onTap: _resumeScanning,
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.5),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.close,
                          color: Colors.white,
                          size: 24,
                        ),
                      ),
                    ),
                  ),
                ),
                const Spacer(),
                // メイン画面
                Column(
                  children: [
                    // "IT'S A MATCH!" テキスト
                    const Text(
                      "IT'S A MATCH!",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 36,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 2,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      "あなたたちはお互いにLikeしました",
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 50),
                    // プロフィール画像を並べて表示
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // 自分のアバター
                        Container(
                          width: 140,
                          height: 140,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 4),
                          ),
                          child: ClipOval(
                            child: Container(
                              color: Colors.grey[300],
                              child: const Icon(
                                Icons.person,
                                size: 80,
                                color: Colors.grey,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 30),
                        // マッチした相手のアバター
                        Container(
                          width: 140,
                          height: 140,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 4),
                          ),
                          child: ClipOval(
                            child: _generateAvatar(macAddress, size: 140),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 30),
                    Text(
                      deviceName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                // ボタン
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 40),
                  child: Column(
                    children: [
                      // チャットボタン
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          onPressed: _startChat,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFFF6B6B),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(25),
                            ),
                            elevation: 0,
                          ),
                          child: const Text(
                            'SAY HELLO',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      // スキャンを続けるボタン
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: TextButton(
                          onPressed: _resumeScanning,
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(25),
                              side: const BorderSide(color: Colors.white, width: 1),
                            ),
                          ),
                          child: const Text(
                            'KEEP SWIPING',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ],
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
                  leading: _generateAvatar(event['mac_address'], size: 50),
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

  // 利用可能なアバター画像のリスト（assets/avatars内の実際のファイル）
  static const List<String> _avatarImages = [
    'assets/avatars/avatar1.png',
    'assets/avatars/avatar2.png',
    'assets/avatars/avatar3.png',
    'assets/avatars/avatar4.png',
    'assets/avatars/avatar5.png',
  ];

  // MACアドレスから一意の写真アバターを生成
  Widget _generateAvatar(String macAddress, {double size = 50}) {
    // 画像が存在しない場合のフォールバック用
    if (_avatarImages.isEmpty) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Colors.grey[300],
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Icon(
          Icons.person,
          color: Colors.grey[600],
          size: size * 0.6,
        ),
      );
    }
    
    // MACアドレスからハッシュ値を生成して画像を選択
    final hash = macAddress.hashCode.abs();
    final imageIndex = hash % _avatarImages.length;
    final imagePath = _avatarImages[imageIndex];
    
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipOval(
        child: Image.asset(
          imagePath,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            // 画像読み込み失敗時のフォールバック
            _logger.e("アバター画像読み込みエラー: $imagePath");
            _logger.e("エラー詳細: $error");
            _logger.e("スタックトレース: $stackTrace");
            return Container(
              width: size,
              height: size,
              color: Colors.grey[300],
              child: Icon(
                Icons.person,
                color: Colors.grey[600],
                size: size * 0.6,
              ),
            );
          },
        ),
      ),
    );
  }


  // Tinder風のスワイプエリア
  Widget _buildTinderSwipeArea() {
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

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
      child: Stack(
        children: [
          // 次のカード（背景）
          if (unprocessedDevices.length > 1)
            _buildTinderCard(unprocessedDevices[1], isBackground: true),
          // 現在のカード（前景）
          GestureDetector(
          onHorizontalDragStart: (details) {
            setState(() {
              _isDragging = true;
            });
          },
          onHorizontalDragUpdate: (details) {
            setState(() {
              _cardOffset = details.localPosition.dx - 200; // カードの中心からのオフセット
              _cardRotation = _cardOffset / 300; // 回転角度を計算
            });
          },
          onHorizontalDragEnd: (details) {
            const double threshold = 80.0; // スワイプ判定のしきい値
            
            if (_cardOffset > threshold) {
              // 右スワイプ（Like）
              _animateCardExit(true, currentDevice);
            } else if (_cardOffset < -threshold) {
              // 左スワイプ（Nope）
              _animateCardExit(false, currentDevice);
            } else {
              // スワイプが不十分な場合は元の位置に戻す
              _resetCardPosition();
            }
          },
            child: Transform.translate(
              offset: Offset(_cardOffset, 0),
              child: Transform.rotate(
                angle: _cardRotation * 0.05, // より自然な回転
                child: Stack(
                  children: [
                    _buildTinderCard(currentDevice),
                    // Like/Nopeオーバーレイ
                    if (_isDragging) _buildSwipeOverlay(),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Tinder風のカードを構築
  Widget _buildTinderCard(Map<String, dynamic> device, {bool isBackground = false}) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      margin: EdgeInsets.all(isBackground ? 8 : 0),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isBackground ? 0.1 : 0.2),
            blurRadius: isBackground ? 5 : 20,
            offset: Offset(0, isBackground ? 2 : 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 背景画像（アバター）
            _generateAvatar(device['mac_address'], size: double.infinity),
            // グラデーションオーバーレイ
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.7),
                  ],
                  stops: const [0.0, 0.6, 1.0],
                ),
              ),
            ),
            // 情報テキスト
            Positioned(
              left: 16,
              right: 16,
              bottom: 16,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // デバイス名と年齢（風）
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          device['device_name'],
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      Text(
                        '${(device['rssi'] as int).abs() ~/ 10}', // RSSIから仮の年齢を生成
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.w300,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  // RSSI情報
                  Row(
                    children: [
                      const Icon(
                        Icons.signal_cellular_alt,
                        color: Colors.white,
                        size: 16,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'RSSI: ${device['rssi']} dBm',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // スワイプオーバーレイ
  Widget _buildSwipeOverlay() {
    String text = '';
    Color color = Colors.transparent;
    double rotation = 0;
    
    if (_cardOffset > 50) {
      text = 'LIKE';
      color = Colors.green;
      rotation = -0.2;
    } else if (_cardOffset < -50) {
      text = 'NOPE';
      color = Colors.red;
      rotation = 0.2;
    }
    
    if (text.isEmpty) return const SizedBox.shrink();
    
    return Positioned.fill(
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: color,
            width: 4,
          ),
        ),
        child: Center(
          child: Transform.rotate(
            angle: rotation,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                border: Border.all(color: color, width: 4),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                text,
                style: TextStyle(
                  color: color,
                  fontSize: 48,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 4,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // Tinder風のアクションボタン
  Widget _buildTinderActionButtons() {
    final unprocessedDevices = _detectedDevices
        .where((device) => 
            !_likedDevices.contains(device['mac_address']) && 
            !_nopedDevices.contains(device['mac_address']))
        .toList();

    if (unprocessedDevices.isEmpty) {
      return const SizedBox(height: 80);
    }

    final currentDevice = unprocessedDevices[_currentDeviceIndex];

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // Rewind (未実装)
          _buildActionButton(
            icon: Icons.replay,
            color: Colors.amber,
            size: 50,
            onTap: () {},
          ),
          // Nope
          _buildActionButton(
            icon: Icons.close,
            color: Colors.red,
            size: 60,
            onTap: () => _nopeDevice(currentDevice),
          ),
          // Super Like (未実装)
          _buildActionButton(
            icon: Icons.star,
            color: Colors.blue,
            size: 50,
            onTap: () {},
          ),
          // Like
          _buildActionButton(
            icon: Icons.favorite,
            color: Colors.green,
            size: 60,
            onTap: () => _likeDevice(currentDevice),
          ),
          // Boost (未実装)
          _buildActionButton(
            icon: Icons.flash_on,
            color: Colors.purple,
            size: 50,
            onTap: () {},
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required Color color,
    required double size,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 10,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Icon(
          icon,
          color: color,
          size: size * 0.4,
        ),
      ),
    );
  }

  // カードの色を取得（スワイプ方向に応じて変化）
  Color _getCardColor() {
    if (!_isDragging) return Colors.white;
    
    if (_cardOffset > 50) {
      // 右スワイプ（Like）- 緑っぽく
      final opacity = (_cardOffset / 150).clamp(0.0, 0.3);
      return Color.lerp(Colors.white, Colors.green[100], opacity)!;
    } else if (_cardOffset < -50) {
      // 左スワイプ（Nope）- 赤っぽく
      final opacity = (-_cardOffset / 150).clamp(0.0, 0.3);
      return Color.lerp(Colors.white, Colors.red[100], opacity)!;
    }
    
    return Colors.white;
  }
  
  // カードのボーダーを取得（スワイプ方向に応じて変化）
  Border? _getCardBorder() {
    if (!_isDragging) return null;
    
    if (_cardOffset > 50) {
      // 右スワイプ（Like）- 緑のボーダー
      final opacity = (_cardOffset / 150).clamp(0.0, 1.0);
      return Border.all(
        color: Colors.green.withValues(alpha: opacity), 
        width: 3,
      );
    } else if (_cardOffset < -50) {
      // 左スワイプ（Nope）- 赤のボーダー
      final opacity = (-_cardOffset / 150).clamp(0.0, 1.0);
      return Border.all(
        color: Colors.red.withValues(alpha: opacity), 
        width: 3,
      );
    }
    
    return null;
  }
  
  // カードを元の位置に戻すアニメーション
  void _resetCardPosition() {
    setState(() {
      _cardOffset = 0.0;
      _cardRotation = 0.0;
      _isDragging = false;
    });
  }
  
  // カードの退場アニメーション
  void _animateCardExit(bool isLike, Map<String, dynamic> device) {
    setState(() {
      _cardOffset = isLike ? 400.0 : -400.0;
      _cardRotation = isLike ? 0.3 : -0.3;
    });
    
    // アニメーション完了後に実際の処理を実行
    Future.delayed(const Duration(milliseconds: 200), () {
      if (isLike) {
        _likeDevice(device);
      } else {
        _nopeDevice(device);
      }
      
      // カードをリセット
      _resetCardPosition();
    });
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
      
      // メッセージ数をカウント
      _incrementMessageCount();
      
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
  
  // メッセージ数をカウントして告白促進をチェック
  void _incrementMessageCount() {
    if (_currentChatRoomId == null) return;
    
    _messageCountPerRoom[_currentChatRoomId!] = 
        (_messageCountPerRoom[_currentChatRoomId!] ?? 0) + 1;
    
    final count = _messageCountPerRoom[_currentChatRoomId!]!;
    
    // 3通目のメッセージで告白促進を表示
    if (count == 3 && !_confessionPromptShown.contains(_currentChatRoomId!)) {
      _confessionPromptShown.add(_currentChatRoomId!);
      _showConfessionPrompt();
    }
  }
  
  // 告白促進ダイアログを表示
  void _showConfessionPrompt() {
    if (!mounted) return;
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        backgroundColor: Colors.pink[50],
        title: const Row(
          children: [
            Icon(Icons.favorite, color: Colors.pink, size: 28),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                '告白しろ！！',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.pink,
                ),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.pink[200]!, width: 2),
              ),
              child: Column(
                children: [
                  const Text(
                    '💕 恋のチャンス到来！ 💕',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.pink,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'やりとりが盛り上がってきましたね！\n今がチャンスです！\n\n勇気を出して気持ちを伝えてみませんか？',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey[700],
                      height: 1.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const Icon(Icons.lightbulb, color: Colors.amber, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '「いつもお話していて楽しいです！\nもしよろしければ...」',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              'まだ早い',
              style: TextStyle(color: Colors.grey[600]),
            ),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.of(context).pop();
              _insertConfessionMessage();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.pink,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(25),
              ),
            ),
            icon: const Icon(Icons.favorite, size: 18),
            label: const Text(
              '告白する！',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
  
  // 告白メッセージをテキストフィールドに挿入
  void _insertConfessionMessage() {
    final confessionMessages = [
      'いつもお話していて楽しいです！もしよろしければ、もっと親しくなりたいです💕',
      'あなたとのやりとりがとても楽しくて...気持ちを伝えたくて💖',
      'もしかして...私たち、相性いいかもしれませんね😊もっとお話したいです！',
      '勇気を出して言います！あなたともっと特別な関係になりたいです💝',
    ];
    
    final random = DateTime.now().millisecondsSinceEpoch % confessionMessages.length;
    _messageController.text = confessionMessages[random];
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
        title: Row(
          children: [
            _generateAvatar(_currentPartnerMac ?? '', size: 35),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _currentPartnerName ?? '',
                style: const TextStyle(fontSize: 18),
              ),
            ),
          ],
        ),
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