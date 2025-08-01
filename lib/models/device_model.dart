// BLEデバイス関連のモデルクラス
class BLEDevice {
  final String macAddress;
  final String deviceName;
  final int rssi;
  final DateTime detectedAt;
  final bool isLiked;
  final bool isNoped;

  BLEDevice({
    required this.macAddress,
    required this.deviceName,
    required this.rssi,
    required this.detectedAt,
    this.isLiked = false,
    this.isNoped = false,
  });

  factory BLEDevice.fromJson(Map<String, dynamic> json) {
    return BLEDevice(
      macAddress: json['mac_address'] ?? '',
      deviceName: json['device_name'] ?? 'Unknown Device',
      rssi: json['rssi'] ?? -100,
      detectedAt: json['detected_at'] != null 
          ? DateTime.parse(json['detected_at']) 
          : DateTime.now(),
    );
  }
}

class MatchEvent {
  final String deviceName;
  final String macAddress;
  final int rssi;
  final DateTime matchedAt;
  final bool isSuperLike;

  MatchEvent({
    required this.deviceName,
    required this.macAddress,
    required this.rssi,
    required this.matchedAt,
    this.isSuperLike = false,
  });

  Map<String, dynamic> toJson() {
    return {
      'device_name': deviceName,
      'mac_address': macAddress,
      'rssi': rssi,
      'matched_at': matchedAt.toUtc().add(const Duration(hours: 9)),
      'is_super_like': isSuperLike,
    };
  }
}

class LocationScan {
  final double latitude;
  final double longitude;
  final double? accuracy;
  final List<String> macAddresses;
  final DateTime scannedAt;

  LocationScan({
    required this.latitude,
    required this.longitude,
    this.accuracy,
    required this.macAddresses,
    required this.scannedAt,
  });
}