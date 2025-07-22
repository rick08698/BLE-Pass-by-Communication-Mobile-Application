import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:logger/logger.dart';

final logger = Logger();

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BLE Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const MyHomePage(title: 'BLE デモ'),
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
  BluetoothDevice? selectedDevice;
  bool isScanning = false;
  List<BluetoothService> services = [];

  // ★ 1. 探したいBLEタグのMACアドレスを4つリストで定義
  final List<String> targetTagAddresses = [
    "AA:11:BB:22:CC:33", // 1つ目のタグのアドレス
    "BB:22:CC:33:DD:44", // 2つ目のタグのアドレス
    "CC:33:DD:44:EE:55", // 3つ目のタグのアドレス
    "DD:44:EE:55:FF:66", // 4つ目のタグのアドレス
  ];

  // ★ 2. スキャン中に発見済みのタグを記録するためのSet
  final Set<String> _foundDevices = {};

  @override
  void initState() {
    super.initState();
    FlutterBluePlus.adapterState.listen((BluetoothAdapterState state) {
      if (state == BluetoothAdapterState.on) {
        logger.i('Bluetoothがオンになりました');
      } else {
        logger.w('Bluetoothがオフです: $state');
      }
    });
  }

  void startScan() async {
    // ★ 3. スキャン開始時に発見済みリストをクリア
    _foundDevices.clear();
    setState(() {
      scanResults = [];
      isScanning = true;
    });

    try {
      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 15),
        androidUsesFineLocation: false,
      );

      FlutterBluePlus.scanResults.listen((results) {
        setState(() {
          scanResults = results;
        });

        // ★ 4. スキャン結果をループし、ターゲットのタグを探す
        for (final result in results) {
          final deviceAddress = result.device.remoteId.toString();

          // ターゲットリストに含まれていて、まだ発見済みとして記録されていないかチェック
          if (targetTagAddresses.contains(deviceAddress) && !_foundDevices.contains(deviceAddress)) {
            // 発見済みとして記録
            _foundDevices.add(deviceAddress);
            // どのデバイスが見つかったかメッセージを表示
            _showHelloMessage(result.device);
          }
        }
      });

      FlutterBluePlus.isScanning.listen((scanning) {
        setState(() {
          isScanning = scanning;
        });
      });
    } catch (e) {
      logger.e('スキャンエラー: $e');
    }
  }

  void connectToDevice(BluetoothDevice device) async {
    try {
      await device.connect();
      setState(() {
        selectedDevice = device;
      });

      device.connectionState.listen((BluetoothConnectionState state) {
        logger.i('接続状態: $state');
        if (state == BluetoothConnectionState.disconnected) {
          setState(() {
            selectedDevice = null;
            services = [];
          });
        }
      });

      services = await device.discoverServices();
      setState(() {});
    } catch (e) {
      logger.e('接続エラー: $e');
    }
  }

  void disconnectDevice() async {
    if (selectedDevice != null) {
      try {
        await selectedDevice!.disconnect();
        setState(() {
          selectedDevice = null;
        });
      } catch (e) {
        logger.e('切断エラー: $e');
      }
    }
  }

  // ★ 5. メッセージ表示メソッドを修正し、どのデバイスか分かるようにする
  void _showHelloMessage(BluetoothDevice device) {
    if (!mounted) return;
    final deviceName = device.platformName.isEmpty ? device.remoteId.toString() : device.platformName;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('👋 ターゲットデバイスを検知しました！: $deviceName'),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 5),
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
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: <Widget>[
            ElevatedButton(
              onPressed: isScanning ? null : startScan,
              child: Text(isScanning ? 'スキャン中...' : 'スキャン開始'),
            ),
            const SizedBox(height: 10),
            if (selectedDevice != null) ...[
              const Divider(),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      '接続中: ${selectedDevice!.platformName}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  ElevatedButton(
                    onPressed: disconnectDevice,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red[300],
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('切断'),
                  ),
                ],
              ),
              SizedBox(
                height: 200,
                child: ListView.builder(
                  itemCount: services.length,
                  itemBuilder: (context, serviceIndex) {
                    final service = services[serviceIndex];
                    return ExpansionTile(
                      title: Text('Service: ${service.uuid}'),
                      children: service.characteristics.map((characteristic) {
                        return ListTile(
                          title: Text('Characteristic: ${characteristic.uuid}'),
                          subtitle: Text(
                              'Properties: ${characteristic.properties.toString()}'),
                          dense: true,
                        );
                      }).toList(),
                    );
                  },
                ),
              ),
            ],
            const Divider(),
            const Text('周辺のデバイス', style: TextStyle(fontWeight: FontWeight.bold)),
            Expanded(
              child: ListView.builder(
                itemCount: scanResults.length,
                itemBuilder: (context, index) {
                  final result = scanResults[index];
                  // ターゲットのタグをハイライト表示
                  final isTarget = targetTagAddresses.contains(result.device.remoteId.toString());
                  return ListTile(
                    title: Text(
                      result.device.platformName.isEmpty
                          ? '(Unknown Device)'
                          : result.device.platformName,
                      style: TextStyle(color: isTarget ? Colors.blue : null, fontWeight: isTarget ? FontWeight.bold : null),
                    ),
                    subtitle: Text('RSSI: ${result.rssi}  |  ID: ${result.device.remoteId}'),
                    onTap: () => connectToDevice(result.device),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}