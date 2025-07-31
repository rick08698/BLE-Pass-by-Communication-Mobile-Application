import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:logger/logger.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:permission_handler/permission_handler.dart';

final logger = Logger();

// ★ Supabaseを初期化
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ★ あなたのSupabaseプロジェクトのURLとANON KEYに書き換えてください
  await Supabase.initialize(
    url: 'https://pefwaiptgdqwefwljaks.supabase.co',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InBlZndhaXB0Z2Rxd2Vmd2xqYWtzIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTMxMTczNDEsImV4cCI6MjA2ODY5MzM0MX0.zTb6JKPL_bVN0ZTjPE1069g4cM9bo9DdpaGjYPNP9Js',
  );

  runApp(const MyApp());
}

// Supabaseクライアントへのショートカット
final supabase = Supabase.instance.client;

// ★ キャラクターのデータ構造を定義
class Character {
  final String macAddress;
  final String name;
  int interactionCount;

  Character({
    required this.macAddress,
    required this.name,
    this.interactionCount = 0,
  });
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BLE Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const MyHomePage(title: 'BLE 恋愛ゲーム'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});
  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  List<ScanResult> scanResults = [];
  bool isScanning = false;

  // ★ アプリ内でキャラクター情報を管理するリスト
  List<Character> characters = [];

  // ★ すれ違い判定用のRSSI閾値（この値より強い電波を「すれ違い」と判定）
  final int rssiThreshold = -70;

  // ★ 同じデバイスで連続カウントしないためのクールダウン管理
  final Map<String, DateTime> _cooldowns = {};
  final Duration _cooldownDuration = const Duration(minutes: 1); // 1分間のクールダウン

  @override
  void initState() {
    super.initState();
    // アプリ起動時にSupabaseからキャラクター情報を取得
    _fetchCharacters();
  }

  // Supabaseからキャラクターの情報を取得する
  Future<void> _fetchCharacters() async {
    try {
      final data = await supabase.from('characters').select();
      if (mounted && data.isNotEmpty) {
        setState(() {
          characters = data.map((item) => Character(
            macAddress: item['mac_address'],
            name: item['name'],
            interactionCount: item['interaction_count'],
          )).toList();
        });
      }
    } catch (e) {
      logger.e('キャラクター情報の取得エラー: $e');
    }
  }

void startScan() async {
    logger.i("権限リクエストを開始します...");

    // 【デバッグのため修正】最初に位置情報の権限を単独でリクエスト
    var locationStatus = await Permission.locationWhenInUse.request();
    logger.i("位置情報権限のステータス: $locationStatus");

    if (locationStatus != PermissionStatus.granted) {
      logger.w('位置情報の権限が許可されていません。');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('スキャンには位置情報の権限が必要です。設定アプリから許可してください。')),
      );
      return;
    }

    // 次にBluetoothスキャンの権限をリクエスト
    var bluetoothScanStatus = await Permission.bluetoothScan.request();
    logger.i("Bluetoothスキャン権限のステータス: $bluetoothScanStatus");

    if (bluetoothScanStatus != PermissionStatus.granted) {
      logger.w('Bluetoothスキャンの権限が許可されていません。');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bluetoothスキャンの権限が必要です。設定アプリから許可してください。')),
      );
      return;
    }

    // 最後にBluetooth接続の権限をリクエスト
    var bluetoothConnectStatus = await Permission.bluetoothConnect.request();
    logger.i("Bluetooth接続権限のステータス: $bluetoothConnectStatus");

    if (bluetoothConnectStatus != PermissionStatus.granted) {
      logger.w('Bluetooth接続の権限が許可されていません。');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bluetooth接続の権限が必要です。設定アプリから許可してください。')),
      );
      return;
    }

    logger.i("すべての権限が許可されました。スキャンを開始します。");

    setState(() {
      isScanning = true;
    });

    try {
      await FlutterBluePlus.startScan(androidUsesFineLocation: true);

      FlutterBluePlus.scanResults.listen((results) {
        if (!mounted) return;
        setState(() {
          scanResults = results;
        });
        _checkForInteraction(results);
      });
    } catch (e) {
      logger.e('スキャンエラー: $e');
    }
  }

  void stopScan() {
    FlutterBluePlus.stopScan();
    setState(() {
      isScanning = false;
    });
  }

  // ★ すれ違いを判定し、回数を更新するメソッド
  void _checkForInteraction(List<ScanResult> results) {
    for (final result in results) {
      // 電波強度が閾値より弱い場合はスキップ
      if (result.rssi < rssiThreshold) continue;

      final deviceAddress = result.device.remoteId.toString();

      // このデバイスがターゲットキャラクターか探す
      for (var chara in characters) {
        if (chara.macAddress == deviceAddress) {
          // クールダウン中かチェック
          final now = DateTime.now();
          if (_cooldowns.containsKey(deviceAddress) && now.difference(_cooldowns[deviceAddress]!) < _cooldownDuration) {
            continue; // まだクールダウン中なのでスキップ
          }
          
          // クールダウンを更新して、すれ違い回数を増やす
          _cooldowns[deviceAddress] = now;
          _incrementInteraction(chara);
          break; // 一致するキャラを見つけたらループを抜ける
        }
      }
    }
  }

  // ★ Supabaseの回数を更新し、アプリ内の表示も更新するメソッド
  Future<void> _incrementInteraction(Character character) async {
    try {
      final newCount = character.interactionCount + 1;

      // Supabaseのデータを更新
      await supabase
          .from('characters')
          .update({'interaction_count': newCount})
          .eq('mac_address', character.macAddress);

      // アプリ内の表示を更新
      if (mounted) {
        setState(() {
          character.interactionCount = newCount;
        });
      }

      // ユーザーに通知
      _showInteractionMessage(character);

    } catch (e) {
      logger.e('${character.name}とのすれ違い記録エラー: $e');
    }
  }

  void _showInteractionMessage(Character character) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('💖 ${character.name}とすれ違いました！'),
        backgroundColor: Colors.pinkAccent,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(widget.title),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                ElevatedButton(
                  onPressed: isScanning ? stopScan : startScan,
                  child: Text(isScanning ? 'スキャン停止' : 'すれ違い探しを開始'),
                ),
                const SizedBox(height: 20),
                const Text('💖 キャラクターとの親密度 💖', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          // キャラクターのすれ違い回数を表示するリスト
          SizedBox(
            height: 220,
            child: ListView.builder(
              itemCount: characters.length,
              itemBuilder: (context, index) {
                final chara = characters[index];
                return ListTile(
                  leading: const Icon(Icons.favorite, color: Colors.pink),
                  title: Text(chara.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                  trailing: Text('すれ違い回数: ${chara.interactionCount} 回', style: const TextStyle(fontSize: 16)),
                );
              },
            ),
          ),
          const Divider(),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('周辺のデバイス', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: scanResults.length,
              itemBuilder: (context, index) {
                final result = scanResults[index];
                final isTarget = characters.any((c) => c.macAddress == result.device.remoteId.toString());
                return ListTile(
                  title: Text(
                    result.device.platformName.isEmpty ? '(Unknown Device)' : result.device.platformName,
                    style: TextStyle(color: isTarget ? Colors.deepPurple : null, fontWeight: isTarget ? FontWeight.bold : null),
                  ),
                  subtitle: Text('RSSI: ${result.rssi}  |  ID: ${result.device.remoteId}'),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}