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
  List<ScanResult> scanResults = [];     // Advertiseを受信したデバイス（Peripheral機器）一覧
  BluetoothDevice? selectedDevice;       // 接続済みデバイス
  bool isScanning = false;               // スキャン状態のフラグ
  List<BluetoothService> services = [];  // 検出されたService一覧

  @override
  void initState() {
    super.initState();
    // Bluetoothの状態を監視
    FlutterBluePlus.adapterState.listen((BluetoothAdapterState state) {
      if (state == BluetoothAdapterState.on) {
        logger.i('Bluetoothがオンになりました');
      } else {
        logger.w('Bluetoothがオフです: $state');
      }
    });
  }

  // デバイスのスキャンを開始
  void startScan() async {
    setState(() {
      scanResults = [];
      isScanning = true;
    });

    try {
      // Peripheral機器からのAdvertise信号をスキャン
      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 15),
        androidUsesFineLocation: false,
      );

      // Advertise信号の受信をリアルタイムで監視
      FlutterBluePlus.scanResults.listen((results) {
        setState(() {
          scanResults = results;
        });
      });

      // スキャン完了を監視
      FlutterBluePlus.isScanning.listen((scanning) {
        setState(() {
          isScanning = scanning;
        });
      });
    } catch (e) {
      logger.e('スキャンエラー: $e');
    }
  }

  // デバイスに接続
  void connectToDevice(BluetoothDevice device) async {
    try {
      // GATT接続の確立
      await device.connect();
      setState(() {
        selectedDevice = device;
      });

      // GATT接続状態の監視
      device.connectionState.listen((BluetoothConnectionState state) {
        logger.i('接続状態: $state');
        if (state == BluetoothConnectionState.disconnected) {
          setState(() {
            selectedDevice = null;
            services = []; // 切断時にServiceをクリア
          });
        }
      });

      // Serviceの探索
      services = await device.discoverServices();
      setState(() {});
    } catch (e) {
      logger.e('接続エラー: $e');
    }
  }

  // デバイスから切断
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
            const SizedBox(height: 20),
            if (selectedDevice == null) ...[
              ElevatedButton(
                onPressed: isScanning ? null : startScan,
                child: Text(isScanning ? 'スキャン中...' : 'スキャン開始'),
              ),
              const SizedBox(height: 20),
              Expanded(
                child: ListView.builder(
                  itemCount: scanResults.length,
                  itemBuilder: (context, index) {
                    final result = scanResults[index];
                    return ListTile(
                      title: Text(result.device.platformName.isEmpty
                          ? 'Unknown Device'
                          : result.device.platformName),
                      subtitle: Text('RSSI: ${result.rssi}'),
                      onTap: () => connectToDevice(result.device),
                    );
                  },
                ),
              ),
            ] else ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('接続済みデバイス: ${selectedDevice!.platformName}'),
                  ElevatedButton(
                    onPressed: disconnectDevice,
                    child: const Text('切断'),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Expanded(
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
          ],
        ),
      ),
    );
  }
}
