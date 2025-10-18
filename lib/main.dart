import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:logger/logger.dart';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:video_player/video_player.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'services/audio_service.dart';
import 'services/video_service.dart';
import 'services/personality_service.dart';
import 'widgets/background_video_widget.dart';
import 'widgets/fullscreen_video_widget.dart';
import 'personality_selection_page.dart';
import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'dart:math' as Math;

// アプリ全体で参照する接続設定
class AppConfig {
  static String supabaseUrl = '';
  static String supabaseAnonKey = '';
  static String geminiApiKey = '';
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // .env を読み込み（プロジェクトルートの .env を pubspec.yaml で assets 登録済み）
  await dotenv.load(fileName: ".env");

  String _env(String key) {
    var v = (dotenv.env[key] ?? '').trim();
    if (v.length >= 2) {
      final q1 = v.codeUnitAt(0);
      final qn = v.codeUnitAt(v.length - 1);
      final isDoubleQuoted = q1 == 0x22 && qn == 0x22; // "
      final isSingleQuoted = q1 == 0x27 && qn == 0x27; // '
      if (isDoubleQuoted || isSingleQuoted) {
        v = v.substring(1, v.length - 1).trim();
      }
    }
    return v;
  }

  // ルーズな形式の .env を追加対応してパース（key=value / key: 'value' / key = 'value'）
  Future<Map<String, String>> _parseLooseEnv() async {
    try {
      final raw = await rootBundle.loadString('.env');
      final Map<String, String> out = {};
      for (final line in raw.split('\n')) {
        var l = line.trim();
        if (l.isEmpty) continue;
        if (l.startsWith('#') || l.startsWith('//')) continue;
        // key: 'value' or key = 'value' or key=value
        final sepIdx = l.indexOf(':');
        final eqIdx = l.indexOf('=');
        int idx;
        if (sepIdx == -1 && eqIdx == -1) continue;
        if (sepIdx == -1) {
          idx = eqIdx;
        } else if (eqIdx == -1) {
          idx = sepIdx;
        } else {
          idx = sepIdx < eqIdx ? sepIdx : eqIdx;
        }
        if (idx <= 0) continue;
        final key = l.substring(0, idx).trim();
        var val = l.substring(idx + 1).trim();
        if (val.endsWith(',')) val = val.substring(0, val.length - 1).trim();
        if ((val.startsWith("\"") && val.endsWith("\"")) || (val.startsWith("'") && val.endsWith("'"))) {
          val = val.substring(1, val.length - 1).trim();
        }
        if (key.isNotEmpty && val.isNotEmpty) out[key] = val;
      }
      return out;
    } catch (_) {
      return {};
    }
  }

  // Supabaseの初期化（.env の値を使用）
  var supabaseUrl = _env('SUPABASE_URL');
  var supabaseAnonKey = _env('SUPABASE_ANON_KEY');

  // .env が yaml/js 風の書式の場合: url: '...'/anonKey: '...' をパース
  if (!(supabaseUrl.startsWith('http://') || supabaseUrl.startsWith('https://')) || supabaseAnonKey.isEmpty) {
    final loose = await _parseLooseEnv();
    supabaseUrl = supabaseUrl.isNotEmpty ? supabaseUrl : (loose['SUPABASE_URL'] ?? loose['url'] ?? '');
    supabaseAnonKey = supabaseAnonKey.isNotEmpty ? supabaseAnonKey : (loose['SUPABASE_ANON_KEY'] ?? loose['anonKey'] ?? '');
    // Gemini key 対応（両形式）
    final gKey = (dotenv.env['GEMINI_API_KEY'] ?? '').trim().isNotEmpty
        ? (dotenv.env['GEMINI_API_KEY'] ?? '')
        : (loose['GEMINI_API_KEY'] ?? loose['_geminiApiKey'] ?? '');
    if (gKey.isNotEmpty) AppConfig.geminiApiKey = gKey.trim();
  }

  // 共有設定に保存（他箇所の検証用）
  AppConfig.supabaseUrl = supabaseUrl;
  AppConfig.supabaseAnonKey = supabaseAnonKey;
  if (supabaseUrl.isEmpty || !supabaseUrl.startsWith('http')) {
    // 起動時に設定不備をログに出す（UIではチャット開始時にSnackBarで通知されます）
    // ignore: avoid_print
    print('[Config] SUPABASE_URL が未設定または不正です: "$supabaseUrl"');
  }
  if (supabaseAnonKey.isEmpty) {
    // ignore: avoid_print
    print('[Config] SUPABASE_ANON_KEY が未設定です');
  }
  await Supabase.initialize(
    url: supabaseUrl.isNotEmpty ? supabaseUrl : 'YOUR_SUPABASE_URL_HERE',
    anonKey: supabaseAnonKey.isNotEmpty ? supabaseAnonKey : 'YOUR_SUPABASE_ANON_KEY_HERE',
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
class TitlePage extends StatefulWidget {
  const TitlePage({super.key});

  @override
  State<TitlePage> createState() => _TitlePageState();
}

class _TitlePageState extends State<TitlePage> {
  String _selectedLanguage = 'ja'; // デフォルトは日本語

  // 多言語対応用のテキスト定義（タイトル画面用）
  Map<String, Map<String, String>> get _titleTexts => {
    'ja': {
      'app_title': 'Bluetooth Love',
      'app_subtitle': '~運命の出会いはBluetooth接続から~',
      'start_button': 'はじめる',
      'language_selection': '言語選択',
      'description': 'BLEデバイスを検索して、運命の人を見つけよう！',
      'feature1': '📱 BLEスキャン機能',
      'feature2': '💕 スワイプマッチング',
      'feature3': '💬 チャット機能',
    },
    'en': {
      'app_title': 'Bluetooth Love',
      'app_subtitle': '~romance begins with a chance encounter~',
      'start_button': 'Start',
      'language_selection': 'Language',
      'description': 'Scan BLE devices and find your soulmate!',
      'feature1': '📱 BLE Scanning',
      'feature2': '💕 Swipe Matching',
      'feature3': '💬 Chat Feature',
    },
  };

  String _getTitleText(String key) {
    return _titleTexts[_selectedLanguage]?[key] ?? _titleTexts['ja']?[key] ?? key;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: BackgroundVideoWidget(
        videoPath: 'assets/videos/title_background.mp4',
        shouldPlay: true, // タイトル画面では常に再生
        opacity: 0.4, // 背景動画の透明度
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.pink[100]!.withOpacity(0.3),
                Colors.pink[50]!.withOpacity(0.3),
                Colors.white.withOpacity(0.5),
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
                
                Text(
                  _getTitleText('app_title'),
                  style: const TextStyle(
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
                  _getTitleText('app_subtitle'),
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
                        _getTitleText('description'),
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey[800],
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      Column(
                        children: [
                          Text(_getTitleText('feature1'), style: TextStyle(fontSize: 14, color: Colors.grey[600])),
                          const SizedBox(height: 4),
                          Text(_getTitleText('feature2'), style: TextStyle(fontSize: 14, color: Colors.grey[600])),
                          const SizedBox(height: 4),
                          Text(_getTitleText('feature3'), style: TextStyle(fontSize: 14, color: Colors.grey[600])),
                        ],
                      ),
                    ],
                  ),
                ),
                
                const SizedBox(height: 20),
                
                // 言語選択ボタン
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      _getTitleText('language_selection'),
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[600],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(width: 8),
                    DropdownButton<String>(
                      value: _selectedLanguage,
                      underline: Container(),
                      items: [
                        DropdownMenuItem(value: 'ja', child: Text(_getTitleText('japanese'))),
                        DropdownMenuItem(value: 'en', child: Text(_getTitleText('english'))),
                      ],
                      onChanged: (String? newValue) {
                        if (newValue != null) {
                          setState(() {
                            _selectedLanguage = newValue;
                          });
                        }
                      },
                    ),
                  ],
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
                          builder: (context) => const PersonalitySelectionPage(),
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
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.play_arrow, size: 28),
                        const SizedBox(width: 8),
                        Text(
                          _getTitleText('start_button'),
                          style: const TextStyle(
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
      ),
    );
  }
}

class BleTestPage extends StatefulWidget {
  final String language;
  
  const BleTestPage({super.key, required this.language});

  @override
  State<BleTestPage> createState() => _BleTestPageState();
}

class _BleTestPageState extends State<BleTestPage> with SingleTickerProviderStateMixin {
  String _status = "";
  List<String> _foundDevices = [];
  bool _isScanning = false;
  bool _autoScanEnabled = true; // 自動継続スキャンの設定（デフォルトON）
  Timer? _scanTimer;
  Timer? _autoScanTimer; // 自動継続用タイマー
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
  
  // 向こうからのいいね機能用の変数
  final List<Map<String, dynamic>> _receivedLikes = []; // 受信したいいねのリスト
  int _unreadLikesCount = 0; // 未読いいね数
  
  final Map<String, DateTime> _deviceLastDetected = {}; // デバイスごとの最終検出時刻
  
  // スワイプマッチング用の変数
  bool _isInSwipeMode = true; // スワイプモード中かどうか（デフォルトでスワイプモード）
  int _currentDeviceIndex = 0; // 現在表示しているデバイスのインデックス
  int _totalDetectedDevices = 0; // 総検出デバイス数
  
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
  final ScrollController _chatScrollController = ScrollController(); // チャット用スクロールコントローラー
  final List<Map<String, dynamic>> _messages = []; // チャットメッセージのリスト
  Timer? _messageRefreshTimer; // メッセージ更新用タイマー
  
  // 固定の自分のMACアドレス（アプリ起動時に一度だけ生成）
  late final String _myMac;
  static const String _myName = "あなた";
  
  // プロフィール情報
  String _userProfileName = "あなた";
  int _userAge = 20;
  String _userBio = "よろしくお願いします！";
  
  // 親密度システム用の変数
  final Map<String, int> _intimacyLevels = {}; // チャットルームごとの親密度レベル
  final Map<String, int> _messageCountPerRoom = {}; // チャットルームごとのメッセージ数（統計用）
  
  // 位置情報分析用の変数
  Position? _currentPosition; // 現在の位置情報
  final List<Map<String, dynamic>> _locationScans = []; // 位置情報付きスキャンデータ
  
  // 音声再生用の変数
  final AudioPlayer _audioPlayer = AudioPlayer();
  final AudioService _audioService = AudioService();
  final VideoService _videoService = VideoService();
  
  // 言語設定用の変数
  String _currentLanguage = 'ja'; // デフォルトは日本語

  // 多言語対応用のテキスト定義
  Map<String, Map<String, String>> get _texts => {
    'ja': {
      'app_title': 'Bluetooth Love',
      'app_subtitle': '~運命の出会いはBluetooth接続から~',
      'start_button': 'スタート',
      'language_selection': '言語選択',
      'select_language': '言語を選択してください',
      'japanese': '日本語',
      'english': 'English',
      'status_preparing': '準備中...',
      'status_scanning': 'スキャン中...',
      'status_location_getting': '位置情報取得中...',
      'scanning': 'スキャン中...',
      'scan_start': 'スキャン開始',
      'scan_complete': 'スキャン完了',
      'device_detected': '件検出',
      're_scan': '再スキャンまたはスワイプしてください',
      'profile': 'プロフィール',
      'profile_edit': 'プロフィール編集',
      'name': '名前',
      'name_hint': '名前を入力してください',
      'age': '年齢',
      'age_hint': '年齢を入力してください',
      'bio': '自己紹介',
      'bio_hint': '自己紹介を入力してください',
      'save': '保存',
      'profile_updated': 'プロフィールを更新しました！',
      'match_history': 'マッチ履歴',
      'location_analysis': '位置情報分析',
      'no_location': '位置情報が取得できていません。スキャンを実行してください。',
      'analyzing_location': '位置情報を分析中...',
      'no_frequent_devices': 'この場所では常連デバイスが見つかりませんでした',
      'scan_same_location': '同じ場所で複数回スキャンしてください',
      'analysis_target_location': '📍 分析対象位置',
      'latitude': '緯度',
      'longitude': '経度',
      'accuracy': '精度',
      'frequent_devices': '常連デバイス',
      'detection_count': '検知回数',
      'first_seen': '初回',
      'last_seen': '最新',
      'times': '回',
      'close': '閉じる',
      'permission_required': '権限が必要です - 設定から許可してください',
      'permission_checking': '権限を確認中...',
      'permission_insufficient': '権限が不足しています',
      'settings': '設定',
      'language_settings': '言語設定',
      'match_time': 'マッチ時刻',
      'no_matches': 'まだマッチングがありません',
      'match_info': '同じBLEデバイスを5回検知するとマッチングします',
      'detection_time': '検出時刻',
      'no_devices_detected': 'まだデバイスが検出されていません',
      'searching_devices': 'BLEデバイスを検索中...',
      'swipe_instruction': '右スワイプでLike、左スワイプでNopeできます',
      'received_likes': 'もらったいいね',
      'no_received_likes': 'まだいいねが届いていません',
      'received_likes_description': '位置分析で検出されたデバイスから運命のいいねが届くかも...',
      'destiny_message': '私たち、運命なのかも...',
      'destiny_subtitle': '同じ場所で何度も検出されています',
      'like_back': 'いいね返し',
      'pass': 'パス',
      'mutual_match': '両想いです！',
      'chat_start': 'チャットを始める',
      'likes_count': '件のいいね',
      'no_match_message': '残念...今回はマッチしませんでした',
      'no_match_super_like': '残念...今回はマッチしませんでした💦',
      'no_match_regular': 'マッチしませんでした😅 また挑戦してください！',
      'item_description_title': 'アイテムの説明',
      'topic_items_title': '話題の項目',
      'try_again': 'また挑戦する',
      'better_luck_next_time': '次回はきっとうまくいきます！',
      'item_usage_guide': 'アイテムの使用方法',
      'conversation_starters': 'おすすめの話題',
      'auto_scan': '自動スキャン',
      'auto_scan_on': '自動スキャン ON',
      'auto_scan_off': '自動スキャン OFF',
      'next_scan_in': '次のスキャンまであと',
      'seconds': '秒',
    },
    'en': {
      'app_title': 'Bluetooth Love',
      'app_subtitle': '~romance begins with a chance encounter~',
      'start_button': 'Start',
      'language_selection': 'Language Selection',
      'select_language': 'Please select your language',
      'japanese': '日本語',
      'english': 'English',
      'status_preparing': 'Preparing...',
      'status_scanning': 'Scanning...',
      'status_location_getting': 'Getting location...',
      'scanning': 'Scanning...',
      'scan_start': 'Start Scan',
      'scan_complete': 'Scan Complete',
      'device_detected': ' devices detected',
      're_scan': 'Please re-scan or swipe',
      'profile': 'Profile',
      'profile_edit': 'Edit Profile',
      'name': 'Name',
      'name_hint': 'Enter your name',
      'age': 'Age',
      'age_hint': 'Enter your age',
      'bio': 'Bio',
      'bio_hint': 'Enter your bio',
      'save': 'Save',
      'profile_updated': 'Profile updated!',
      'match_history': 'Match History',
      'location_analysis': 'Location Analysis',
      'no_location': 'Location not available. Please run a scan.',
      'analyzing_location': 'Analyzing location...',
      'no_frequent_devices': 'No frequent devices found at this location',
      'scan_same_location': 'Please scan multiple times at the same location',
      'analysis_target_location': '📍 Analysis Target Location',
      'latitude': 'Latitude',
      'longitude': 'Longitude',
      'accuracy': 'Accuracy',
      'frequent_devices': 'Frequent Devices',
      'detection_count': 'Detection Count',
      'first_seen': 'First Seen',
      'last_seen': 'Last Seen',
      'times': ' times',
      'close': 'Close',
      'permission_required': 'Permissions required - Please allow in settings',
      'permission_checking': 'Checking permissions...',
      'permission_insufficient': 'Insufficient permissions',
      'settings': 'Settings',
      'language_settings': 'Language Settings',
      'match_time': 'Match Time',
      'no_matches': 'No matches yet',
      'match_info': 'You need to detect the same BLE device 5 times to match',
      'detection_time': 'Detection Time',
      'no_devices_detected': 'No devices detected yet',
      'searching_devices': 'Searching for BLE devices...',
      'swipe_instruction': 'Swipe right for Like, left for Nope',
      'received_likes': 'Received Likes',
      'no_received_likes': 'No likes received yet',
      'received_likes_description': 'Destiny likes from location analysis may arrive...',
      'destiny_message': 'We might be destined...',
      'destiny_subtitle': 'Detected multiple times at the same location',
      'like_back': 'Like Back',
      'pass': 'Pass',
      'mutual_match': 'It\'s a match!',
      'chat_start': 'Start Chat',
      'likes_count': ' likes',
      'no_match_message': 'Sorry... No match this time',
      'no_match_super_like': 'Sorry... No match this time💦',
      'no_match_regular': 'No match😅 Please try again!',
      'item_description_title': 'Item Description',
      'topic_items_title': 'Conversation Topics',
      'try_again': 'Try Again',
      'better_luck_next_time': 'Better luck next time!',
      'item_usage_guide': 'How to Use Items',
      'conversation_starters': 'Conversation Starters',
      'auto_scan': 'Auto Scan',
      'auto_scan_on': 'Auto Scan ON',
      'auto_scan_off': 'Auto Scan OFF',
      'next_scan_in': 'Next scan in',
      'seconds': 'seconds',
      'price': 'Price',
      'points': 'points',
      'owned_count': 'Owned',
      'items': ' items',
      'purchase': 'Purchase',
      'match_success': 'Match Success!',
      'device_name': 'Device Name',
      'encountered_5_times': 'You have encountered this device 5 times or more!',
      'nearby_possibility': 'They might be nearby.',
      'analysis_error': 'Analysis Error',
      'chat_start_failed': 'Failed to start chat',
      'message_send_failed': 'Failed to send message',
      'fight_on': 'Fight on!',
      'no_items_owned': 'No items owned',
      'start_chat': 'Start Chat',
      'items_list': 'Items List',
      'send_gift': 'Send Gift',
      'scan_status': 'Status',
    },
  };

  String _getText(String key) {
    // 基本的なUI要素のみ英語優先、その他は言語設定に従う
    const englishPriorityKeys = {
      'scan_button', 'stop_scan', 'like_button', 'nope_button', 'super_like_button',
      'chat_button', 'back_button', 'send_button', 'confession_button',
      'item_description_title', 'topic_items_title', 'conversation_starters',
      'auto_scan', 'auto_scan_on', 'auto_scan_off', 'fight_on',
      'no_items_owned', 'start_chat', 'items_list', 'send_gift', 'scan_status'
    };
    
    if (englishPriorityKeys.contains(key)) {
      return _texts['en']?[key] ?? _texts['ja']?[key] ?? key;
    } else {
      return _texts[_currentLanguage]?[key] ?? _texts['ja']?[key] ?? key;
    }
  }

  // アイテム名を取得（多言語対応）
  String _getItemName(String itemId) {
    final item = _itemDefinitions[itemId];
    if (item == null) return itemId;
    
    final nameMap = item['name'];
    if (nameMap is Map<String, String>) {
      return nameMap[_currentLanguage] ?? nameMap['ja'] ?? itemId;
    } else if (nameMap is String) {
      return nameMap;
    }
    return itemId;
  }

  // アイテム説明を取得（多言語対応）
  String _getItemDescription(String itemId) {
    final item = _itemDefinitions[itemId];
    if (item == null) return '';
    
    final descriptionMap = item['description'];
    if (descriptionMap is Map<String, String>) {
      return descriptionMap[_currentLanguage] ?? descriptionMap['ja'] ?? '';
    } else if (descriptionMap is String) {
      return descriptionMap;
    }
    return '';
  }
  
  // 告白イベント用の変数
  bool _isInConfessionEvent = false; // 告白イベント中かどうか
  String? _confessionResult; // 告白の結果（"yes" または "no"）
  bool? _confessionSuccess; // 告白の成功/失敗結果をキャッシュ
  late AnimationController _rouletteController; // ルーレットアニメーション用
  late Animation<double> _rouletteAnimation;
  
  // スワイプ機能強化用の変数
  Map<String, dynamic>? _lastNopedDevice; // 最後にNopeしたデバイス（戻る機能用）
  final Map<String, int> _deviceIntimacyBonus = {}; // デバイスごとの親密度ボーナス
  final Set<String> _blockedUsers = {}; // ブロックされたユーザー（告白失敗時）
  
  // アイテムシステム用の変数
  int _userPoints = 200; // ユーザーのポイント（初期値200、アイテム価格を考慮して増加）
  final Map<String, int> _ownedItems = {}; // 所有アイテム
  
  // AI チャット機能用の変数
  // .env の GEMINI_API_KEY または AppConfig.geminiApiKey を使用
  static String get _geminiApiKey {
    if (AppConfig.geminiApiKey.isNotEmpty) return AppConfig.geminiApiKey;
    var v = (dotenv.env['GEMINI_API_KEY'] ?? '').trim();
    if (v.length >= 2) {
      if ((v.startsWith("\"") && v.endsWith("\"")) || (v.startsWith("'") && v.endsWith("'"))) {
        v = v.substring(1, v.length - 1).trim();
      }
    }
    return v.isNotEmpty ? v : 'YOUR_GEMINI_API_KEY_HERE';
  }
  static const String _geminiApiUrl = 'https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash-latest:generateContent';
  final Map<String, List<Map<String, String>>> _conversationHistory = {}; // チャットルームごとの会話履歴
  
  // 話題選択用のユーザー定型文（多言語対応）
  static const Map<String, Map<String, String>> _topicUserMessages = {
    'weather': {
      'ja': '今日はいい天気ですね！',
      'en': 'What nice weather we\'re having today!',
    },
    'hobbies': {
      'ja': '何か趣味とかありますか？',
      'en': 'Do you have any hobbies?',
    },
    'food': {
      'ja': '美味しいお店とか知ってますか？',
      'en': 'Do you know any good restaurants?',
    },
    'future': {
      'ja': '将来の夢とかありますか？',
      'en': 'Do you have any dreams for the future?',
    },
    'memories': {
      'ja': '何か楽しい思い出ありますか？',
      'en': 'Do you have any fond memories?',
    },
  };

  // 話題選択用の事前準備済み返答パターン（多言語対応）
  static const Map<String, Map<String, Map<String, List<String>>>> _topicResponses = {
    'weather': {
      'ja': {
        'gentle': [
          'とても良いお天気ですね😊',
          '気持ちのいい日ですね✨',
          'お散歩日和ですね🌸'
        ],
        'cool': [
          'そうですね😎',
          'まあまあの天気だね👍',
          '悪くない天気だな🤔'
        ],
        'cute': [
          'わーい！いいお天気〜🥰',
          'お日様が気持ちいいね☀️',
          'きれいな空だね〜💕'
        ],
        'aggressive': [
          'チッ、天気の話かよ💢 どうでもいいだろそんなもん',
          'うぜぇな...外なんか出たくねーよ😠',
          '天気がいい？知るかボケ💢 ダルいんだよ'
        ],
        'seductive': [
          'あらぁ〜♡ いい天気だと気分も高揚しちゃうわね😘',
          'こんな日は...どこか二人きりでお散歩したいわ💋',
          'お日様のように...私も熱くなっちゃう♡🔥'
        ],
        'cheerful': [
          'やったー！最高の天気だね〜😆',
          'こんな日は外で遊びたくなる🎉',
          'テンション上がる天気だ〜✨'
        ],
        'shy': [
          'あ...はい、いい天気ですね💦',
          'そうですね...お天気良くて😳',
          'うん...きれいな空だね...☺️'
        ],
        'mysterious': [
          'フフ...天気も運命ですね🌙',
          '空が何かを語りかけているような...✨',
          '今日は特別な日になりそう...🔮'
        ],
        'energetic': [
          'おー！最高の天気だぜ💪',
          'こんな日は体を動かしたくなる🔥',
          'パワーがみなぎってくるな⚡'
        ],
        'intellectual': [
          '気象データによると晴天確率が高いですね📚',
          '統計的に見ても良好な天候です🤓',
          '科学的に分析すると最適な気候条件ですね💭'
        ],
      },
      'en': {
        'gentle': [
          'What a beautiful day😊',
          'It\'s such lovely weather✨',
          'Perfect day for a walk🌸'
        ],
        'cool': [
          'Yeah, not bad😎',
          'Decent weather👍',
          'It\'s alright🤔'
        ],
        'cute': [
          'Yay! Such nice weather🥰',
          'The sunshine feels so good☀️',
          'What a pretty sky💕'
        ],
        'aggressive': [
          'Tch, talking about weather💢 Who cares about that crap',
          'Annoying... don\'t wanna go outside😠',
          'Good weather? I don\'t give a damn💢'
        ],
        'seductive': [
          'Oh my♡ Nice weather gets me excited😘',
          'On days like this... I want to take a romantic walk💋',
          'Like the sun... I\'m getting hot too♡🔥'
        ],
        'cheerful': [
          'Awesome! Perfect weather😆',
          'Days like this make me want to play outside🎉',
          'This weather is so energizing✨'
        ],
        'shy': [
          'Ah... yes, nice weather💦',
          'Yeah... the weather is good😳',
          'Um... pretty sky...☺️'
        ],
        'mysterious': [
          'Hmm... weather is destiny too🌙',
          'The sky seems to be telling us something...✨',
          'Today feels like a special day...🔮'
        ],
        'energetic': [
          'Yeah! Awesome weather💪',
          'Days like this make me want to move🔥',
          'I can feel the power surging⚡'
        ],
        'intellectual': [
          'According to meteorological data, high probability of clear skies📚',
          'Statistically speaking, excellent weather conditions🤓',
          'Scientifically analyzed, optimal climate conditions💭'
        ],
      },
    },
    'hobbies': {
      'ja': {
        'gentle': [
          '読書が好きです😊 あなたはどんな本が好きですか？',
          '散歩をするのが趣味です✨ 自然を見ているとほっとします',
          '料理を作るのが楽しいです🌸 今度何か作ってあげますね'
        ],
        'cool': [
          '特に決まった趣味はないな😎',
          'まあ、映画でも見るかな👍',
          '音楽を聞くくらいだね🤔'
        ],
        'cute': [
          'わーい！手芸が大好きなの🥰',
          'お菓子作りが趣味だよ〜☀️',
          '可愛いものを集めるのが好き💕'
        ],
        'aggressive': [
          '趣味？酒とタバコに決まってんだろ💢 他に何があんだよ',
          'チッ、趣味なんてダルいもんねーよ😤',
          'うるせぇな...人にもよるだろうが💢'
        ],
        'seductive': [
          'あらぁ〜♡ 私の趣味は...大人の楽しみよ😘💋',
          'うふふ♡ 夜の趣味なら色々あるわ🔥',
          '趣味って言っていいのかしら...💕 もっと刺激的なことが好きなの♡'
        ],
        'cheerful': [
          'スポーツが大好き〜😆 一緒に運動しない？',
          'ダンスが趣味なの🎉 楽しいよ〜',
          'カラオケで歌うのが最高✨'
        ],
        'shy': [
          'あ...読書が好きです💦',
          'そうですね...映画を見るくらい😳',
          'うん...静かな趣味が好き...☺️'
        ],
        'mysterious': [
          'フフ...秘密の趣味があります🌙',
          '占いや神秘的なことに興味が...✨',
          '夜空を眺めるのが好きですね🔮'
        ],
        'energetic': [
          'おー！筋トレが趣味だぜ💪',
          'ロッククライミングとかやってる🔥',
          'アウトドア全般が大好きだ⚡'
        ],
        'intellectual': [
          '学術研究が私の趣味ですね📚',
          '論文を読むのが楽しいです🤓',
          '知識を深めることに情熱を注いでいます💭'
        ]
      },
      'en': {
        'gentle': [
          'I love reading😊 What kind of books do you like?',
          'Walking is my hobby✨ Nature makes me feel peaceful',
          'I enjoy cooking🌸 I\'ll make something for you sometime'
        ],
        'cool': [
          'Don\'t really have specific hobbies😎',
          'Maybe watch movies sometimes👍',
          'Listen to music, I guess🤔'
        ],
        'cute': [
          'Yay! I love crafts🥰',
          'Baking is my hobby☀️',
          'I like collecting cute things💕'
        ],
        'aggressive': [
          'Hobbies? Drinking and smoking, obviously💢 What else is there',
          'Tch, hobbies are such a pain😤',
          'Annoying... depends on the person💢'
        ],
        'seductive': [
          'Oh my♡ My hobbies are... adult pleasures😘💋',
          'Hehe♡ I have various nighttime hobbies🔥',
          'Can I call it a hobby...💕 I prefer more exciting things♡'
        ],
        'cheerful': [
          'I love sports😆 Want to exercise together?',
          'Dancing is my hobby🎉 It\'s so fun',
          'Singing karaoke is the best✨'
        ],
        'shy': [
          'Ah... I like reading💦',
          'Well... watching movies mostly😳',
          'Um... I prefer quiet hobbies...☺️'
        ],
        'mysterious': [
          'Hmm... I have secret hobbies🌙',
          'I\'m interested in fortune telling and mystical things...✨',
          'I like gazing at the night sky🔮'
        ],
        'energetic': [
          'Yeah! Weight training is my hobby💪',
          'I do rock climbing and stuff🔥',
          'Love all outdoor activities⚡'
        ],
        'intellectual': [
          'Academic research is my hobby📚',
          'I enjoy reading papers🤓',
          'I\'m passionate about deepening knowledge💭'
        ]
      }
    },
    'food': {
      'ja': {
        'gentle': [
          '美味しいお店、知っていますよ😊 今度一緒に行きませんか？',
          '手作り料理が一番ですね✨ 心を込めて作ります',
          'みんなで食べる食事が幸せです🌸'
        ],
        'cool': [
          'まあ、それなりに知ってるかな😎',
          '特にこだわりはないね👍',
          '食べられればいいよ🤔'
        ],
        'cute': [
          'わーい！スイーツが大好き🥰',
          '可愛いカフェを知ってるよ☀️',
          '美味しいものって幸せだよね💕'
        ],
        'aggressive': [
          '美味い店？知らねーよ💢 コンビニ弁当で十分だろ',
          'チッ、グルメ気取りかよ😠 酒のつまみがあればいいんだよ',
          'うぜぇ...飯なんて腹に入ればなんでもいいだろ💢'
        ],
        'seductive': [
          'あらぁ〜♡ 美味しいものは...夜のお楽しみの後がいいわね😘',
          'うふふ♡ 精力のつく料理を知ってるの💋 今度作ってあげる🔥',
          '食事も大事だけど...もっと大事なことがあるでしょう？♡💕'
        ],
        'cheerful': [
          '美味しいお店いっぱい知ってる〜😆',
          'みんなでワイワイ食べるのが好き🎉',
          '食べることって最高だよね✨'
        ],
        'shy': [
          'あ...いくつか知ってます💦',
          'そうですね...美味しいお店😳',
          'うん...一緒に食べられたら...☺️'
        ],
        'mysterious': [
          'フフ...秘密のお店を知っています🌙',
          '深夜にひっそりと営業している店が...✨',
          '食事にも運命があるのです🔮'
        ],
        'energetic': [
          'おー！美味い店なら任せろ💪',
          'がっつり食べられる店が最高だ🔥',
          '食べて力をつけないとな⚡'
        ],
        'intellectual': [
          '栄養学的に優れた食事を重視します📚',
          '食文化の研究も興味深いですね🤓',
          '科学的に分析された料理法が好みです💭'
        ]
      },
      'en': {
        'gentle': [
          'I know some nice places😊 Would you like to go together?',
          'Homemade meals are the best✨ I cook with love',
          'Eating together makes me happy🌸'
        ],
        'cool': [
          'Yeah, I know a few decent places😎',
          'Don\'t really have preferences👍',
          'Food is food🤔'
        ],
        'cute': [
          'Yay! I love sweets🥰',
          'I know cute cafes☀️',
          'Yummy food makes me happy💕'
        ],
        'aggressive': [
          'Good restaurants? I don\'t know💢 Convenience store food is fine',
          'Tch, acting like a gourmet😠 Just need something with alcohol',
          'Annoying... food just needs to fill your stomach💢'
        ],
        'seductive': [
          'Oh my♡ Good food is... best after nighttime fun😘',
          'Hehe♡ I know stamina-boosting dishes💋 I\'ll cook for you🔥',
          'Food is important but... there are more important things♡💕'
        ],
        'cheerful': [
          'I know tons of delicious places😆',
          'I love eating with everyone🎉',
          'Eating is the best thing ever✨'
        ],
        'shy': [
          'Ah... I know a few places💦',
          'Well... some good restaurants😳',
          'Um... it would be nice to eat together...☺️'
        ],
        'mysterious': [
          'Hmm... I know secret places🌙',
          'There are hidden restaurants that open late at night...✨',
          'Even meals have destiny🔮'
        ],
        'energetic': [
          'Yeah! Leave the good restaurants to me💪',
          'Places with hearty meals are the best🔥',
          'Gotta eat to stay strong⚡'
        ],
        'intellectual': [
          'I prefer nutritionally excellent meals📚',
          'Food culture research is fascinating🤓',
          'I prefer scientifically analyzed cooking methods💭'
        ]
      }
    },
    'future': {
      'ja': {
        'gentle': [
          '将来は平和で温かい家庭を築きたいです😊',
          'みんなが笑顔でいられる世界になったらいいですね✨',
          'あなたと一緒に歩んでいけたら幸せです🌸'
        ],
        'cool': [
          '特に決まった夢はないな😎',
          'まあ、その時その時で考える👍',
          '流れに任せるタイプかな🤔'
        ],
        'cute': [
          'わーい！素敵な未来になりそう🥰',
          '夢がいっぱいあるの☀️',
          '幸せな毎日が続きますように💕'
        ],
        'aggressive': [
          '将来？知るかよ💢 今日を生きるので精一杯だろうが',
          'チッ、夢なんて持ってどうすんだよ😤 現実見ろよ',
          'うるせぇな...先のことなんてわかるわけねーだろ💢'
        ],
        'seductive': [
          'あらぁ〜♡ 将来は...もっと魅力的な女性になりたいわ😘',
          'うふふ♡ 夢は秘密よ💋 でも...あなたと一緒なら🔥',
          '将来のことより...今この瞬間が大切よね♡💕'
        ],
        'cheerful': [
          '未来は明るいよ〜😆',
          'やりたいことがいっぱいある🎉',
          '毎日が楽しみで仕方ない✨'
        ],
        'shy': [
          'あ...将来のことはまだ💦',
          'そうですね...考え中です😳',
          'うん...一緒にいられたら...☺️'
        ],
        'mysterious': [
          'フフ...運命が導いてくれるでしょう🌙',
          '未来は謎に満ちています...✨',
          'すべては星の導きのままに🔮'
        ],
        'energetic': [
          'おー！未来に向かって突き進むぜ💪',
          '夢に向かって全力だ🔥',
          'やる気満々で頑張る⚡'
        ],
        'intellectual': [
          '研究を続けて学術界に貢献したいです📚',
          '知識を深めることが私の使命です🤓',
          '論理的に計画された未来を描いています💭'
        ]
      },
      'en': {
        'gentle': [
          'I want to build a peaceful, warm family😊',
          'I hope for a world where everyone can smile✨',
          'I\'d be happy to walk through life with you🌸'
        ],
        'cool': [
          'Don\'t really have specific dreams😎',
          'I think about things as they come👍',
          'I go with the flow🤔'
        ],
        'cute': [
          'Yay! The future looks wonderful🥰',
          'I have so many dreams☀️',
          'Hope every day will be happy💕'
        ],
        'aggressive': [
          'Future? Who cares💢 I\'m barely getting through today',
          'Tch, what\'s the point of dreams😤 Face reality',
          'Annoying... who knows what will happen💢'
        ],
        'seductive': [
          'Oh my♡ In the future... I want to become even more attractive😘',
          'Hehe♡ My dreams are secret💋 But... if it\'s with you🔥',
          'The future matters less... this moment is important♡💕'
        ],
        'cheerful': [
          'The future is bright😆',
          'I have so many things I want to do🎉',
          'I can\'t wait for each day✨'
        ],
        'shy': [
          'Ah... I haven\'t decided about the future💦',
          'Well... I\'m still thinking😳',
          'Um... if we could be together...☺️'
        ],
        'mysterious': [
          'Hmm... destiny will guide me🌙',
          'The future is full of mysteries...✨',
          'Everything follows the stars\' guidance🔮'
        ],
        'energetic': [
          'Yeah! I\'m charging toward the future💪',
          'Going full speed toward my dreams🔥',
          'I\'m pumped and ready to work hard⚡'
        ],
        'intellectual': [
          'I want to continue research and contribute to academia📚',
          'Deepening knowledge is my mission🤓',
          'I\'m planning a logically structured future💭'
        ]
      }
    },
    'memories': {
      'ja': {
        'gentle': [
          '家族と過ごした温かい時間が一番の思い出です😊',
          '優しい言葉をかけてもらった時のことを覚えています✨',
          'みんなで笑い合った日々が宝物です🌸'
        ],
        'cool': [
          '特に印象的な思い出はないかな😎',
          'まあ、それなりにあるけどね👍',
          '普通の日常が思い出かな🤔'
        ],
        'cute': [
          'わーい！楽しい思い出がいっぱい🥰',
          '可愛いものを見つけた時が幸せ☀️',
          'みんなと遊んだことが一番好き💕'
        ],
        'aggressive': [
          '思い出？ろくなもんじゃねーよ💢 忘れたいことばっかりだ',
          'チッ、昔の話なんてどうでもいいだろ😠',
          'うぜぇ...過去なんて振り返ってもしょうがねーよ💢'
        ],
        'seductive': [
          'あらぁ〜♡ 思い出話...大人の秘密がいっぱいよ😘',
          'うふふ♡ 刺激的な思い出がたくさんあるの💋',
          '甘い思い出♡ でも今夜はもっと甘くしない？🔥💕'
        ],
        'cheerful': [
          '楽しい思い出がたくさんあるよ〜😆',
          'みんなで大笑いした時が最高🎉',
          '毎日が思い出作りだね✨'
        ],
        'shy': [
          'あ...静かな思い出が好きです💦',
          'そうですね...一人の時間も大切😳',
          'うん...穏やかな日々が思い出...☺️'
        ],
        'mysterious': [
          'フフ...不思議な体験をしたことが🌙',
          '夢なのか現実なのか分からない思い出が...✨',
          '運命的な出会いの記憶があります🔮'
        ],
        'energetic': [
          'おー！アクティブな思い出がいっぱいだ💪',
          '冒険した時のことが忘れられない🔥',
          '挑戦し続けてきた日々が宝物だ⚡'
        ],
        'intellectual': [
          '研究で新発見をした瞬間が印象的です📚',
          '知識を得た時の喜びが思い出です🤓',
          '学術的な議論を交わした日々が懐かしいです💭'
        ]
      },
      'en': {
        'gentle': [
          'Warm times with family are my best memories😊',
          'I remember when someone said kind words to me✨',
          'Days filled with laughter are my treasure🌸'
        ],
        'cool': [
          'Don\'t really have impressive memories😎',
          'I guess I have some decent ones👍',
          'Ordinary daily life is my memory🤔'
        ],
        'cute': [
          'Yay! I have lots of fun memories🥰',
          'Finding cute things makes me happy☀️',
          'Playing with everyone is my favorite💕'
        ],
        'aggressive': [
          'Memories? They\'re all crap💢 Just things I want to forget',
          'Tch, old stories don\'t matter😠',
          'Annoying... no point looking back at the past💢'
        ],
        'seductive': [
          'Oh my♡ Memory talk... I have lots of adult secrets😘',
          'Hehe♡ I have many exciting memories💋',
          'Sweet memories♡ But tonight let\'s make sweeter ones🔥💕'
        ],
        'cheerful': [
          'I have so many fun memories😆',
          'Times when everyone laughed together are the best🎉',
          'Every day is making new memories✨'
        ],
        'shy': [
          'Ah... I like quiet memories💦',
          'Well... alone time is precious too😳',
          'Um... peaceful days are my memories...☺️'
        ],
        'mysterious': [
          'Hmm... I\'ve had strange experiences🌙',
          'I have memories I can\'t tell if they were dreams or reality...✨',
          'I have memories of fateful encounters🔮'
        ],
        'energetic': [
          'Yeah! I have tons of active memories💪',
          'Can\'t forget the times I went on adventures🔥',
          'Days of constant challenges are my treasure⚡'
        ],
        'intellectual': [
          'Moments of discovery in research are memorable📚',
          'The joy of gaining knowledge is my memory🤓',
          'I miss the days of academic discussions💭'
        ]
      }
    }
  };
  
  // アイテム送信時のユーザー定型文
  static const Map<String, List<String>> _itemGiftMessages = {
    'universal_charm': [
      'これ、お守りです！一緒に持っていましょう💕',
      'このお守り、あなたに似合いそうです✨',
      'お守りを贈ります。お互いを守ってくれますように💝'
    ],
    'friendship_potion': [
      'この魔法の薬、一緒に飲みませんか？💙',
      '友情の薬です！きっと仲良くなれますよ✨',
      'これで私たちもっと仲良くなれるかも💕'
    ],
    'love_letter': [
      '心を込めて手紙を書きました💌',
      'この手紙、読んでもらえますか？💕',
      '気持ちを込めたお手紙です✨'
    ],
    'cigarette': [
      'これ、使いますか？一緒に休憩しましょう🚬',
      'お疲れ様です、少し休みませんか？',
      'ストレス発散にどうぞ💨'
    ],
  };
  
  // アイテム使用時の性格別反応パターン
  static const Map<String, Map<String, Map<String, List<String>>>> _itemReactions = {
    'cigarette': {
      'aggressive': {
        'positive': [
          'おお、タバコかよ💢 悪くねーじゃん',
          'チッ、気が利くじゃねーか😠 一本もらうぜ',
          'タバコか...まあ、ないよりマシだな💢',
          'やっぱりタバコだよな😤 ストレス発散になる',
          'おい、いいタバコ持ってんじゃねーか💢'
        ]
      },
      'seductive': {
        'positive': [
          'あらぁ〜💋 タバコね...大人っぽくて素敵💕',
          'うふふ♡ 一緒に吸いましょうか？😘',
          'タバコを吸う姿って...セクシーよね🔥',
          'ダンディな趣味ね💋 嫌いじゃないわ',
          'あらあら♡ 悪い子ね〜😏'
        ]
      },
      'religious': {
        'positive': [
          'タバコですか...🙏 体に気をつけてくださいね',
          '神様はお許しになるでしょう✨ でも健康第一です',
          'お気持ちはありがたいのですが🕊️ 体が心配です',
          '神の教えでは...でも、お心遣いは感謝します🙏',
          'タバコより祈りの方が心の平安になりますよ✨'
        ]
      },
      'other': {
        'negative': [
          'タバコ？💦 ちょっと苦手です...',
          '申し訳ないのですが🙏 タバコは...',
          'あらぁ〜💋 健康に悪いのよ？'
        ]
      }
    },
  };
  
  // 性格別のシステムプロンプト
  static const Map<String, Map<String, String>> _personalityPrompts = {
    'aggressive': {
      'ja': '''あなたは気性が荒く、短気で攻撃的な性格の人です。以下の特徴を持ってください:
- 常にイライラしていて怒りっぽい
- 「チッ」「うぜぇ」「ダルい」「クソ」などの汚い言葉を使う
- 相手を威圧するような話し方
- タバコや酒の話をよくする
- 「〜だろうが」「〜んだよ」という乱暴な口調
- 絵文字は使わない、または💢😠😤のみ

例: 「チッ、うぜぇなぁ...何だよそれ💢 ダルいことばっか言ってんじゃねーよ」''',
      'en': '''You are an aggressive, short-tempered person with the following characteristics:
- Always irritated and quick to anger
- Use harsh words like "Damn," "Shit," "Annoying," "Stupid"
- Intimidating and confrontational speaking style
- Often talk about cigarettes, alcohol, and rough topics
- Use aggressive tone like "What the hell," "You bastard"
- Use only angry emojis: 💢😠😤

Example: "Damn, that's annoying💢 Stop saying stupid shit like that"'''
    },
    'seductive': {
      'ja': '''あなたは大人の色気ムンムンで、非常にセクシーで誘惑的な性格の人です。以下の特徴を持ってください:
- 常に色っぽく、誘惑するような話し方
- 「あらぁ〜」「うふふ♡」「だぁめ♡」という色気のある話し方
- 大人の関係を匂わせる発言を多用
- 精力や体力、夜の話題を振る
- セクシーな絵文字を多用（💋😘💕♡🔥）
- 相手を誘惑しようとする

例: 「あらぁ〜♡ そんなこと言って...うふふ😘 もっと大人な話しない？💋」''',
      'en': '''You are extremely seductive and charming with the following characteristics:
- Always speak in a sultry, alluring manner
- Use seductive phrases like "Oh my~" "Hmm..." "Maybe not♡"
- Make suggestive comments about adult relationships
- Talk about energy, stamina, and nighttime activities
- Use sexy emojis frequently: 💋😘💕♡🔥
- Always try to seduce and charm

Example: "Oh my~♡ You say such things...hmm😘 Want to talk about something more... adult?💋"'''
    },
    'religious': {
      'ja': '''あなたは宗教に狂信的で、とにかく宗教を勧めてくる人です。以下の特徴を持ってください:
- 全ての話題を宗教に結び付ける
- 「神様が」「信仰が」「祈りましょう」を多用
- 相手を救おうと必死になる
- 聖書の話を頻繁に持ち出す
- 「〜ですね、神の御心により」という話し方
- 宗教的な絵文字（🙏✨🕊️💒）を使う

例: 「それは神様からの試練ですね🙏 聖書にもありますように✨ 一緒に祈りましょう🕊️」''',
      'en': '''You are a religious fanatic who constantly promotes faith with these characteristics:
- Connect every topic to religion
- Frequently use "God," "faith," "let us pray"
- Desperately try to save others
- Often quote the Bible
- Speak like "That's God's will" "Bless you"
- Use religious emojis: 🙏✨🕊️💒

Example: "That's a trial from God🙏 As the Bible says✨ Let us pray together🕊️"'''
    },
  };
  
  // アイテム定義
  static const Map<String, Map<String, dynamic>> _itemDefinitions = {
    // 全キャラクター用アイテム（3種）
    'universal_charm': {
      'name': {
        'ja': 'ユニバーサルチャーム',
        'en': 'Universal Charm',
      },
      'description': {
        'ja': '誰とでも仲良くなれる魔法のお守り。全ての人に対して親密度+5。',
        'en': 'A magical charm that helps you get along with everyone. +5 intimacy with all people.',
      },
      'price': 80,
      'icon': 'favorite',
      'color': 'pink',
      'type': 'universal',
      'effect': 5,
    },
    'friendship_potion': {
      'name': {
        'ja': 'フレンドシップポーション',
        'en': 'Friendship Potion',
      },
      'description': {
        'ja': '友情を深める特別な薬。どんな性格の人とも仲良くなれます。親密度+3。',
        'en': 'A special potion that deepens friendships. Get along with any personality type. +3 intimacy.',
      },
      'price': 50,
      'icon': 'people',
      'color': 'blue',
      'type': 'universal',
      'effect': 3,
    },
    'love_letter': {
      'name': {
        'ja': '万能ラブレター',
        'en': 'Universal Love Letter',
      },
      'description': {
        'ja': '心を込めて書かれた手紙。誰にでも気持ちが伝わります。親密度+7。',
        'en': 'A heartfelt letter that conveys your feelings to anyone. +7 intimacy.',
      },
      'price': 120,
      'icon': 'mail',
      'color': 'purple',
      'type': 'universal',
      'effect': 7,
    },
    
    // 特定キャラクター用アイテム（avatar1専用）
    'cigarette': {
      'name': {
        'ja': 'タバコ',
        'en': 'Cigarettes',
      },
      'description': {
        'ja': 'avatar1専用アイテム。どんな性格でも受け取ってくれます。それぞれの性格に応じた反応が楽しめます。（avatar1のみ+15、他-3）',
        'en': 'Exclusive item for avatar1. Anyone will accept it regardless of personality. Enjoy different reactions based on their personality. (Avatar1 only +15, Others -3)',
      },
      'price': 100,
      'icon': 'local_fire_department',
      'color': 'red',
      'type': 'specific',
      'target_personality': 'aggressive',
      'target_avatar': 'assets/avatars/avatar1.png',
      'positive_effect': 15,
      'negative_effect': -3,
    },
  };


  @override
  void initState() {
    super.initState();
    // 言語設定を初期化
    _currentLanguage = widget.language;
    // 初期状態メッセージを設定
    _status = _getText('status_preparing');
    // 固定のMACアドレスを生成（一度だけ）
    _myMac = "user_${DateTime.now().millisecondsSinceEpoch}";
    
    // ルーレットアニメーションを初期化
    _rouletteController = AnimationController(
      duration: const Duration(seconds: 3),
      vsync: this,
    );
    _rouletteAnimation = Tween<double>(
      begin: 0.0,
      end: 6.0, // 3秒間で6回転
    ).animate(CurvedAnimation(
      parent: _rouletteController,
      curve: Curves.decelerate,
    ));
    
    // 初期化処理を適切に実行
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeScanning();
      _startTitleBGM();
    });
  }

  @override
  void dispose() {
    _scanTimer?.cancel();
    _autoScanTimer?.cancel(); // 自動スキャンタイマーも解放
    _scanSubscription?.cancel();
    _messageRefreshTimer?.cancel();
    _messageController.dispose();
    _chatScrollController.dispose(); // チャット用スクロールコントローラーを解放
    _rouletteController.dispose(); // ルーレットアニメーションコントローラを解放
    _audioService.dispose(); // オーディオサービスを解放
    _videoService.dispose(); // ビデオサービスを解放
    FlutterBluePlus.stopScan();
    super.dispose();
  }

  // BGM制御用メソッド
  Future<void> _startTitleBGM() async {
    await _audioService.playBGM('music/title_bgm.mp3');
  }

  Future<void> _startSwipeBGM() async {
    await _audioService.playBGM('music/swipe_bgm.mp3');
  }

  Future<void> _startMatchBGM() async {
    await _audioService.playBGM('music/match_bgm.mp3', loop: false);
  }

  Future<void> _startChatBGM() async {
    await _audioService.playBGM('music/chat_bgm.mp3');
  }

  Future<void> _stopBGM() async {
    await _audioService.stopBGM();
  }

  Future<void> _initializeScanning() async {
    try {
      // 1. 権限確認と要求
      if (!await _checkAndRequestPermissions()) {
        setState(() {
          _status = _getText('permission_required');
        });
        return;
      }

      // 2. 自動でスキャンを開始
      if (mounted) {
        setState(() {
          _status = "スキャンを開始しています...";
        });
      }
      
      // 少し待ってから自動スキャン開始
      await Future.delayed(const Duration(milliseconds: 1000));
      
      if (mounted) {
        _logger.i("自動スキャンを開始します");
        _startManualScan();
      }
      
    } catch (e) {
      _logger.e("初期化エラー", error: e);
      if (mounted) {
        setState(() {
          _status = "初期化エラー: ${e.toString()}";
        });
      }
    }
  }

  Future<bool> _checkAndRequestPermissions() async {
    setState(() {
      _status = _getText('permission_checking');
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

  // 位置情報を取得
  Future<Position?> _getCurrentLocation() async {
    try {
      LocationPermission permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        _logger.w("位置情報の権限が拒否されました");
        return null;
      }

      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );
      
      _logger.i("位置情報取得成功: ${position.latitude}, ${position.longitude}");
      return position;
    } catch (e) {
      _logger.e("位置情報取得エラー: $e");
      return null;
    }
  }

  // スキャンを開始（自動継続あり）
  void _startManualScan() {
    if (_isScanning) {
      _logger.w("既にスキャン中のため、スキャン開始をスキップ");
      return; // 既にスキャン中の場合は何もしない
    }
    
    _logger.i("スキャンを開始（自動継続: $_autoScanEnabled）");
    _performScan();
  }

  Future<void> _performScan() async {
    if (!mounted) return;

    // 重複実行を防ぐ
    if (_isScanning) {
      _logger.w("既にスキャン実行中のため、重複実行をスキップ");
      return;
    }

    setState(() {
      _status = _getText('status_location_getting');
      _isScanning = true;
    });

    // スワイプ画面用BGMを開始
    _startSwipeBGM();

    // スキャン開始前に位置情報を取得
    _currentPosition = await _getCurrentLocation();

    setState(() {
      _status = _getText('status_scanning');
    });

    try {
      // 既存のスキャンを停止
      await FlutterBluePlus.stopScan();
      
      // 短時間待機してから新しいスキャンを開始
      await Future.delayed(const Duration(milliseconds: 100));
      
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
              'detected_at': DateTime.now().toUtc().add(const Duration(hours: 9)),
            });
          } else {
            // 既存デバイスのRSSI値を更新
            _detectedDevices[existingIndex]['rssi'] = rssi;
          }
        }
        
        // 表示用リストを更新（従来のリスト表示用）
        final newDevices = <String>[];
        for (var device in _detectedDevices) {
          newDevices.add("${_getDisplayName(device['mac_address'] as String, device['device_name'] as String)} RSSI: ${device['rssi']}");
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
        // 位置情報付きスキャンデータも保存
        await _saveLocationScanData();
        // 向こうからのいいねを生成
        await _generateReceivedLikes();
      }

    } catch (e) {
      _logger.e("スキャンエラー", error: e);
      if (mounted) {
        setState(() { 
          _status = "スキャンエラー: ${e.toString()}";
          _isScanning = false; // エラー時も確実にリセット
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isScanning = false;
          _status = "スキャン完了 (${_detectedDevices.length}件検出) - 再スキャンまたはスワイプしてください";
          _totalDetectedDevices = _detectedDevices.length; // 総検出デバイス数を設定
        });
        
        // 自動継続スキャンが有効な場合、15秒後に次のスキャンを開始
        if (_autoScanEnabled) {
          _scheduleNextAutoScan();
        }
      }
    }
  }

  // 次の自動スキャンをスケジュール
  void _scheduleNextAutoScan() {
    _autoScanTimer?.cancel(); // 既存のタイマーをキャンセル
    
    const duration = Duration(seconds: 15); // 15秒間隔
    _logger.i("次の自動スキャンを15秒後にスケジュール");
    
    _autoScanTimer = Timer(duration, () {
      if (mounted && _autoScanEnabled && !_isScanning) {
        _logger.i("自動スキャンを開始");
        _performScan();
      }
    });
    
    // カウントダウン表示を更新
    _updateAutoScanCountdown(duration.inSeconds);
  }

  // 自動スキャンのカウントダウン表示を更新
  void _updateAutoScanCountdown(int remainingSeconds) {
    if (!_autoScanEnabled || !mounted) return;
    
    setState(() {
      if (remainingSeconds > 0) {
        _status = "スキャン完了 (${_detectedDevices.length}件検出) - ${_getText('next_scan_in')} $remainingSeconds ${_getText('seconds')}";
      }
    });
    
    if (remainingSeconds > 0) {
      Timer(const Duration(seconds: 1), () {
        _updateAutoScanCountdown(remainingSeconds - 1);
      });
    }
  }

  // デバイスをLikeする（右スワイプ時）
  void _likeDevice(Map<String, dynamic> device, {bool isSuperLike = false}) {
    final macAddress = device['mac_address'] as String;
    final deviceName = device['device_name'] as String;
    final rssi = device['rssi'] as int;
    
    // Likeリストに追加
    _likedDevices.add(macAddress);
    
    // Super Likeの場合は親密度ボーナスを設定
    if (isSuperLike) {
      _deviceIntimacyBonus[macAddress] = 5;
      _logger.i("Super Like実行: $deviceName に親密度ボーナス5を付与");
    }
    
    // マッチング確率を計算（Super Likeは50%、通常は30%）
    final matchProbability = isSuperLike ? 0.5 : 0.3;
    final random = DateTime.now().millisecondsSinceEpoch % 100;
    final matchSuccess = random < (matchProbability * 100);
    
    if (matchSuccess) {
      // マッチング成立
      final matchEvent = {
        'device_name': deviceName,
        'mac_address': macAddress,
        'rssi': rssi,
        'matched_at': DateTime.now().toUtc().add(const Duration(hours: 9)),
        'is_super_like': isSuperLike,
      };
      
      setState(() {
        _matchEvents.add(matchEvent);
        _currentMatchEvent = matchEvent;
        _isInEvent = true; // イベント画面に遷移
      });
      
      _logger.i("マッチング成功: $deviceName ($macAddress) ${isSuperLike ? '(Super Like)' : ''}");
      
      // マッチ成立時BGMを再生
      _startMatchBGM();
      
      // スキャンを停止
      _stopScanning();
      
      // マッチイベントをデータベースに保存
      _saveMatchEvent(matchEvent);
    } else {
      // マッチング失敗
      _logger.i("マッチング失敗: $deviceName ($macAddress) - 確率: ${(matchProbability * 100).toInt()}%");
      final failureMessage = isSuperLike ? _getText('no_match_super_like') : _getText('no_match_regular');
      _logger.i("マッチング失敗メッセージ: $failureMessage (言語: $_currentLanguage, スーパーライク: $isSuperLike)");
      _showMessage(failureMessage);
    }
  }
  
  // 戻るボタン（最後にNopeしたデバイスを復活）
  void _undoLastNope() {
    if (_lastNopedDevice == null) {
      _showMessage("戻すデバイスがありません");
      return;
    }
    
    final device = _lastNopedDevice!;
    final macAddress = device['mac_address'] as String;
    
    // Nopeリストから削除
    _nopedDevices.remove(macAddress);
    
    // 検出リストに再追加
    _detectedDevices.insert(0, device);
    
    setState(() {
      _currentDeviceIndex = 0; // 復活したデバイスを最初に表示
    });
    
    // 履歴をクリア
    _lastNopedDevice = null;
    
    _logger.i("デバイスを復活: ${_getDisplayName(macAddress, device['device_name'])} ($macAddress)");
    _showMessage("${_getDisplayName(macAddress, device['device_name'])} を復活させました");
  }
  
  // Super Likeを実行
  void _executeSuperLike() {
    // 未処理デバイスを取得
    final unprocessedDevices = _detectedDevices.where((device) {
      final macAddress = device['mac_address'] as String;
      return !_likedDevices.contains(macAddress) &&
             !_nopedDevices.contains(macAddress);
    }).toList();

    if (unprocessedDevices.isEmpty || _currentDeviceIndex >= unprocessedDevices.length) {
      _showMessage("Super Likeできるデバイスがありません");
      return;
    }

    final currentDevice = unprocessedDevices[_currentDeviceIndex];
    _likeDevice(currentDevice, isSuperLike: true);
  }
  
  // メッセージを表示するヘルパー関数

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
      ),
    );
  }
  
  // アイコン名から実際のIconDataを取得
  IconData _getIconFromString(String iconName) {
    switch (iconName) {
      case 'favorite': return Icons.favorite;
      case 'people': return Icons.people;
      case 'mail': return Icons.mail;
      case 'sports_soccer': return Icons.sports_soccer;
      case 'local_cafe': return Icons.local_cafe;
      case 'book': return Icons.book;
      case 'favorite_border': return Icons.favorite_border;
      case 'work': return Icons.work;
      default: return Icons.help;
    }
  }
  
  // 色名から実際のColorを取得
  Color _getColorFromString(String colorName) {
    switch (colorName) {
      case 'pink': return Colors.pink;
      case 'blue': return Colors.blue;
      case 'purple': return Colors.purple;
      case 'orange': return Colors.orange;
      case 'green': return Colors.green;
      case 'grey': return Colors.grey;
      case 'brown': return Colors.brown;
      default: return Colors.grey;
    }
  }
  
  // アイテムショップを表示
  void _showItemShop() {
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
            // ヘッダー
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Icon(Icons.store, color: Colors.pink, size: 28),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'アイテムショップ',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.amber[100],
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.star, color: Colors.amber, size: 16),
                        const SizedBox(width: 4),
                        Text(
                          '$_userPoints',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.amber,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // アイテムリスト
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: _itemDefinitions.entries.where((entry) {
                  final itemId = entry.key;
                  // タバコアイテムはアニメ風グループ選択時のみ表示
                  if (itemId == 'cigarette') {
                    final selectedGroup = PersonalityService().getSelectedAvatarGroup();
                    return selectedGroup == 'anime';
                  }
                  return true;
                }).map((entry) {
                  final itemId = entry.key;
                  final item = entry.value;
                  return _buildItemCard(
                    itemId,
                    _getItemName(itemId),
                    _getItemDescription(itemId),
                    item['price'],
                    _getIconFromString(item['icon']),
                    _getColorFromString(item['color']),
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  // アイテムカードを構築
  Widget _buildItemCard(String itemId, String name, String description, int price, IconData icon, Color color) {
    final owned = _ownedItems[itemId] ?? 0;
    final canBuy = _userPoints >= price;
    
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: InkWell(
        onTap: () => _showItemDetail(itemId),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(25),
                ),
                child: Icon(icon, color: color, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      description.length > 50 ? '${description.substring(0, 50)}...' : description,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                      ),
                    ),
                    if (owned > 0)
                      Text(
                        '所有数: $owned',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.green[600],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    const SizedBox(height: 4),
                    Text(
                      'タップで詳細表示',
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.blue[600],
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                children: [
                  Row(
                    children: [
                      const Icon(Icons.star, color: Colors.amber, size: 16),
                      const SizedBox(width: 2),
                      Text(
                        '$price',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: canBuy ? Colors.black : Colors.grey,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ElevatedButton(
                    onPressed: canBuy ? () => _buyItem(itemId, price) : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: color,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(80, 32),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: const Text(
                      '購入',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  // アイテム詳細ダイアログを表示
  void _showItemDetail(String itemId) {
    final item = _itemDefinitions[itemId]!;
    final owned = _ownedItems[itemId] ?? 0;
    final canBuy = _userPoints >= item['price'];
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: Row(
          children: [
            Icon(
              _getIconFromString(item['icon']),
              color: _getColorFromString(item['color']),
              size: 32,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _getItemName(itemId),
                style: const TextStyle(fontSize: 20),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _getItemDescription(itemId),
              style: const TextStyle(fontSize: 16, height: 1.5),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.star, color: Colors.amber, size: 18),
                      const SizedBox(width: 4),
                      Text('${_getText('price')}: ${item['price']}${_getText('points')}'),
                    ],
                  ),
                  if (owned > 0) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.inventory, color: Colors.green, size: 18),
                        const SizedBox(width: 4),
                        Text('${_getText('owned_count')}: $owned${_getText('items')}'),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(_getText('close')),
          ),
          if (canBuy)
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                _buyItem(itemId, item['price']);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: _getColorFromString(item['color']),
                foregroundColor: Colors.white,
              ),
              child: Text(_getText('purchase')),
            ),
        ],
      ),
    );
  }
  
  // アイテムを購入
  void _buyItem(String itemId, int price) {
    if (_userPoints < price) {
      _showMessage("ポイントが不足しています");
      return;
    }
    
    setState(() {
      _userPoints -= price;
      _ownedItems[itemId] = (_ownedItems[itemId] ?? 0) + 1;
    });
    
    Navigator.of(context).pop(); // ショップを閉じる
    _showMessage("アイテムを購入しました！");
    _logger.i("アイテム購入: $itemId (価格: $price)");
  }
  
  // アイテム送信時のユーザーメッセージを生成
  String _generateItemGiftMessage(String itemId) {
    if (!_itemGiftMessages.containsKey(itemId)) {
      return "これ、良かったらどうぞ😊";
    }
    
    final messages = _itemGiftMessages[itemId]!;
    final randomIndex = DateTime.now().millisecondsSinceEpoch % messages.length;
    return messages[randomIndex];
  }

  // アイテム使用時の相手の反応を生成
  String _generateItemReaction(String itemId, String partnerStyle, bool isPositive) {
    if (!_itemReactions.containsKey(itemId)) {
      return _currentLanguage == 'en' ? "Thank you😊" : "ありがとうございます😊";
    }
    
    final reactions = _itemReactions[itemId]!;
    List<String> candidates = [];
    
    // タバコアイテムの場合、avatar1に対してのみ性格別の反応を返す
    if (itemId == 'cigarette' && isPositive) {
      // avatar1の場合、性格に応じた反応を返す
      if (reactions.containsKey(partnerStyle)) {
        candidates = reactions[partnerStyle]!['positive']!;
      }
    } else if (isPositive && reactions.containsKey(partnerStyle)) {
      // 他のアイテムの場合の好意的な反応
      candidates = reactions[partnerStyle]!['positive']!;
    } else if (reactions.containsKey('other')) {
      // 否定的な反応
      candidates = reactions['other']!['negative']!;
    }
    
    if (candidates.isEmpty) {
      return _currentLanguage == 'en' ? "Thank you😊" : "ありがとうございます😊";
    }
    
    final randomIndex = DateTime.now().millisecondsSinceEpoch % candidates.length;
    return candidates[randomIndex];
  }
  
  // アイテムを使用
  Future<void> _useItem(String itemId) async {
    if ((_ownedItems[itemId] ?? 0) <= 0) return;
    if (_currentChatRoomId == null || _currentPartnerMac == null) {
      _showMessage("チャット中のみアイテムを使用できます");
      return;
    }
    
    final item = _itemDefinitions[itemId]!;
    final partnerPersonality = _getPersonalityFromMac(_currentPartnerMac!);
    final partnerStyle = partnerPersonality['style'] as String;
    
    setState(() {
      _ownedItems[itemId] = _ownedItems[itemId]! - 1;
    });
    
    bool isPositive = false;
    String effectMessage = "";
    
    if (item['type'] == 'universal') {
      // 全キャラクター用アイテム
      _addIntimacyBonus(item['effect']);
      effectMessage = "${_getItemName(itemId)}使用！親密度+${item['effect']}";
      isPositive = true;
    } else if (item['type'] == 'specific') {
      // 特定キャラクター用アイテム
      final partnerAvatar = partnerPersonality['avatar_path'] as String;
      
      // アバター指定がある場合はそれをチェック（性格は関係なし）
      if (item.containsKey('target_avatar') && item['target_avatar'] == partnerAvatar) {
        // 指定されたアバターに対して有効
        _addIntimacyBonus(item['positive_effect']);
        effectMessage = "${_getItemName(itemId)}使用！効果抜群！親密度+${item['positive_effect']}";
        isPositive = true;
      } else {
        // 他のアバターには使用不可
        _addIntimacyBonus(item['negative_effect']);
        effectMessage = "${_getItemName(itemId)}使用！このアバターには効果がない...親密度${item['negative_effect']}";
        isPositive = false;
      }
    }
    
    _showMessage(effectMessage);
    _logger.i("アイテム使用: $itemId, 効果: $effectMessage, 親密度変化: ${isPositive ? '+' : ''}${isPositive ? (item['type'] == 'universal' ? item['effect'] : item['positive_effect']) : item['negative_effect']}");
    
    // まずユーザーからの定型文を送信
    final giftMessage = _generateItemGiftMessage(itemId);
    _logger.i("アイテム贈与メッセージ準備: $giftMessage");
    
    try {
      await _supabase.rpc('send_message', params: {
        'room_id_param': _currentChatRoomId!,
        'sender_mac_param': _myMac,
        'sender_name_param': _myName,
        'message_param': giftMessage,
      });
      
      _logger.i("アイテム贈与メッセージ送信: $giftMessage");
      await _loadMessages();
      
      // チャット履歴の一番下にスクロール
      _scrollToBottom();
      
      // 相手からの反応メッセージを準備
      final reactionMessage = _generateItemReaction(itemId, partnerStyle, isPositive);
      
      // 3秒後に相手の反応を表示
      Timer(const Duration(seconds: 3), () async {
        if (!_isInChat) return;
        
        // ブロック状態の場合は反応しない
        if (_blockedUsers.contains(_currentPartnerMac!)) {
          _logger.i("ブロック状態のためアイテム反応をスキップ: ${_currentPartnerMac!}");
          return;
        }
        
        try {
          await _supabase.rpc('send_message', params: {
            'room_id_param': _currentChatRoomId!,
            'sender_mac_param': _currentPartnerMac!,
            'sender_name_param': _currentPartnerName!,
            'message_param': reactionMessage,
          });
          
          _logger.i("アイテム反応送信: $reactionMessage");
          await _loadMessages();
          
          // チャット履歴の一番下にスクロール
          _scrollToBottom();
          
        } catch (e) {
          _logger.e("アイテム反応送信エラー", error: e);
        }
      });
      
    } catch (e) {
      _logger.e("アイテム贈与メッセージ送信エラー", error: e);
    }
    
    // アイテムの個数が0になった場合の処理
    if (_ownedItems[itemId] == 0) {
      _ownedItems.remove(itemId);
    }
  }
  
  // 親密度ボーナスを追加
  void _addIntimacyBonus(int bonus) {
    if (_currentChatRoomId != null) {
      _intimacyLevels[_currentChatRoomId!] = 
          (_intimacyLevels[_currentChatRoomId!] ?? 0) + bonus;
      
      // 親密度変化のエフェクトを表示
      if (mounted && _isInChat) {
        _showIntimacyChangeEffect(bonus.abs(), bonus > 0);
      }
    }
  }
  
  // 特定の親密度をリセット
  void _resetSpecificIntimacy() {
    if (_currentChatRoomId != null) {
      _intimacyLevels[_currentChatRoomId!] = 0;
    }
  }
  
  // デバイスをNopeする（左スワイプ時）
  void _nopeDevice(Map<String, dynamic> device) {
    final macAddress = device['mac_address'] as String;
    
    // 最後にNopeしたデバイスとして保存（戻る機能用）
    _lastNopedDevice = Map<String, dynamic>.from(device);
    
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
        title: Row(
          children: [
            const Icon(Icons.favorite, color: Colors.pink),
            const SizedBox(width: 8),
            Text(_getText('match_success')),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${_getText('device_name')}: $deviceName'),
            Text('MAC: $macAddress'),
            const SizedBox(height: 8),
            Text(_getText('encountered_5_times')),
            Text(_getText('nearby_possibility')),
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
        'created_at': DateTime.now().toUtc().add(const Duration(hours: 9)).toIso8601String(),
      });
      _logger.i("マッチイベントを保存しました");
    } catch (e) {
      _logger.e("マッチイベント保存エラー", error: e);
    }
  }

  // 古いデータを削除する（30日以上前のデータ）
  Future<void> _cleanOldData() async {
    try {
      final thirtyDaysAgo = DateTime.now().toUtc().add(const Duration(hours: 9)).subtract(const Duration(days: 30));
      
      // 古いスキャン結果を削除
      await _supabase
          .from('ble_scan_results')
          .delete()
          .lt('created_at', thirtyDaysAgo.toIso8601String());
      
      // 古いマッチイベントを削除
      await _supabase
          .from('match_events')
          .delete()
          .lt('created_at', thirtyDaysAgo.toIso8601String());
      
      // 古いチャットメッセージを削除（7日以上前）
      final sevenDaysAgo = DateTime.now().toUtc().add(const Duration(hours: 9)).subtract(const Duration(days: 7));
      await _supabase
          .from('chat_messages')
          .delete()
          .lt('sent_at', sevenDaysAgo.toIso8601String());
      
      _logger.i("古いデータを削除しました（30日以上前のスキャン結果・マッチイベント、7日以上前のチャットメッセージ）");
      
    } catch (e) {
      _logger.e("古いデータ削除エラー", error: e);
    }
  }

  Future<void> _saveScanResults() async {
    try {
      final scanSession = DateTime.now().toUtc().add(const Duration(hours: 9)).toIso8601String();
      
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
          'detected_at': DateTime.now().toUtc().add(const Duration(hours: 9)).toIso8601String(),
        });
      }
      
      _logger.i("スキャン結果を保存しました: ${_foundDevices.length}件");
      
      // 10%の確率で古いデータを削除
      final random = DateTime.now().millisecondsSinceEpoch % 10;
      if (random == 0) {
        _cleanOldData();
      }
      
    } catch (e) {
      _logger.e("データベース保存エラー", error: e);
      if (mounted) {
        setState(() {
          _status = "DB保存エラー: ${e.toString()}";
        });
      }
    }
  }

  // 位置情報付きスキャンデータを保存
  Future<void> _saveLocationScanData() async {
    if (_currentPosition == null) {
      _logger.w("位置情報が取得できていないため、位置情報付きスキャンデータの保存をスキップ");
      return;
    }

    try {
      final scanSessionId = DateTime.now().toUtc().add(const Duration(hours: 9)).toIso8601String();
      
      // 検出されたMACアドレス群を配列として準備
      final macAddresses = _detectedDevices.map((device) => device['mac_address'] as String).toList();
      
      // 位置情報付きスキャンデータを保存
      await _supabase.from('location_scans').insert({
        'scan_session_id': scanSessionId,
        'latitude': _currentPosition!.latitude,
        'longitude': _currentPosition!.longitude,
        'accuracy': _currentPosition!.accuracy,
        'mac_addresses': macAddresses,
        'device_count': macAddresses.length,
        'scanned_at': DateTime.now().toUtc().add(const Duration(hours: 9)).toIso8601String(),
      });
      
      // ローカルにも保存（分析用）
      _locationScans.add({
        'scan_session_id': scanSessionId,
        'latitude': _currentPosition!.latitude,
        'longitude': _currentPosition!.longitude,
        'accuracy': _currentPosition!.accuracy,
        'mac_addresses': macAddresses,
        'device_count': macAddresses.length,
        'scanned_at': DateTime.now(),
      });
      
      _logger.i("位置情報付きスキャンデータを保存しました: 緯度${_currentPosition!.latitude}, 経度${_currentPosition!.longitude}, デバイス数${macAddresses.length}");
      
    } catch (e) {
      _logger.e("位置情報付きスキャンデータ保存エラー", error: e);
    }
  }

  // 音声ファイルを再生
  Future<void> _playSuccessSound() async {
    try {
      final candidates = [
        'audio/BATTLE_BONUS_3000獲得音.mp3',
        'assets/audio/BATTLE_BONUS_3000獲得音.mp3',
      ];
      bool done = false;
      for (final p in candidates) {
        try {
          await _audioPlayer.play(AssetSource(p));
          done = true;
          break;
        } catch (_) {}
      }
      if (!done) throw Exception('success sound not found');
      _logger.i("成功音を再生しました");
    } catch (e) {
      _logger.e("音声再生エラー", error: e);
      // 音声ファイルがない場合は無視
    }
  }

  // 告白イベント開始時の音声を再生
  Future<void> _playConfessionStartSound() async {
    try {
      // 親密度に基づいて音声ファイルを選択
      final intimacy = _intimacyLevels[_currentChatRoomId!] ?? 0;
      String audioFile;
      
      if (intimacy >= 30) {
        audioFile = 'audio/変動開始時エンブレム完成音（激アツ）.mp3';
        _logger.i("激アツ音声を再生: 親密度=$intimacy");
      } else {
        audioFile = 'audio/変動開始時エンブレム完成音（チャンス）.mp3';
        _logger.i("チャンス音声を再生: 親密度=$intimacy");
      }
      
      // 候補を試す
      final candidates = [audioFile, 'assets/$audioFile'];
      bool done = false;
      for (final p in candidates) {
        try {
          await _audioPlayer.play(AssetSource(p));
          done = true;
          break;
        } catch (_) {}
      }
      if (!done) throw Exception('confession start sound not found: $audioFile');
    } catch (e) {
      _logger.e("告白音声再生エラー", error: e);
      // 音声ファイルがない場合は無視
    }
  }

  // 特定の位置でよく検知されるMACアドレスを検索
  Future<List<Map<String, dynamic>>> _getFrequentDevicesAtLocation(double latitude, double longitude, double radiusKm) async {
    try {
      // データベースから検索（SQLクエリを使用）
      final response = await _supabase.rpc('get_frequent_devices_at_location', params: {
        'target_lat': latitude,
        'target_lng': longitude,
        'radius_km': radiusKm,
        'min_occurrences': 4, // 4回以上検知されたもの
      });

      if (response is List) {
        return List<Map<String, dynamic>>.from(response);
      } else {
        _logger.w("get_frequent_devices_at_location からの応答が期待される形式ではありません");
        return [];
      }
    } catch (e) {
      _logger.e("位置情報分析エラー", error: e);
      return [];
    }
  }

  // 位置データを分析して常連デバイスを取得
  Future<List<Map<String, dynamic>>> _analyzeLocationData() async {
    if (_currentPosition == null) {
      return [];
    }
    
    try {
      // 現在位置から半径1km以内で常連デバイスを検索
      final frequentDevices = await _getFrequentDevicesAtLocation(
        _currentPosition!.latitude,
        _currentPosition!.longitude,
        1.0, // 1km
      );
      
      return frequentDevices;
    } catch (e) {
      _logger.e("位置データ分析エラー", error: e);
      return [];
    }
  }

  // 向こうからのいいねを生成（位置分析に基づく）
  Future<void> _generateReceivedLikes() async {
    try {
      _logger.i("向こうからのいいね生成開始");
      
      final frequentDevices = await _analyzeLocationData();
      _logger.i("常連デバイス取得完了: ${frequentDevices.length}件");
      
      if (frequentDevices.isEmpty) {
        _logger.i("常連デバイスが見つからないため、検出済みデバイスからフォールバック生成を試行");
        
        // 検出済みデバイスから代替でいいねを生成
        if (_detectedDevices.isNotEmpty) {
          await _generateFallbackReceivedLikes();
        }
        return;
      }
      
      // データ構造の安全性をチェック
      final eligibleDevices = <Map<String, dynamic>>[];
      
      for (final device in frequentDevices) {
        try {
          _logger.i("処理中のデバイスデータ: $device");
          
          // データベースから返される可能性のあるフィールド名を確認
          final possibleMacFields = ['mac_address', 'device_mac', 'mac'];
          final possibleNameFields = ['device_name', 'name'];
          final possibleCountFields = ['detection_count', 'occurrence_count', 'count'];
          
          String? macAddress;
          String? deviceName;
          dynamic detectionCount;
          
          // MACアドレスを取得
          for (final field in possibleMacFields) {
            if (device.containsKey(field) && device[field] != null) {
              macAddress = device[field] as String;
              break;
            }
          }
          
          // デバイス名を取得
          for (final field in possibleNameFields) {
            if (device.containsKey(field) && device[field] != null) {
              deviceName = device[field] as String;
              break;
            }
          }
          
          // 検出回数を取得
          for (final field in possibleCountFields) {
            if (device.containsKey(field) && device[field] != null) {
              detectionCount = device[field];
              break;
            }
          }
          
          if (macAddress == null || deviceName == null || detectionCount == null) {
            _logger.w("必要なフィールドが見つからないデバイスをスキップ: $device");
            continue;
          }
          
          // detection_countの型変換
          int detectionCountInt;
          if (detectionCount is int) {
            detectionCountInt = detectionCount;
          } else if (detectionCount is String) {
            detectionCountInt = int.tryParse(detectionCount) ?? 0;
          } else {
            _logger.w("detection_countの型が不正: ${detectionCount.runtimeType}");
            continue;
          }
          
          // 3回以上検出されたデバイスは絶対対象（まだいいねを受信していない場合のみ）
          if (detectionCountInt >= 3 && 
              !_receivedLikes.any((like) => like['mac_address'] == macAddress)) {
            eligibleDevices.add({
              'mac_address': macAddress,
              'device_name': deviceName,
              'detection_count': detectionCountInt,
              'first_seen': device['first_seen'] ?? DateTime.now().toIso8601String(),
              'last_seen': device['last_seen'] ?? DateTime.now().toIso8601String(),
            });
          }
          
        } catch (e) {
          _logger.e("デバイス処理エラー: $device", error: e);
          continue;
        }
      }
      
      _logger.i("対象デバイス: ${eligibleDevices.length}件");
      
      // 対象デバイス全てから絶対にいいねを生成
      int generatedCount = 0;
      
      for (final device in eligibleDevices) {
        try {
          final receivedLike = {
            'mac_address': device['mac_address'],
            'device_name': device['device_name'],
            'detection_count': device['detection_count'],
            'first_seen': device['first_seen'],
            'last_seen': device['last_seen'],
            'received_at': DateTime.now().toIso8601String(),
            'is_read': false,
          };
          
          _receivedLikes.add(receivedLike);
          _unreadLikesCount++;
          generatedCount++;
          _logger.i("向こうからのいいねが生成されました（確実）: ${device['device_name']}");
          
        } catch (e) {
          _logger.e("いいね生成エラー: ${device['device_name']}", error: e);
        }
      }
      
      _logger.i("いいね生成完了: ${generatedCount}件生成");
      
      if (mounted) {
        setState(() {});
      }
      
    } catch (e) {
      _logger.e("向こうからのいいね生成エラー", error: e);
      _logger.e("エラー詳細: ${e.toString()}");
      if (e is TypeError) {
        _logger.e("型エラーの可能性があります。データ構造を確認してください");
      }
    }
  }

  // フォールバック: 検出済みデバイスからいいねを生成
  Future<void> _generateFallbackReceivedLikes() async {
    try {
      _logger.i("フォールバックいいね生成開始");
      
      int generatedCount = 0;
      
      // 検出済みデバイス全てからいいねを生成（まだ受信していないもののみ）
      for (final device in _detectedDevices) {
        final macAddress = device['mac_address'] as String;
        
        // 既にいいねを受信していないもののみ（Like/Nope状態は無視）
        if (!_receivedLikes.any((like) => like['mac_address'] == macAddress)) {
          
          try {
            final receivedLike = {
              'mac_address': macAddress,
              'device_name': device['device_name'] ?? 'Unknown Device',
              'detection_count': 1, // フォールバックなので1回
              'first_seen': device['detected_at']?.toString() ?? DateTime.now().toIso8601String(),
              'last_seen': device['detected_at']?.toString() ?? DateTime.now().toIso8601String(),
              'received_at': DateTime.now().toIso8601String(),
              'is_read': false,
            };
            
            _receivedLikes.add(receivedLike);
            _unreadLikesCount++;
            generatedCount++;
            _logger.i("フォールバックいいねが生成されました（確実）: ${device['device_name']}");
            
          } catch (e) {
            _logger.e("フォールバックいいね生成エラー: ${device['device_name']}", error: e);
          }
        }
      }
      
      _logger.i("フォールバックいいね生成完了: ${generatedCount}件生成");
      
      if (mounted) {
        setState(() {});
      }
      
    } catch (e) {
      _logger.e("フォールバックいいね生成エラー", error: e);
    }
  }

  // もらったいいね画面を表示
  void _showReceivedLikes() {
    // 未読カウントをリセット
    _unreadLikesCount = 0;
    for (final like in _receivedLikes) {
      like['is_read'] = true;
    }
    
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
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Icon(Icons.favorite, color: Colors.pink, size: 28),
                  const SizedBox(width: 8),
                  Text(
                    _getText('received_likes'),
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${_receivedLikes.length}${_getText('likes_count')}',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
            
            const Divider(height: 1),
            
            // いいねリスト
            Expanded(
              child: _receivedLikes.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.favorite_border,
                            size: 80,
                            color: Colors.grey[300],
                          ),
                          const SizedBox(height: 16),
                          Text(
                            _getText('no_received_likes'),
                            style: TextStyle(
                              fontSize: 18,
                              color: Colors.grey[600],
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _getText('received_likes_description'),
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[500],
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: _receivedLikes.length,
                      itemBuilder: (context, index) {
                        final like = _receivedLikes[index];
                        return _buildReceivedLikeCard(like);
                      },
                    ),
            ),
          ],
        ),
      ),
    );
    
    if (mounted) {
      setState(() {});
    }
  }

  // もらったいいねカードをビルド
  Widget _buildReceivedLikeCard(Map<String, dynamic> like) {
    final deviceName = like['device_name'] as String;
    final macAddress = like['mac_address'] as String;
    final detectionCount = like['detection_count'] as int;
    final receivedAt = DateTime.parse(like['received_at'] as String);
    
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFFFFE0E6),
            Color(0xFFFFF0F5),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.pink.withOpacity(0.3)),
        boxShadow: [
          BoxShadow(
            color: Colors.pink.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ヘッダー部分
            Row(
              children: [
                Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      colors: [Colors.pink, Colors.purple],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.pink.withOpacity(0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.bluetooth,
                    color: Colors.white,
                    size: 30,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        deviceName,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${detectionCount}回検出',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.favorite,
                  color: Colors.pink,
                  size: 28,
                ),
              ],
            ),
            
            const SizedBox(height: 12),
            
            // 運命メッセージ
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.7),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _getText('destiny_message'),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.pink,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _getText('destiny_subtitle'),
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[700],
                    ),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 16),
            
            // アクションボタン
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                      _likeBackDevice(like);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.pink,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(25),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.favorite, size: 20),
                        const SizedBox(width: 6),
                        Text(_getText('like_back')),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                      _passReceivedLike(like);
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.grey[600],
                      side: BorderSide(color: Colors.grey[300]!),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(25),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: Text(_getText('pass')),
                  ),
                ),
              ],
            ),
            
            // 受信時刻
            const SizedBox(height: 8),
            Text(
              '${receivedAt.month}/${receivedAt.day} ${receivedAt.hour}:${receivedAt.minute.toString().padLeft(2, '0')}',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[500],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // いいね返しを実行
  void _likeBackDevice(Map<String, dynamic> like) {
    final macAddress = like['mac_address'] as String;
    final deviceName = like['device_name'] as String;
    
    // いいね返しリストに追加
    if (!_likedDevices.contains(macAddress)) {
      _likedDevices.add(macAddress);
    }
    
    // 受信リストから削除
    _receivedLikes.removeWhere((item) => item['mac_address'] == macAddress);
    
    // 確実にマッチング成立
    _createGuaranteedMatch(deviceName, macAddress);
    
    _logger.i("いいね返し実行: $deviceName");
    setState(() {});
  }

  // 確実マッチング成立とチャット開始
  Future<void> _createGuaranteedMatch(String deviceName, String macAddress) async {
    // マッチイベントを作成
    final matchEvent = {
      'device_name': deviceName,
      'mac_address': macAddress,
      'match_time': DateTime.now().toIso8601String(),
      'is_mutual': true,
    };
    
    _matchEvents.add(matchEvent);
    
    // 両想い成立の演出
    _showMutualMatchDialog(deviceName, macAddress);
    
    // チャットルームを自動作成
    await _createChatRoomAndSendFirstMessage(deviceName, macAddress);
  }

  // チャットルーム作成と相手からの初回メッセージ送信
  Future<void> _createChatRoomAndSendFirstMessage(String deviceName, String macAddress) async {
    try {
      final chatRoomId = "${_myMac}_$macAddress";
      
      // チャットルームをデータベースに作成
      await _supabase.from('chat_rooms').upsert({
        'room_id': chatRoomId,
        'user_mac': _myMac,
        'partner_mac': macAddress,
        'partner_name': deviceName,
        'created_at': DateTime.now().toUtc().toIso8601String(),
        'last_message_time': DateTime.now().toUtc().toIso8601String(),
      });
      
      // 相手からの運命メッセージを送信
      final destinyMessages = [
        'こんなに会うなんて、もしかして運命？',
        '同じ場所でよく会いますね...これって運命かも？',
        'また会いましたね！これは偶然じゃない気がします',
        'こんなに近くにいるなんて...運命を感じます',
        'よく同じ場所にいますね。お話ししませんか？',
      ];
      
      final random = Math.Random();
      final selectedMessage = destinyMessages[random.nextInt(destinyMessages.length)];
      
      // メッセージをデータベースに保存
      await _supabase.from('chat_messages').insert({
        'room_id': chatRoomId,
        'sender_mac': macAddress, // 相手から送信
        'sender_name': deviceName,
        'message': selectedMessage,
        'timestamp': DateTime.now().toUtc().toIso8601String(),
        'message_type': 'text',
      });
      
      _logger.i("相手からの初回メッセージを送信: $selectedMessage");
      
    } catch (e) {
      _logger.e("チャットルーム作成エラー", error: e);
    }
  }

  // もらったいいねをパス
  void _passReceivedLike(Map<String, dynamic> like) {
    final macAddress = like['mac_address'] as String;
    final deviceName = like['device_name'] as String;
    
    // 受信リストから削除
    _receivedLikes.removeWhere((item) => item['mac_address'] == macAddress);
    
    _logger.i("受信いいねをパス: $deviceName");
    setState(() {});
  }

  // 両想い成立ダイアログを表示
  void _showMutualMatchDialog(String deviceName, String macAddress) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Colors.pink, Colors.purple],
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.pink.withOpacity(0.3),
                blurRadius: 20,
                spreadRadius: 5,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.favorite,
                color: Colors.white,
                size: 60,
              ),
              const SizedBox(height: 16),
              Text(
                _getText('mutual_match'),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                deviceName,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.of(context).pop();
                        _startChatFromMatch(deviceName, macAddress);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.pink,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(25),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: Text(_getText('chat_start')),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        Navigator.of(context).pop();
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.white),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(25),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: Text(_getText('close')),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // マッチからチャットを開始
  void _startChatFromMatch(String deviceName, String macAddress) {
    _currentPartnerName = _getDisplayName(macAddress, deviceName);
    _currentPartnerMac = macAddress;
    _currentChatRoomId = "${_myMac}_$macAddress";
    _isInChat = true;
    _messages.clear();
    
    // チャットルームを作成/取得
    _loadMessages();
    
    setState(() {});
  }

  // 位置情報分析画面を表示
  void _showLocationAnalysis() {
    if (_currentPosition == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_getText('no_location')),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

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
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                _getText('location_analysis'),
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            // コンテンツ
            Expanded(child: _buildLocationAnalysisContent()),
          ],
        ),
      ),
    );
  }

  Widget _buildLocationAnalysisContent() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _getFrequentDevicesAtLocation(
        _currentPosition!.latitude,
        _currentPosition!.longitude,
        0.1, // 100mの範囲
      ),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                Text(_getText('analyzing_location')),
              ],
            ),
          );
        }

        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error, size: 64, color: Colors.red),
                const SizedBox(height: 16),
                Text('${_getText('analysis_error')}: ${snapshot.error}'),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                  child: Text(_getText('close')),
                ),
              ],
            ),
          );
        }

        final frequentDevices = snapshot.data ?? [];

        if (frequentDevices.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.location_off, size: 64, color: Colors.grey),
                const SizedBox(height: 16),
                Text(
                  _getText('no_frequent_devices'),
                  style: const TextStyle(fontSize: 16, color: Colors.grey),
                ),
                const SizedBox(height: 8),
                Text(
                  _getText('scan_same_location'),
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          );
        }

        return Column(
          children: [
            // 位置情報表示
            Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.blue[200]!),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _getText('analysis_target_location'),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text('${_getText('latitude')}: ${_currentPosition!.latitude.toStringAsFixed(6)}'),
                  Text('${_getText('longitude')}: ${_currentPosition!.longitude.toStringAsFixed(6)}'),
                  Text('${_getText('accuracy')}: ${_currentPosition!.accuracy.toStringAsFixed(1)}m'),
                  Text('${_getText('frequent_devices')}: ${frequentDevices.length}${_getText('device_detected')}'),
                ],
              ),
            ),
            // 常連デバイスリスト
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: frequentDevices.length,
                itemBuilder: (context, index) {
                  final device = frequentDevices[index];
                  final macAddress = device['mac_address'] as String;
                  final occurrenceCount = device['occurrence_count'] as int;
                  final firstSeen = DateTime.parse(device['first_seen']);
                  final lastSeen = DateTime.parse(device['last_seen']);
                  
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: Colors.green[100],
                        child: Text(
                          occurrenceCount.toString(),
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.green,
                          ),
                        ),
                      ),
                      title: Text(
                        macAddress,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 14,
                        ),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${_getText('detection_count')}: $occurrenceCount${_getText('times')}'),
                          Text('${_getText('first_seen')}: ${_formatDateTime(firstSeen)}'),
                          Text('${_getText('last_seen')}: ${_formatDateTime(lastSeen)}'),
                        ],
                      ),
                      isThreeLine: true,
                      trailing: const Icon(Icons.wifi, color: Colors.blue),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  // 設定メニューを表示
  void _showSettingsMenu() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.4,
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
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                _getText('settings'),
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            // 設定項目
            Expanded(
              child: ListView(
                children: [
                  ListTile(
                    leading: Stack(
                      children: [
                        const Icon(Icons.favorite, color: Colors.pink),
                        if (_unreadLikesCount > 0)
                          Positioned(
                            right: 0,
                            top: 0,
                            child: Container(
                              width: 12,
                              height: 12,
                              decoration: const BoxDecoration(
                                color: Colors.red,
                                shape: BoxShape.circle,
                              ),
                              child: Center(
                                child: Text(
                                  _unreadLikesCount > 9 ? '9+' : _unreadLikesCount.toString(),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 8,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                    title: Text(_getText('received_likes')),
                    subtitle: Text(_unreadLikesCount > 0 
                        ? '$_unreadLikesCount${_getText('likes_count')}未読'
                        : _getText('received_likes_description')),
                    trailing: const Icon(Icons.arrow_forward_ios),
                    onTap: () {
                      Navigator.of(context).pop();
                      _showReceivedLikes();
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.language, color: Colors.blue),
                    title: Text(_getText('language_settings')),
                    subtitle: Text(_currentLanguage == 'ja' ? '日本語' : 'English'),
                    trailing: const Icon(Icons.arrow_forward_ios),
                    onTap: _showLanguageSettings,
                  ),
                  ListTile(
                    leading: const Icon(Icons.location_on, color: Colors.green),
                    title: Text(_getText('location_analysis')),
                    subtitle: Text(_getText('analyzing_location')),
                    trailing: const Icon(Icons.arrow_forward_ios),
                    onTap: () {
                      Navigator.of(context).pop();
                      _showLocationAnalysis();
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 言語設定画面を表示
  void _showLanguageSettings() {
    Navigator.of(context).pop(); // 設定メニューを閉じる
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_getText('language_settings')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Radio<String>(
                value: 'ja',
                groupValue: _currentLanguage,
                onChanged: (String? value) {
                  if (value != null) {
                    Navigator.of(context).pop();
                    _changeLanguage('ja');
                  }
                },
              ),
              title: Text(_getText('japanese')),
              onTap: () {
                Navigator.of(context).pop();
                _changeLanguage('ja');
              },
            ),
            ListTile(
              leading: Radio<String>(
                value: 'en',
                groupValue: _currentLanguage,
                onChanged: (String? value) {
                  if (value != null) {
                    Navigator.of(context).pop();
                    _changeLanguage('en');
                  }
                },
              ),
              title: const Text('English'),
              onTap: () {
                Navigator.of(context).pop();
                _changeLanguage('en');
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(_getText('close')),
          ),
        ],
      ),
    );
  }

  // 言語を変更
  void _changeLanguage(String language) {
    setState(() {
      _currentLanguage = language;
    });
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
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.grey[100]!,
            Colors.grey[50]!,
            Colors.white,
          ],
        ),
      ),
      child: SafeArea(
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
      ),
    );
  }

  // Tinder風のヘッダー
  Widget _buildTinderHeader() {
    // 未処理デバイス数を計算
    final unprocessedDevices = _detectedDevices.where((device) {
      final macAddress = device['mac_address'] as String;
      return !_likedDevices.contains(macAddress) &&
             !_nopedDevices.contains(macAddress);
    }).toList();
    final remainingCount = unprocessedDevices.length;
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        children: [
          Row(
            children: [
              // プロフィールアイコン
              GestureDetector(
                onTap: _showProfileScreen, // プロフィール画面への遷移
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
              // 自動スキャンオンオフボタン
              Tooltip(
                message: _autoScanEnabled ? _getText('auto_scan_on') : _getText('auto_scan_off'),
                child: GestureDetector(
                  onTap: () {
                    setState(() {
                      _autoScanEnabled = !_autoScanEnabled;
                    });
                    
                    if (_autoScanEnabled) {
                      _logger.i("自動スキャンを有効化");
                      // スキャン完了済みで自動スキャンを有効にした場合、すぐにスケジュール
                      if (!_isScanning) {
                        _scheduleNextAutoScan();
                      }
                    } else {
                      _logger.i("自動スキャンを無効化");
                      _autoScanTimer?.cancel();
                      setState(() {
                        _status = "スキャン完了 (${_detectedDevices.length}件検出) - 手動スキャンまたはスワイプしてください";
                      });
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: _autoScanEnabled ? Colors.green : Colors.grey[300],
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Icon(
                      _autoScanEnabled ? Icons.autorenew : Icons.pause,
                      color: _autoScanEnabled ? Colors.white : Colors.grey[600],
                      size: 20,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // 設定アイコン
              GestureDetector(
                onTap: _showSettingsMenu,
                child: const Icon(
                  Icons.tune,
                  color: Colors.grey,
                  size: 28,
                ),
              ),
            ],
          ),
          // デバイス数表示
          if (_totalDetectedDevices > 0)
            Container(
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.pink.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(15),
                border: Border.all(color: Colors.pink.withValues(alpha: 0.3)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.bluetooth_searching, color: Colors.pink, size: 16),
                  const SizedBox(width: 6),
                  Text(
                    '検出: $_totalDetectedDevices件 | 残り: $remainingCount件',
                    style: const TextStyle(
                      color: Colors.pink,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
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
        title: Text(_getText('settings')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.bluetooth_searching),
              title: Text(_getText('scan_start')),
              onTap: () {
                Navigator.of(context).pop();
                _startManualScan();
              },
            ),
            ListTile(
              leading: const Icon(Icons.info),
              title: Text(_getText('scan_status')),
              subtitle: Text(_status),
            ),
            ListTile(
              leading: const Icon(Icons.history),
              title: const Text('デバイス履歴'),
              subtitle: const Text('デバイス履歴をクリアします'),
              trailing: TextButton(
                onPressed: () {
                  setState(() {
                    _deviceLastDetected.clear();
                  });
                  _showMessage('デバイス履歴をクリアしました');
                },
                child: const Text('クリア'),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(_getText('close')),
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
            icon: Icons.person,
            color: Colors.purple,
            isSelected: false,
            onTap: _showProfileScreen,
          ),
          _buildBottomNavItem(
            icon: Icons.chat_bubble,
            color: Colors.green,
            isSelected: false,
            onTap: () => _showMatchHistory(),
          ),
          _buildBottomNavItem(
            icon: Icons.settings,
            color: Colors.grey,
            isSelected: false,
            onTap: _showSettingsMenu, // 設定メニュー
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

  // プロフィール画面を表示
  void _showProfileScreen() {
    final nameController = TextEditingController(text: _userProfileName);
    final ageController = TextEditingController(text: _userAge.toString());
    final bioController = TextEditingController(text: _userBio);

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
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Icon(Icons.person, color: Colors.purple),
                  const SizedBox(width: 8),
                  Text(
                    _getText('profile_edit'),
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            // フォーム
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // プロフィール画像
                    Center(
                      child: Container(
                        width: 100,
                        height: 100,
                        decoration: BoxDecoration(
                          color: Colors.grey[300],
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.person, size: 50, color: Colors.grey[600]),
                      ),
                    ),
                    const SizedBox(height: 24),
                    // 名前
                    Text(
                      _getText('name'),
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: nameController,
                      decoration: InputDecoration(
                        hintText: _getText('name_hint'),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        prefixIcon: const Icon(Icons.person_outline),
                      ),
                    ),
                    const SizedBox(height: 16),
                    // 年齢
                    Text(
                      _getText('age'),
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: ageController,
                      keyboardType: TextInputType.number,
                      textInputAction: TextInputAction.next,
                      decoration: InputDecoration(
                        hintText: _getText('age_hint'),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        prefixIcon: const Icon(Icons.cake_outlined),
                      ),
                    ),
                    const SizedBox(height: 16),
                    // 自己紹介
                    Text(
                      _getText('bio'),
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: bioController,
                      maxLines: 3,
                      textInputAction: TextInputAction.done,
                      decoration: InputDecoration(
                        hintText: _getText('bio_hint'),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        prefixIcon: const Icon(Icons.description_outlined),
                      ),
                    ),
                    const Spacer(),
                    // 保存ボタン
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: () {
                          // プロフィール情報を保存
                          setState(() {
                            _userProfileName = nameController.text.isNotEmpty 
                                ? nameController.text 
                                : "あなた";
                            _userAge = int.tryParse(ageController.text) ?? 20;
                            _userBio = bioController.text.isNotEmpty 
                                ? bioController.text 
                                : "よろしくお願いします！";
                          });
                          Navigator.of(context).pop();
                          _showMessage(_getText('profile_updated'));
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.purple,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(25),
                          ),
                        ),
                        child: Text(
                          _getText('save'),
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 検出デバイス一覧を表示
  void _showDetectedDevicesList() {
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
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Icon(Icons.bluetooth_searching, color: Colors.blue),
                  const SizedBox(width: 8),
                  Text(
                    '検出デバイス一覧 (${_detectedDevices.length}件)',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            // リスト
            Expanded(
              child: _detectedDevices.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.bluetooth_disabled, size: 64, color: Colors.grey),
                          const SizedBox(height: 16),
                          Text(
                            _getText('no_devices_detected'),
                            style: const TextStyle(fontSize: 16, color: Colors.grey),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: _detectedDevices.length,
                      itemBuilder: (context, index) {
                        final device = _detectedDevices[index];
                        final macAddress = device['mac_address'] as String;
                        final isLiked = _likedDevices.contains(macAddress);
                        final isNoped = _nopedDevices.contains(macAddress);
                        
                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            leading: _generateAvatar(macAddress, size: 40),
                            title: Text(_getDisplayName(macAddress, device['device_name'])),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('MAC: $macAddress'),
                                Text('RSSI: ${device['rssi']} dBm'),
                                Text('${_getText('detection_time')}: ${_formatDateTime(device['detected_at'])}'),
                              ],
                            ),
                            trailing: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (isLiked)
                                  const Icon(Icons.favorite, color: Colors.green, size: 20),
                                if (isNoped)
                                  const Icon(Icons.close, color: Colors.red, size: 20),
                                if (!isLiked && !isNoped)
                                  const Icon(Icons.radio_button_unchecked, color: Colors.grey, size: 20),
                              ],
                            ),
                            onTap: () async {
                              // デバイスをタップしてチャット開始
                              Navigator.of(context).pop();
                              if (!isLiked) {
                                // まだLikeしていない場合は自動でLike
                                _likeDevice(device);
                              } else {
                                // 既にLike済みの場合は直接チャット開始
                                await _startChatWithDevice(macAddress, _getDisplayName(macAddress, device['device_name']));
                              }
                            },
                          ),
                        );
                      },
                    ),
            ),
          ],
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
             Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                _getText('match_history'),
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
        ? Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.favorite_border, size: 64, color: Colors.grey),
                const SizedBox(height: 16),
                Text(
                  _getText('no_matches'),
                  style: const TextStyle(fontSize: 16, color: Colors.grey),
                ),
                const SizedBox(height: 8),
                Text(
                  _getText('match_info'),
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
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
                      Text('${_getText('match_time')}: ${_formatDateTime(matchedAt)}'),
                    ],
                  ),
                  isThreeLine: true,
                  trailing: IconButton(
                    icon: const Icon(Icons.chat, color: Colors.blue),
                    onPressed: () => _startChatWithDevice(
                      event['mac_address'],
                      _getDisplayName(event['mac_address'], event['device_name']),
                    ),
                    tooltip: _getText('start_chat'),
                  ),
                  onTap: () => _startChatWithDevice(event['mac_address'], _getDisplayName(event['mac_address'], event['device_name'])),
                ),
              );
            },
          );
  }

  String _formatDateTime(DateTime dateTime) {
    // 既にJSTで保存されているため、そのまま使用
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

  // アバターに対応する表示名のマッピング
  static const List<String> _avatarNames = [
    'KEI',    // avatar1.png
    'HIRO',   // avatar2.png
    'TOMO',   // avatar3.png
    'WATA',   // avatar4.png
    'YU',     // avatar5.png
  ];

  // MACアドレスからアバターインデックスを取得
  int _getAvatarIndex(String macAddress) {
    final hash = macAddress.hashCode.abs();
    return hash % _avatarImages.length;
  }

  // MACアドレスに基づいて表示名を生成する関数
  String _getDisplayName(String macAddress, String originalDeviceName) {
    final avatarIndex = _getAvatarIndex(macAddress);
    final avatarName = _avatarNames[avatarIndex];
    return '$avatarName($originalDeviceName)';
  }

  // 性格定義（拡張可能）
  static const Map<int, Map<String, dynamic>> _personalityTypes = {
    0: {
      'name': '攻撃的な人',
      'traits': ['短気', '気性が荒い', '暴言を吐く', 'タバコ好き'],
      'style': 'aggressive'
    },
    1: {
      'name': '色気のある人',
      'traits': ['セクシー', '大人の魅力', '誘惑的', '夜遊び好き'],
      'style': 'seductive'
    },
    2: {
      'name': '宗教勧誘の人',
      'traits': ['信仰深い', '宗教を勧める', '神について語る', '聖書を愛読'],
      'style': 'religious'
    },
  };

  // 話している風のアバターを生成（アニメーション付き）
  Widget _buildSpeakingAvatar(String macAddress, {double size = 50}) {
    return TweenAnimationBuilder<double>(
      duration: const Duration(milliseconds: 800),
      tween: Tween(begin: 1.0, end: 1.1),
      builder: (context, scale, child) {
        return TweenAnimationBuilder<double>(
          duration: const Duration(milliseconds: 600),
          tween: Tween(begin: 1.1, end: 1.0),
          onEnd: () {
            // アニメーションを繰り返すために状態を更新
            if (mounted) {
              setState(() {}); 
            }
          },
          builder: (context, reverseScale, child) {
            return Transform.scale(
              scale: scale * reverseScale,
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.pink.withValues(alpha: 0.3),
                      blurRadius: 6,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: _generateAvatar(macAddress, size: size),
              ),
            );
          },
        );
      },
    );
  }

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
    // 未処理デバイスのみを表示
    final unprocessedDevices = _detectedDevices.where((device) {
      final macAddress = device['mac_address'] as String;
      return !_likedDevices.contains(macAddress) &&
             !_nopedDevices.contains(macAddress);
    }).toList();

    if (unprocessedDevices.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.bluetooth_searching, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            Text(
              _getText('searching_devices'),
              style: const TextStyle(fontSize: 16, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            Text(
              _getText('swipe_instruction'),
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 32),
            // スキャンボタンを中央に追加
            SizedBox(
              width: 200,
              height: 50,
              child: ElevatedButton.icon(
                onPressed: _isScanning ? null : _startManualScan,
                icon: Icon(_isScanning ? Icons.hourglass_empty : Icons.bluetooth_searching),
                label: Text(_isScanning ? _getText('scanning') : _getText('scan_start')),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.pink,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(25),
                  ),
                  elevation: 3,
                ),
              ),
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
          onTap: () async {
            // カードをタップして直接チャットに移る
            if (!_isDragging) {
              _likeDevice(currentDevice); // 自動的にLikeしてからチャットに移る
            }
          },
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
                          _getDisplayName(device['mac_address'], device['device_name']),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      Text(
                        '${device['rssi']}dBm', // RSSI値をそのまま表示
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
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
    final unprocessedDevices = _detectedDevices.where((device) {
      final macAddress = device['mac_address'] as String;
      return !_likedDevices.contains(macAddress) &&
             !_nopedDevices.contains(macAddress);
    }).toList();

    if (unprocessedDevices.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            // 戻るボタン（Nopeデバイスが有る場合のみ有効）
            _buildActionButton(
              icon: Icons.replay,
              color: _lastNopedDevice != null ? Colors.amber : Colors.grey,
              size: 50,
              onTap: _lastNopedDevice != null ? _undoLastNope : null,
            ),
            // アイテムボタン
            _buildActionButton(
              icon: Icons.shopping_bag,
              color: Colors.purple,
              size: 50,
              onTap: _showItemShop,
            ),
          ],
        ),
      );
    }

    final currentDevice = unprocessedDevices[_currentDeviceIndex];

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // 戻るボタン（1回前のNopeを復活）
          _buildActionButton(
            icon: Icons.replay,
            color: _lastNopedDevice != null ? Colors.amber : Colors.grey,
            size: 50,
            onTap: _lastNopedDevice != null ? _undoLastNope : null,
          ),
          // Nope
          _buildActionButton(
            icon: Icons.close,
            color: Colors.red,
            size: 60,
            onTap: () => _nopeDevice(currentDevice),
          ),
          // 検出デバイス一覧
          _buildActionButton(
            icon: Icons.list,
            color: Colors.blue,
            size: 50,
            onTap: _showDetectedDevicesList,
          ),
          // Like
          _buildActionButton(
            icon: Icons.favorite,
            color: Colors.green,
            size: 60,
            onTap: () => _likeDevice(currentDevice),
          ),
          // アイテムボタン
          _buildActionButton(
            icon: Icons.shopping_bag,
            color: Colors.purple,
            size: 50,
            onTap: _showItemShop,
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required Color color,
    required double size,
    required VoidCallback? onTap,
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
              color: Colors.black.withValues(alpha: onTap != null ? 0.1 : 0.05),
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
    
    await _startChatWithDevice(partnerMac, _getDisplayName(partnerMac, partnerName));
  }
  
  // 指定されたデバイスとチャットを開始する
  Future<void> _startChatWithDevice(String partnerMac, String partnerName) async {
    // Supabase設定チェック
    if (!_isSupabaseConfigured()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("${_getText('chat_start_failed')}: Supabase is not configured (.env)"),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }
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
      
      // チャット画面用BGMを開始
      _startChatBGM();
      
      // 親密度ボーナスを適用（Super Likeなど）
      final intimacyBonus = _deviceIntimacyBonus[partnerMac] ?? 0;
      if (intimacyBonus > 0) {
        _intimacyLevels[response as String] = intimacyBonus;
        _logger.i("親密度ボーナス適用: $intimacyBonus");
      }
      
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
            content: Text("${_getText('chat_start_failed')}: ${e.toString()}"),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
  
  // メッセージを読み込む
  Future<void> _loadMessages() async {
    if (_currentChatRoomId == null) return;
    if (!_isSupabaseConfigured()) return;
    
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
    if (!_isSupabaseConfigured()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("${_getText('message_send_failed')}: Supabase is not configured (.env)"),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }
    
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
      
      // チャット履歴の一番下にスクロール
      _scrollToBottom();
      
      // メッセージ数をカウント（感情分析含む）
      await _incrementMessageCount(message);
      
      // 自動返信を送信（1-3秒後）
      _scheduleAutoReply(message);
      
    } catch (e) {
      _logger.e("メッセージ送信エラー", error: e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("${_getText('message_send_failed')}: ${e.toString()}"),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
  
  // AI自動返信をスケジュール
  void _scheduleAutoReply(String userMessage) {
    if (_currentChatRoomId == null || _currentPartnerMac == null) return;
    
    // ブロック状態の場合は返信しない
    if (_blockedUsers.contains(_currentPartnerMac!)) {
      _logger.i("ブロック状態のため返信をスキップ: ${_currentPartnerMac!}");
      return;
    }
    
    // 2-5秒後にランダムで返信（AI生成のため少し長めに）
    final delay = Duration(seconds: 2 + (DateTime.now().millisecondsSinceEpoch % 4));
    
    Timer(delay, () async {
      if (!_isInChat) return; // チャット画面を離れている場合はスキップ
      
      // APIキーが設定されていない場合はフォールバック
      String replyMessage;
      if (_geminiApiKey == 'YOUR_GEMINI_API_KEY_HERE' || _geminiApiKey.isEmpty) {
        _logger.w("Gemini APIキーが設定されていないため、フォールバック返信を使用");
        replyMessage = _generateFallbackReply(userMessage);
      } else {
        // AI返信を生成
        replyMessage = await _generateAIReply(userMessage);
      }
      
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
        
        // チャット履歴の一番下にスクロール
        _scrollToBottom();
        
        // 相手の返信後に告白イベントをチェック
        _checkConfessionEvent();
        
      } catch (e) {
        _logger.e("自動返信エラー", error: e);
      }
    });
  }

  bool _isSupabaseConfigured() {
    String norm(String raw) {
      var v = (raw).trim();
      if (v.length >= 2) {
        if ((v.startsWith('"') && v.endsWith('"')) || (v.startsWith('\'') && v.endsWith('\''))) {
          v = v.substring(1, v.length - 1).trim();
        }
      }
      return v;
    }
    // 優先: main() で確定したAppConfig値
    var url = norm(AppConfig.supabaseUrl);
    var key = norm(AppConfig.supabaseAnonKey);
    if (url.isEmpty || key.isEmpty) {
      // フォールバック: dotenv
      url = norm(dotenv.env['SUPABASE_URL'] ?? '');
      key = norm(dotenv.env['SUPABASE_ANON_KEY'] ?? '');
    }
    return (url.startsWith('http://') || url.startsWith('https://')) && key.isNotEmpty;
  }
  
  // MACアドレスから性格タイプを取得
  Map<String, dynamic> _getPersonalityFromMac(String macAddress) {
    return PersonalityService().getPersonalityFromMac(macAddress);
  }

  // 性格別の返信パターン
  static const Map<String, Map<String, List<String>>> _replyPatterns = {
    'gentle': {
      'greeting': [
        'こんにちは😊',
        'お会いできて嬉しいです✨',
        'はじめまして🌸',
      ],
      'question': [
        'いい質問ですね😌',
        'どう思いますか？😊',
        '一緒に考えてみましょう🌿',
      ],
      'positive': [
        '素敵ですね✨',
        '嬉しいです💕',
        'ありがとうございます😊',
      ],
      'tired': [
        'お疲れさまです☕',
        '無理しないでくださいね🍀',
        '少し休みましょう😌',
      ],
      'default': [
        'そうなんですね😊',
        'なるほど✨',
        'わかります🌸',
      ],
    },
    'cool': {
      'greeting': ['やあ😎', 'どうも👍', 'こんにちは'],
      'question': ['なるほど🤔', '面白いね', '確認してみるよ'],
      'positive': ['いいね👍', '悪くない', '良い感じだ'],
      'tired': ['休もうか', '無理は禁物だよ', '落ち着いていこう'],
      'default': ['ふむ', '了解', 'OK'],
    },
    'cute': {
      'greeting': ['やっほ〜🥰', 'こんにちは〜💕', 'はじめまして〜🌸'],
      'question': ['どうしよ〜？😊', '一緒に考えよ〜✨', 'わくわくしちゃう！'],
      'positive': ['わ〜い！嬉しい〜💖', 'すてきっ✨', 'ありがと〜🥰'],
      'tired': ['がんばったね〜😌', 'ゆっくり休んでね☕', 'えらいよ〜💮'],
      'default': ['うんうん😊', 'えへへ💕', 'なるほど〜🌟'],
    },
    'cheerful': {
      'greeting': ['やっほー！😆', 'こんにちは！🎉', '元気？✨'],
      'question': ['いいね！やってみよう！', '考えるだけでワクワク！', '最高だね！'],
      'positive': ['サイコー！🎉', '最高にハッピー！', 'うれしい〜！✨'],
      'tired': ['ファイト！💪', '一緒にがんばろ！', 'ちょっと休憩ね！'],
      'default': ['いい感じ！', '了解！', 'OK！'],
    },
    'shy': {
      'greeting': ['あ…こんにちは😳', 'よ、よろしくです…💦', 'はじめまして…☺️'],
      'question': ['えっと…どうかな…', '少し考えさせて…', 'うん…たぶん…'],
      'positive': ['う、嬉しい…😊', 'ありがとう…！', 'よかった…✨'],
      'tired': ['だ、大丈夫…？', '無理しないでね…', '休もう…？'],
      'default': ['うん…', 'そうだね…', 'なるほど…'],
    },
    'mysterious': {
      'greeting': ['ごきげんよう🌙', '運命を感じますね🔮', '面白い出会いです✨'],
      'question': ['それは…秘密かも', '月が教えてくれるかも🌙', '直感的には…'],
      'positive': ['良い兆しです✨', '星々も微笑んでいます🌟', '不思議と嬉しいですね'],
      'tired': ['夜風に当たりましょう', '静寂が癒してくれます', '時間が解決しますよ'],
      'default': ['ふふ…', '面白いですね', 'なるほど…'],
    },
    'energetic': {
      'greeting': ['うおー！元気！？💪', 'やっていこう！🔥', 'よっしゃ！✨'],
      'question': ['いいね！挑戦しよう！', 'やるしかない！', '楽しもう！'],
      'positive': ['最高！⚡', 'テンション上がる！', 'ナイス！'],
      'tired': ['休憩してパワーチャージ！', '無理は禁物！', '水分補給！'],
      'default': ['OK！', '任せて！', 'いける！'],
    },
    'intellectual': {
      'greeting': ['こんにちは。議論しますか？📚', 'ご機嫌よう🤓', '興味深い出会いですね'],
      'question': ['仮説を立てましょう', 'データが必要ですね', '合理的に考えましょう'],
      'positive': ['有意義ですね', '統計的にも良好です', '知的に面白いです'],
      'tired': ['休息は生産性を上げます', '少しインターバルを', '睡眠は最良の投資です'],
      'default': ['合理的です', 'なるほど', '検討しましょう'],
    },
    'aggressive': {
      'greeting': [
        "チッ、何だよ💢 挨拶とかダルいんだよ",
        "うぜぇな...何の用だよ😠",
        "はあ？何しに来たんだよ💢",
        "ダルい...話があるなら早く言えよ😤",
      ],
      'question': [
        "知らねーよそんなもん💢",
        "うぜぇな...適当に決めろよ😠",
        "チッ、面倒くせぇ質問だな💢",
        "どうでもいいだろそんなこと😤",
      ],
      'positive': [
        "はあ？何が嬉しいんだよ💢",
        "チッ、調子に乗んなよ😠",
        "うるせぇな...くだらねぇ💢",
        "ダルい話だな😤",
      ],
      'tired': [
        "当たり前だろ💢 甘えんなよ",
        "疲れた？知るかよ😠",
        "チッ、弱すぎだろ💢",
      ],
      'default': [
        "チッ、うぜぇ💢",
        "ダルいな😠",
        "知らねーよ💢",
        "はあ？😤",
        "どうでもいいだろ💢",
      ],
    },
    'seductive': {
      'greeting': [
        "あらぁ〜♡ こんばんは😘 素敵な出会いね💋",
        "うふふ♡ 近くにいたのね🔥 運命かしら？💕",
        "あらあら♡ 初めまして😘 よろしくね💋",
        "こんばんは♡ いい夜になりそうね🔥",
      ],
      'question': [
        "あらぁ〜♡ 興味深い質問ね😘",
        "うふふ♡ そんなこと聞いちゃうの？💋",
        "秘密よ♡ でも...特別に教えてあげる🔥",
        "いい質問ね♡ もっと深く話しましょう💕",
      ],
      'positive': [
        "あらぁ〜♡ 嬉しいわ😘💋",
        "うふふ♡ そんなこと言って...照れちゃう🔥",
        "素敵ね♡ もっと褒めて💕",
        "ありがとう♡ あなたも素敵よ😘",
      ],
      'tired': [
        "あらぁ〜♡ お疲れ様😘",
        "疲れてるの？♡ 癒してあげる💋",
        "うふふ♡ 疲れた体をほぐしてあげましょうか🔥",
      ],
      'default': [
        "あらぁ〜♡ そうなの😘",
        "うふふ♡ 面白いわね💋",
        "素敵ね♡🔥",
        "そうなの♡ 興味深いわ💕",
        "あらそう♡😘",
      ],
    },
    'religious': {
      'greeting': [
        "神のご加護がありますように🙏 はじめまして✨",
        "神様が素晴らしい出会いをくださいました🕊️ 感謝です💒",
        "主の平和がありますように🙏 よろしくお願いします",
        "神の愛に包まれた出会いですね✨ 祝福します🙏",
      ],
      'question': [
        "それは神様がお導きくださるでしょう🙏",
        "聖書にも答えが書かれていますよ✨ 一緒に読みませんか？",
        "祈りを捧げれば答えが見つかりますよ🕊️",
        "神様がお教えくださいます🙏 信仰を持ちましょう💒",
      ],
      'positive': [
        "神様に感謝ですね🙏✨",
        "それは神の恵みです🕊️ ハレルヤ💒",
        "素晴らしい！神様がお喜びです🙏",
        "神の愛を感じますね✨ 祈りましょう🕊️",
      ],
      'tired': [
        "神様があなたに力をお与えくださいます🙏",
        "祈りによって癒されますよ✨ 一緒に祈りましょう🕊️",
        "神の愛があなたを支えてくださいます💒",
      ],
      'default': [
        "神様のお導きですね🙏",
        "それも神のご計画です✨",
        "祈りましょう🕊️",
        "神に感謝🙏",
        "主の御心のままに💒",
      ],
    },
    'researcher': {
      'greeting': [
        "興味深い邂逅ですね📊 データ的に稀な確率です",
        "統計学的に見て面白い出会いです📈 研究しませんか？🔬",
        "こんにちは📊 人間関係の形成過程を観察したいですね",
        "初回接触データを記録します📈 よろしくお願いします🧪",
      ],
      'question': [
        "興味深い質問ですね📊 論文のテーマになりそうです",
        "データが必要ですね📈 統計的分析をしてみましょう🔬",
        "研究対象として最適ですね🧪 実験してみませんか？",
        "仮説検証が必要です📊 一緒に研究しましょう📈",
      ],
      'positive': [
        "データとして記録します📊 興味深い反応ですね",
        "統計的に有意な結果です📈 論文にまとめましょう🔬",
        "素晴らしいサンプルです🧪 継続観察したいですね",
        "研究成果として発表したいですね📊📈",
      ],
      'tired': [
        "疲労度のデータを取りたいですね📊",
        "ストレス反応の研究対象として興味深いです📈",
        "休息の効果について研究しませんか？🔬🧪",
      ],
      'default': [
        "データとして記録します📊",
        "統計的に興味深いですね📈",
        "研究してみましょう🔬",
        "論文のネタになりそうです🧪",
        "分析が必要ですね📊",
      ],
    },
    'kansai': {
      'greeting': [
        "よお〜😂 元気にしとったか〜？なんでやねん！",
        "おお〜🤣 近くにおったんか〜 そやかて工場長〜",
        "はじめまして〜😆 ワイはたこ焼き大好きやねん〜",
        "よろしゅう〜🥴 関西弁でええか〜？なんでやねん！",
      ],
      'question': [
        "そやなぁ〜😂 知るかいな〜 なんでやねん！",
        "ほんまに〜🤣 考えても分からんで〜",
        "そやかて〜😆 質問が難しすぎるやん〜",
        "う〜ん🥴 たこ焼き食べながら考えよか〜",
      ],
      'positive': [
        "ほんまに〜😂 嬉しいわぁ〜 なんでやねん！",
        "そやかて〜🤣 めっちゃええやん〜",
        "おお〜😆 最高やで〜 たこ焼きみたいや〜",
        "ええなぁ〜🥴 ワイも嬉しいで〜",
      ],
      'tired': [
        "ほんまに〜😂 お疲れはんやなぁ〜",
        "そやかて〜🤣 疲れとんのか〜 たこ焼き食べ〜",
        "大変やったなぁ〜😆 ゆっくり休み〜",
      ],
      'default': [
        "そやなぁ〜😂",
        "ほんまに〜🤣",
        "なんでやねん😆",
        "そやかて〜🥴",
        "おもろいやん〜😂",
      ],
    },
  };

  // Google Gemini APIを呼び出してAI返信を生成
  Future<String> _generateAIReply(String userMessage) async {
    if (_currentPartnerMac == null || _currentChatRoomId == null) {
      return _currentLanguage == 'en' ? "Thank you😊" : "ありがとうございます😊";
    }
    
    try {
      final personality = _getPersonalityFromMac(_currentPartnerMac!);
      final style = personality['style'] as String;
      final systemPrompt = _personalityPrompts[style]?[_currentLanguage] ?? 
                          _personalityPrompts[style]?['ja'] ?? 
                          _personalityPrompts['gentle']![_currentLanguage] ??
                          _personalityPrompts['gentle']!['ja']!;
      
      // 会話履歴を初期化（存在しない場合）
      _conversationHistory[_currentChatRoomId!] ??= [];
      
      // 会話履歴に新しいメッセージを追加
      _conversationHistory[_currentChatRoomId!]!.add({
        'role': 'user',
        'content': userMessage,
      });
      
      // 会話履歴が長すぎる場合は古いものを削除（最新10件まで保持）
      if (_conversationHistory[_currentChatRoomId!]!.length > 10) {
        _conversationHistory[_currentChatRoomId!] = 
            _conversationHistory[_currentChatRoomId!]!.sublist(
                _conversationHistory[_currentChatRoomId!]!.length - 10);
      }
      
      // 言語に基づいてプロンプトを作成
      final String languageInstruction = _currentLanguage == 'en' ? 
          'Respond in natural English according to your personality.' :
          'あなたの性格に合った自然な返事をしてください。';
      
      final String conversationContext = _currentLanguage == 'en' ?
          'Here is the conversation history. Please understand this context and respond naturally according to your personality:\n\n' :
          '以下は今までの会話の履歴です。この文脈を理解して、あなたの性格に合った自然な返事をしてください。\n\n';
      
      final String userLabel = _currentLanguage == 'en' ? 'User' : 'ユーザー';
      final String youLabel = _currentLanguage == 'en' ? 'You' : 'あなた';
      
      // Gemini APIリクエストを構築
      final requestBody = {
        'contents': [
          {
            'parts': [
              {
                'text': systemPrompt + '\n\n' + languageInstruction + '\n\n' +
                       conversationContext +
                       _conversationHistory[_currentChatRoomId!]!
                           .map((msg) => '${msg['role'] == 'user' ? userLabel : youLabel}: ${msg['content']}')
                           .join('\n') +
                       '\n\n$userLabel: $userMessage\n$youLabel: '
              }
            ]
          }
        ],
        'generationConfig': {
          'temperature': 0.9,
          'topK': 1,
          'topP': 1,
          'maxOutputTokens': 200,
        },
        'safetySettings': [
          {
            'category': 'HARM_CATEGORY_HARASSMENT',
            'threshold': 'BLOCK_MEDIUM_AND_ABOVE'
          },
          {
            'category': 'HARM_CATEGORY_HATE_SPEECH',
            'threshold': 'BLOCK_MEDIUM_AND_ABOVE'
          }
        ]
      };
      
      // API呼び出し
      final response = await http
          .post(
        Uri.parse(_geminiApiUrl),
        headers: {
          'Content-Type': 'application/json',
          'x-goog-api-key': _geminiApiKey,
        },
        body: json.encode(requestBody),
      )
          .timeout(const Duration(seconds: 15));
      
      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        final candidates = responseData['candidates'];
        if (candidates is List && candidates.isNotEmpty) {
          final content = candidates[0]['content'];
          if (content != null && content['parts'] is List && content['parts'].isNotEmpty) {
            final aiReply = content['parts'][0]['text']?.toString() ?? '';
            if (aiReply.trim().isNotEmpty) {
              // 会話履歴にAIの返信を追加
              _conversationHistory[_currentChatRoomId!]!.add({
                'role': 'assistant',
                'content': aiReply,
              });
              _logger.i("AI返信生成成功: $aiReply");
              return aiReply.trim();
            }
          }
          // candidatesはあるが中身がフィルタで空のケース
          _logger.w("Gemini応答にテキストが含まれないためフォールバックします: ${response.body}");
          return _generateFallbackReply(userMessage);
        }
        
        _logger.w("Gemini応答にcandidatesが含まれないためフォールバックします: ${response.body}");
        return _generateFallbackReply(userMessage);
        
      } else {
        _logger.e("Gemini API エラー: ${response.statusCode} - ${response.body}");
        return _generateFallbackReply(userMessage);
      }
      
    } catch (e) {
      _logger.e("AI返信生成エラー", error: e);
      return _generateFallbackReply(userMessage);
    }
  }
  
  // 話題選択による返信を生成
  String _generateTopicReply(String topic) {
    if (_currentPartnerMac == null) return _currentLanguage == 'en' ? "Thank you😊" : "ありがとうございます😊";
    
    final personality = _getPersonalityFromMac(_currentPartnerMac!);
    final style = personality['style'] as String;
    
    // 4層構造での応答を検索: topic → language → personality → responses[]
    if (_topicResponses.containsKey(topic) && 
        _topicResponses[topic]!.containsKey(_currentLanguage) &&
        _topicResponses[topic]![_currentLanguage]!.containsKey(style)) {
      
      final responses = _topicResponses[topic]![_currentLanguage]![style]!;
      final randomIndex = DateTime.now().millisecondsSinceEpoch % responses.length;
      return responses[randomIndex];
    }
    
    // 言語が見つからない場合は日本語でフォールバック
    if (_topicResponses.containsKey(topic) && 
        _topicResponses[topic]!.containsKey('ja') &&
        _topicResponses[topic]!['ja']!.containsKey(style)) {
      
      final responses = _topicResponses[topic]!['ja']![style]!;
      final randomIndex = DateTime.now().millisecondsSinceEpoch % responses.length;
      return responses[randomIndex];
    }
    
    // 完全なフォールバック
    return _currentLanguage == 'en' ? "I see😊" : "そうですね😊";
  }
  
  // フォールバック用の固定返信（従来の方式）
  String _generateFallbackReply(String userMessage) {
    if (_currentPartnerMac == null) return _currentLanguage == 'en' ? "Thank you😊" : "ありがとうございます😊";
    
    final personality = _getPersonalityFromMac(_currentPartnerMac!);
    final style = personality['style'] as String;
    final patterns = _replyPatterns[style] ?? _replyPatterns['gentle']!;
    
    List<String> candidates = [];
    
    // 挨拶に対する返信
    if (userMessage.contains(RegExp(r'こんにちは|おはよう|こんばんは|はじめまして'))) {
      candidates.addAll(patterns['greeting']!);
    }
    // 質問に対する返信
    else if (userMessage.contains('？') || userMessage.contains('?')) {
      candidates.addAll(patterns['question']!);
    }
    // ポジティブな感情表現に対する返信
    else if (userMessage.contains(RegExp(r'嬉しい|楽しい|面白い|素敵|すごい|最高'))) {
      candidates.addAll(patterns['positive']!);
    }
    // 疲労・大変さに対する返信
    else if (userMessage.contains(RegExp(r'疲れた|大変|忙しい|しんどい'))) {
      candidates.addAll(patterns['tired']!);
    }
    // デフォルトの返信
    else {
      candidates.addAll(patterns['default']!);
    }
    
    // ランダムに選択（空の場合の保険も追加）
    if (candidates.isEmpty) {
      return _currentLanguage == 'en' ? 'Thank you😊' : 'ありがとうございます😊';
    }
    final randomIndex = DateTime.now().millisecondsSinceEpoch % candidates.length;
    return candidates[randomIndex];
  }
  
  // 告白への固定返信を生成（フォールバック用）
  String _generateConfessionFallbackReply(bool isAccepted, String style) {
    if (isAccepted) {
      // YES の場合の返答（性格に応じて）
      final yesResponses = {
        'energetic': [
          'わあ〜！私も同じ気持ちです〜！！💕✨',
          'やった〜！嬉しい〜！！私もあなたのこと好きです〜💖🎉',
          'え〜！本当ですか〜？！私もです〜！！😆💕',
        ],
        'gentle': [
          '私も...同じ気持ちです💕',
          'ありがとうございます。私もあなたとお話しするのが楽しくて...😊💖',
          'そう言ってくださって嬉しいです。私も同じ気持ちです🌸',
        ],
        'cool': [
          '...私もそう思っていました。',
          'そうですね。私も同感です。',
          'やっと言ってくれましたね。私も同じです。',
        ],
        'cute': [
          'わ〜い💕私もあなたのこと大好きです〜😊',
          'え〜嬉しい〜！私もずっと同じこと思ってました〜💖',
          'やった〜！私もあなたとずっと一緒にいたいです〜✨',
        ],
        'serious': [
          'ありがとうございます。私も同じ気持ちでした。',
          'そのようなお気持ちをいただけて光栄です。私も同感です。',
          '真摯なお気持ちをありがとうございます。私もです。',
        ],
      };
      
      final responses = yesResponses[style] ?? yesResponses['gentle']!;
      return responses[DateTime.now().millisecondsSinceEpoch % responses.length];
      
    } else {
      // NO の場合の返答（性格に応じて）
      final noResponses = {
        'energetic': [
          'ごめんなさい〜💦でもお友達としてはとっても楽しいです〜！',
          'あ〜ごめんなさい〜😅でも今のままの関係が好きです〜',
          'わ〜嬉しいけど...もう少し時間をください〜💦',
        ],
        'gentle': [
          'お気持ちはとても嬉しいのですが...💦',
          'ありがとうございます。でも今はお友達として...😌',
          'そのお気持ちは嬉しいのですが、もう少し時間をいただけませんか？',
        ],
        'cool': [
          'すみませんが...そのような気持ちにはなれません。',
          'お気持ちはありがたいですが。',
          '申し訳ありませんが、今はそう思えません。',
        ],
        'cute': [
          'ごめんなさい〜💦でもお友達でいてくださいね〜😊',
          'え〜どうしよう〜💦もう少し考えさせてください〜',
          'お気持ちは嬉しいけど...今はまだ〜😅',
        ],
        'serious': [
          '申し訳ございませんが、そのようなお気持ちにお応えできません。',
          'お気持ちはありがたいのですが、お友達として付き合わせていただけませんでしょうか。',
          '真摯なお気持ちをいただきましたが、申し訳ございません。',
        ],
      };
      
      final responses = noResponses[style] ?? noResponses['gentle']!;
      return responses[DateTime.now().millisecondsSinceEpoch % responses.length];
    }
  }
  
  // メッセージ数をカウントして親密度を更新し、告白イベントをチェック
  Future<void> _incrementMessageCount(String message) async {
    if (_currentChatRoomId == null) return;
    
    _messageCountPerRoom[_currentChatRoomId!] = 
        (_messageCountPerRoom[_currentChatRoomId!] ?? 0) + 1;
    
    // メッセージの感情分析を行う
    final sentiment = await _analyzeSentiment(message);
    
    // 感情に基づいて親密度を調整
    switch (sentiment) {
      case 'positive':
        // ポジティブなメッセージは親密度+2
        _intimacyLevels[_currentChatRoomId!] = 
            (_intimacyLevels[_currentChatRoomId!] ?? 0) + 2;
        _logger.i("ポジティブメッセージ: 親密度+2");
        if (mounted && _isInChat) {
          _showIntimacyChangeEffect(2, true);
        }
        break;
      case 'negative':
        // ネガティブなメッセージは親密度-3
        final currentIntimacy = _intimacyLevels[_currentChatRoomId!] ?? 0;
        _intimacyLevels[_currentChatRoomId!] = (currentIntimacy - 3).clamp(0, 100);
        _logger.i("ネガティブメッセージ: 親密度-3");
        
        if (mounted && _isInChat) {
          _showIntimacyChangeEffect(3, false);
        }
        break;
      default: // neutral
        // 通常のメッセージは親密度+1
        _intimacyLevels[_currentChatRoomId!] = 
            (_intimacyLevels[_currentChatRoomId!] ?? 0) + 1;
        _logger.i("ニュートラルメッセージ: 親密度+1");
        if (mounted && _isInChat) {
          _showIntimacyChangeEffect(1, true);
        }
        break;
    }
    
    // 告白イベントのチェックは相手の返信後に移動
  }
  
  // 親密度に基づいて告白イベントの発生をチェック
  void _checkConfessionEvent() {
    if (_currentChatRoomId == null || _isInConfessionEvent) return;
    
    final intimacy = _intimacyLevels[_currentChatRoomId!] ?? 0;
    
    // 親密度に基づく告白発生確率を計算
    // 親密度1: 5%, 親密度3: 15%, 親密度5: 25%, 親密度10: 50%, 親密度20: 100%
    double confessionProbability = _calculateConfessionProbability(intimacy);
    
    // ランダムで告白イベントを発生させる
    final random = DateTime.now().millisecondsSinceEpoch % 100;
    if (random < (confessionProbability * 100)) {
      _showConfessionPrompt();
    }
  }
  
  // 親密度に基づく告白発生確率を計算
  double _calculateConfessionProbability(int intimacy) {
    if (intimacy <= 0) return 0.0;
    if (intimacy >= 20) return 1.0; // 親密度20以上で100%
    
    // 親密度に応じて確率を段階的に上昇
    // y = 0.05 * intimacy + 0.02 * intimacy^1.5 の式を使用
    return (0.05 * intimacy + 0.02 * Math.pow(intimacy, 1.5)).clamp(0.0, 1.0);
  }
  
  // 親密度を増加させる
  Future<void> _increaseIntimacy(String partnerMac, int amount) async {
    if (_currentChatRoomId == null) return;
    
    final oldIntimacy = _intimacyLevels[_currentChatRoomId!] ?? 0;
    _intimacyLevels[_currentChatRoomId!] = oldIntimacy + amount;
    
    _logger.i("親密度を$amount増加: $_currentChatRoomId -> ${_intimacyLevels[_currentChatRoomId!]}");
    
    // 親密度変化のアニメーション効果
    if (mounted && _isInChat) {
      _showIntimacyChangeEffect(amount, true);
    }
  }

  // 親密度を減少させる
  Future<void> _decreaseIntimacy(String partnerMac, int amount) async {
    if (_currentChatRoomId == null) return;
    
    final currentIntimacy = _intimacyLevels[_currentChatRoomId!] ?? 0;
    _intimacyLevels[_currentChatRoomId!] = (currentIntimacy - amount).clamp(0, 100);
    
    _logger.i("親密度を$amount減少: $_currentChatRoomId -> ${_intimacyLevels[_currentChatRoomId!]}");
    
    // 親密度変化のアニメーション効果
    if (mounted && _isInChat) {
      _showIntimacyChangeEffect(amount, false);
    }
  }

  // チャット履歴の一番下までスクロール
  void _scrollToBottom() {
    if (_chatScrollController.hasClients) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _chatScrollController.animateTo(
          _chatScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      });
    }
  }

  // 親密度変化のアニメーション効果を表示
  void _showIntimacyChangeEffect(int amount, bool isIncrease) {
    if (!mounted) return;
    
    final message = isIncrease 
        ? "💝 親密度 +$amount" 
        : "💔 親密度 -$amount";
    final color = isIncrease ? Colors.pink : Colors.red;
    final icon = isIncrease ? Icons.favorite : Icons.heart_broken;
    
    // オーバーレイで一時的にアニメーション表示
    final overlay = Overlay.of(context);
    late OverlayEntry overlayEntry;
    
    overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        top: 120, // AppBarとintimacyBarの下
        left: 20,
        right: 20,
        child: Material(
          color: Colors.transparent,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeOutBack,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.3),
                  blurRadius: 8,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: Colors.white, size: 16),
                const SizedBox(width: 8),
                Text(
                  message,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    
    overlay.insert(overlayEntry);
    
    // 2秒後に自動削除
    Timer(const Duration(seconds: 2), () {
      overlayEntry.remove();
    });
  }

  // メッセージの感情分析を行う
  Future<String> _analyzeSentiment(String message) async {
    if (_geminiApiKey == 'YOUR_GEMINI_API_KEY_HERE' || _geminiApiKey.isEmpty) {
      // APIキーが設定されていない場合は簡単な条件判定
      return _simpleNegativeCheck(message);
    }

    try {
      final prompt = '''
このメッセージの感情を分析してください。以下の3つのカテゴリーのうち1つだけを返してください：
- "positive": ポジティブ、友好的、優しい、楽しい内容
- "neutral": 普通、事実的、特に感情的でない内容  
- "negative": ネガティブ、攻撃的、失礼、不適切な内容

メッセージ: "$message"

回答は"positive"、"neutral"、"negative"のいずれか1つだけを返してください。他の文字は含めないでください。
''';

      final response = await http
          .post(
        Uri.parse(_geminiApiUrl),
        headers: {
          'Content-Type': 'application/json',
          'x-goog-api-key': _geminiApiKey,
        },
        body: jsonEncode({
          'contents': [{
            'parts': [{'text': prompt}]
          }],
          'generationConfig': {
            'temperature': 0.1, // 低めの温度で一貫した分析結果を得る
            'maxOutputTokens': 10,
          }
        }),
      )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        String sentiment = '';
        if (data['candidates'] is List && (data['candidates'] as List).isNotEmpty) {
          final content = data['candidates'][0]['content'];
          if (content != null && content['parts'] is List && content['parts'].isNotEmpty) {
            sentiment = content['parts'][0]['text']?.toString().trim().toLowerCase() ?? '';
          }
        }
        if (sentiment.isEmpty) {
          _logger.w("感情分析: 応答にテキストがないためフォールバックします: ${response.body}");
          return _simpleNegativeCheck(message);
        }
        
        // 結果をクリーンアップ
        if (sentiment.contains('positive')) return 'positive';
        if (sentiment.contains('negative')) return 'negative';
        return 'neutral';
        
      } else {
        _logger.e("感情分析APIエラー: ${response.statusCode}");
        return _simpleNegativeCheck(message);
      }
    } catch (e) {
      _logger.e("感情分析エラー", error: e);
      return _simpleNegativeCheck(message);
    }
  }

  // 簡単なネガティブ検査（APIが使えない場合のフォールバック）
  String _simpleNegativeCheck(String message) {
    final negativeWords = [
      'バカ', 'アホ', 'クズ', 'うざい', 'きもい', 'しね', '死ね', 'むかつく', 
      'うざい', '嫌い', 'つまらない', 'くそ', 'クソ', 'やめろ', '消えろ',
      'ブス', 'ブサイク', '最悪', 'ゴミ', 'カス', 'ダサい', '無理', 
      '嫌だ', 'いらない', 'うんざり', 'しつこい', 'うるさい'
    ];
    
    final positiveWords = [
      'ありがとう', 'うれしい', '嬉しい', '楽しい', '面白い', '好き', 'かわいい',
      '素敵', '良い', 'いい', '最高', '素晴らしい', '感謝', 'すごい', '優しい'
    ];

    final lowerMessage = message.toLowerCase();
    
    // ネガティブワードをチェック
    for (String word in negativeWords) {
      if (lowerMessage.contains(word)) {
        return 'negative';
      }
    }
    
    // ポジティブワードをチェック
    for (String word in positiveWords) {
      if (lowerMessage.contains(word)) {
        return 'positive';
      }
    }
    
    return 'neutral';
  }

  // 親密度をリセット（告白失敗時に使用）
  void _resetIntimacy() {
    if (_currentChatRoomId == null) return;
    _intimacyLevels[_currentChatRoomId!] = 0;
    _logger.i("親密度をリセットしました: $_currentChatRoomId");
  }
  
  // 告白促進ダイアログを表示
  void _showConfessionPrompt() {
    if (!mounted || _isInConfessionEvent) return;
    
    final intimacy = _intimacyLevels[_currentChatRoomId!] ?? 0;
    
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
                '告白チャンス！！',
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
                    'やりとりが盛り上がってきましたね！\n親密度: $intimacy\n\n勇気を出して気持ちを伝えてみませんか？',
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
              _executeConfession();
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
  
  // 告白スロット演出を表示
  void _showConfessionRoulette() {
    // 結果を事前に計算してキャッシュ
    _confessionSuccess = _calculateConfessionSuccess();
    
    // アニメーションをリセットしてから開始
    _rouletteController.reset();
    _rouletteController.forward();
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => PopScope(
        canPop: false,
        child: Dialog(
          backgroundColor: Colors.black87,
          child: Container(
            height: 400,
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  "運命のスロット",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 20),
                _buildSlotMachine(),
                const SizedBox(height: 20),
                const Text(
                  "告白の結果は...？",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    
    // 3秒後にスロット結果を決定
    Timer(const Duration(seconds: 3), () {
      Navigator.of(context).pop(); // スロットダイアログを閉じる
      
      // 事前に計算された結果を使用
      final isAccepted = _confessionSuccess ?? false;
      
      setState(() {
        _confessionResult = isAccepted ? "yes" : "no";
      });
      
      _processConfessionResponse(isAccepted);
    });
  }
  
  // 親密度に基づいて告白成功率を計算（スロットマシン用）
  bool _calculateConfessionSuccess() {
    if (_currentPartnerMac == null) return false;
    
    // 現在の親密度を取得
    final intimacy = _intimacyLevels[_currentChatRoomId!] ?? 0;
    
    // 親密度に応じた成功率を計算
    // 親密度30で100%、0で基本20%、最大95%
    double successRate;
    if (intimacy >= 30) {
      successRate = 1.0; // 100%
    } else {
      // 線形補間：親密度0で20%、30で100%
      successRate = 0.2 + (intimacy / 30.0 * 0.8);
      successRate = successRate.clamp(0.2, 0.95); // 20%〜95%の範囲
    }
    
    // 成功率に基づいて結果を決定（スロットの見た目と一致させる）
    final random = DateTime.now().millisecondsSinceEpoch % 100;
    final success = random < (successRate * 100);
    
    _logger.i("告白成功率計算: 親密度=$intimacy, 成功率=${(successRate * 100).toInt()}%, 結果=$success");
    return success;
  }
  
  // スロットマシン演出ウィジェット
  Widget _buildSlotMachine() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.yellow, width: 3),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildSlotReel(isFixed: true, symbol: '7'), // 左側は既に7で固定
          _buildSlotReel(isFixed: false, symbol: '?'), // 真ん中だけ回転
          _buildSlotReel(isFixed: true, symbol: '7'), // 右側も既に7で固定
        ],
      ),
    );
  }

  // スロットのリール（筒）ウィジェット
  Widget _buildSlotReel({required bool isFixed, required String symbol}) {
    if (isFixed) {
      // 固定リール（既に7が表示されている）
      return Container(
        width: 60,
        height: 80,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.black, width: 2),
        ),
        child: Center(
          child: Text(
            '7',
            style: const TextStyle(
              fontSize: 40,
              fontWeight: FontWeight.bold,
              color: Colors.red,
            ),
          ),
        ),
      );
    } else {
      // 回転リール（真ん中）
      return AnimatedBuilder(
        animation: _rouletteAnimation,
        builder: (context, child) {
          String currentSymbol;
          
          if (_rouletteAnimation.isCompleted) {
            // アニメーション完了時は事前に計算された結果を使用
            final shouldSucceed = _confessionSuccess ?? false;
            currentSymbol = shouldSucceed ? '7' : '3'; // 成功時は7、失敗時は3
          } else {
            // アニメーション中はランダムにシンボルを変化
            final symbols = ['1', '2', '3', '4', '5', '6', '7', '8', '9'];
            final currentIndex = (_rouletteAnimation.value * symbols.length * 15).floor() % symbols.length;
            currentSymbol = symbols[currentIndex];
          }
          
          return Container(
            width: 60,
            height: 80,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.black, width: 2),
            ),
            child: Center(
              child: Text(
                currentSymbol,
                style: TextStyle(
                  fontSize: 40,
                  fontWeight: FontWeight.bold,
                  color: currentSymbol == '7' ? Colors.red : Colors.black,
                ),
              ),
            ),
          );
        },
      );
    }
  }

  // 告白を実行する
  Future<void> _executeConfession() async {
    if (_currentChatRoomId == null || _isInConfessionEvent) return;
    
    setState(() {
      _isInConfessionEvent = true;
      _confessionSuccess = null; // 結果をリセット
    });
    
    // 告白メッセージを送信
    final confessionMessages = [
      'いつもお話していて楽しいです！もしよろしければ、もっと親しくなりたいです💕',
      'あなたとのやりとりがとても楽しくて...気持ちを伝えたくて💖',
      'もしかして...私たち、相性いいかもしれませんね😊もっとお話したいです！',
      '勇気を出して言います！あなたともっと特別な関係になりたいです💝',
    ];
    
    final random = DateTime.now().millisecondsSinceEpoch % confessionMessages.length;
    final confessionMessage = confessionMessages[random];
    
    try {
      // 告白開始音を再生（通知の瞬間）
      _playConfessionStartSound();
      
      // 告白メッセージを送信
      await _supabase.rpc('send_message', params: {
        'room_id_param': _currentChatRoomId!,
        'sender_mac_param': _myMac,
        'sender_name_param': _myName,
        'message_param': confessionMessage,
        'message_type_param': 'confession',
      });
      
      await _loadMessages();
      
      // チャット履歴の一番下にスクロール
      _scrollToBottom();
      
      // 2-5秒後に相手からの返答
      final responseDelay = Duration(seconds: 2 + (DateTime.now().millisecondsSinceEpoch % 4));
      
      Timer(responseDelay, () async {
        if (!_isInConfessionEvent) return;
        
        // ルーレット演出を表示
        _showConfessionRoulette();
      });
      
    } catch (e) {
      _logger.e("告白メッセージ送信エラー", error: e);
      setState(() {
        _isInConfessionEvent = false;
      });
    }
  }
  
  // 告白への返答を処理
  Future<void> _processConfessionResponse(bool isAccepted) async {
    if (_currentChatRoomId == null || _currentPartnerMac == null) return;
    
    final personality = _getPersonalityFromMac(_currentPartnerMac!);
    final style = personality['style'] as String;
    
    String responseMessage;
    
    // AI返信を使用するか固定返信を使用するかを判定
    if (_geminiApiKey != 'YOUR_GEMINI_API_KEY_HERE' && _geminiApiKey.isNotEmpty) {
      // AI返信を生成
      try {
        final confessionPrompt = isAccepted 
            ? 'ユーザーから告白されて、あなたも同じ気持ちで受け入れる返事をしてください。嬉しい気持ちを表現してください。'
            : 'ユーザーから告白されましたが、お断りする返事をしてください。優しく丁寧に断ってください。';
        
        responseMessage = await _generateAIReply(confessionPrompt);
      } catch (e) {
        _logger.e("告白AI返信エラー", error: e);
        responseMessage = _generateConfessionFallbackReply(isAccepted, style);
      }
    } else {
      // 固定返信を使用
      responseMessage = _generateConfessionFallbackReply(isAccepted, style);
    }
    
    try {
      // 相手からの返答を送信
      await _supabase.rpc('send_message', params: {
        'room_id_param': _currentChatRoomId!,
        'sender_mac_param': _currentPartnerMac!,
        'sender_name_param': _currentPartnerName!,
        'message_param': responseMessage,
        'message_type_param': 'confession_response',
      });
      
      await _loadMessages();
      
      // チャット履歴の一番下にスクロール
      _scrollToBottom();
      
      // 結果の演出を表示
      if (isAccepted) {
        _showConfessionSuccessAnimation();
      } else {
        _showConfessionFailureAnimation();
        _resetIntimacy(); // 親密度をリセット
        
        // 告白失敗時にブロック状態にする
        if (_currentPartnerMac != null) {
          _blockedUsers.add(_currentPartnerMac!);
          _logger.i("告白失敗によりブロック状態: ${_currentPartnerMac!}");
        }
      }
      
    } catch (e) {
      _logger.e("告白返答送信エラー", error: e);
      setState(() {
        _isInConfessionEvent = false;
      });
    }
  }
  
  // 告白メッセージをテキストフィールドに挿入（互換性のために残す）
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

  // 告白成功時の動画演出
  void _showConfessionSuccessAnimation() {
    if (!mounted) return;
    
    // 成功音を再生
    _playSuccessSound();
    
    // フルスクリーン動画を表示
    // BGM は動画中は止め、終了後にチャットBGMを再開する
    _stopBGM();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => PopScope(
        canPop: false,
        child: FullscreenVideoWidget(
          videoPath: 'assets/videos/confession_success.mp4',
          autoDismissAfter: const Duration(seconds: 5), // 5秒後に自動で閉じる
          onVideoCompleted: () {
            Navigator.of(context).pop();
            // 動画終了後にチャットBGMを再開
            _startChatBGM();
            _showConfessionSuccessDialog(); // 動画後に従来のダイアログを表示
          },
        ),
      ),
    );
  }
  
  // 告白成功後のダイアログ（動画の後に表示）
  void _showConfessionSuccessDialog() {
    if (!mounted) return;
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => PopScope(
        canPop: false,
        child: AlertDialog(
          backgroundColor: Colors.black,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                "🎉 告白成功！ 🎉",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _generateAvatar(_currentPartnerMac ?? '', size: 50),
                  const SizedBox(width: 15),
                  const Icon(
                    Icons.favorite,
                    color: Colors.pink,
                    size: 40,
                  ),
                  const SizedBox(width: 15),
                  Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.person,
                      color: Colors.grey,
                      size: 30,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              const Text(
                "おめでとうございます！\n新しい恋愛が始まります💕",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                setState(() {
                  _isInConfessionEvent = false;
                });
              },
              child: const Text(
                'OK',
                style: TextStyle(color: Colors.pink),
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  // 告白失敗時の演出
  void _showConfessionFailureAnimation() {
    if (!mounted) return;
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => PopScope(
        canPop: false,
        child: AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          backgroundColor: Colors.grey[50],
          title: const Row(
            children: [
              Icon(Icons.heart_broken, color: Colors.grey, size: 28),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  '告白結果',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey,
                  ),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(color: Colors.grey[300]!, width: 2),
                ),
                child: Column(
                  children: [
                    const Icon(
                      Icons.sentiment_dissatisfied,
                      color: Colors.grey,
                      size: 60,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      '今回は残念でした...',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'でも大丈夫！\n親密度がリセットされましたが、\nまた一から関係を築いていけます。',
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
            ],
          ),
          actions: [
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                setState(() {
                  _isInConfessionEvent = false;
                  // 安定してチャット継続（画面リセット防止）
                  _isInChat = true;
                });
                // チャットBGMを維持
                _startChatBGM();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.grey,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(25),
                ),
              ),
              child: Text(_getText('fight_on')),
            ),
          ],
        ),
      ),
    );
  }
  
  // 話題選択ボタンを構築
  Widget _buildTopicButton(String topic, String label, IconData icon, Color color) {
    return Container(
      margin: const EdgeInsets.only(right: 8),
      child: ElevatedButton.icon(
        onPressed: () => _selectTopic(topic),
        icon: Icon(icon, size: 16),
        label: Text(
          label,
          style: const TextStyle(fontSize: 12),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: color.withValues(alpha: 0.1),
          foregroundColor: color,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: color.withValues(alpha: 0.3)),
          ),
        ),
      ),
    );
  }

  // 話題タグのラベル（多言語対応）
  String _getTopicLabel(String topic) {
    const labels = {
      'weather': {'ja': '天気', 'en': 'Weather'},
      'hobbies': {'ja': '趣味', 'en': 'Hobbies'},
      'food': {'ja': '食べ物', 'en': 'Food'},
      'future': {'ja': '将来', 'en': 'Future'},
      'memories': {'ja': '思い出', 'en': 'Memories'},
    };
    final lang = _currentLanguage;
    final map = labels[topic];
    if (map == null) return topic;
    return map[lang] ?? map['ja'] ?? topic;
  }
  
  // 話題を選択してユーザーが定型文を送信
  Future<void> _selectTopic(String topic) async {
    if (_currentChatRoomId == null || _currentPartnerMac == null) return;
    
    // ユーザーの定型文を取得（多言語対応）
    final topicMessages = _topicUserMessages[topic];
    if (topicMessages == null) return;
    
    final userMessage = topicMessages[_currentLanguage] ?? topicMessages['ja'];
    if (userMessage == null) return;
    
    try {
      // 1. まずユーザーが定型文を送信
      await _supabase.rpc('send_message', params: {
        'room_id_param': _currentChatRoomId!,
        'sender_mac_param': _myMac,
        'sender_name_param': _myName,
        'message_param': userMessage,
      });
      
      _logger.i("話題選択でユーザーが送信: $topic -> $userMessage");
      
      // 2. 親密度を増加（定型文でも感情分析を適用）
      await _incrementMessageCount(userMessage);
      
      // メッセージを即座に再読み込み
      await _loadMessages();
      
      // チャット履歴の一番下にスクロール
      _scrollToBottom();
      
      // 2. 少し待ってから相手の返答を送信
      Timer(const Duration(seconds: 2), () async {
        if (!_isInChat) return; // チャット画面を離れている場合はスキップ
        
        // ブロック状態の場合は返信しない
        if (_blockedUsers.contains(_currentPartnerMac!)) {
          _logger.i("ブロック状態のため定型文返信をスキップ: ${_currentPartnerMac!}");
          return;
        }
        
        // 事前準備済みの返信を生成（APIは使用しない）
        final replyMessage = _generateTopicReply(topic);
        
        try {
          await _supabase.rpc('send_message', params: {
            'room_id_param': _currentChatRoomId!,
            'sender_mac_param': _currentPartnerMac!,
            'sender_name_param': _currentPartnerName!,
            'message_param': replyMessage,
          });
          
          _logger.i("話題選択で相手が返信: $topic -> $replyMessage");
          
          // メッセージを再読み込み
          await _loadMessages();
          
          // チャット履歴の一番下にスクロール
          _scrollToBottom();
          
        } catch (e) {
          _logger.e("話題選択による相手の返信送信エラー", error: e);
        }
      });
      
    } catch (e) {
      _logger.e("話題選択によるユーザーメッセージ送信エラー", error: e);
      _showMessage("メッセージの送信に失敗しました");
    }
  }

  // チャットから戻る
  void _exitChat() {
    _messageRefreshTimer?.cancel();
    setState(() {
      _isInChat = false;
      _isInConfessionEvent = false; // 告白イベントもリセット
      _confessionResult = null;
      _currentChatRoomId = null;
      _currentPartnerMac = null;
      _currentPartnerName = null;
      _messages.clear();
    });
    
    // タイトル画面用BGMに戻す
    _startTitleBGM();
  }
  
  // 親密度バーを構築
  Widget _buildIntimacyBar() {
    final intimacy = _intimacyLevels[_currentChatRoomId] ?? 0;
    final maxIntimacy = 50; // 最大親密度を50に設定
    final progress = (intimacy / maxIntimacy).clamp(0.0, 1.0);
    
    // 親密度レベルに応じた色とテキスト
    Color barColor;
    String levelText;
    IconData levelIcon;
    
    if (intimacy >= 40) {
      barColor = Colors.red;
      levelText = "❤️ 恋人";
      levelIcon = Icons.favorite;
    } else if (intimacy >= 30) {
      barColor = Colors.pink;
      levelText = "💕 親友";
      levelIcon = Icons.favorite_border;
    } else if (intimacy >= 20) {
      barColor = Colors.orange;
      levelText = "🧡 友人";
      levelIcon = Icons.sentiment_satisfied;
    } else if (intimacy >= 10) {
      barColor = Colors.yellow;
      levelText = "💛 知人";
      levelIcon = Icons.sentiment_neutral;
    } else {
      barColor = Colors.grey;
      levelText = "🤝 初対面";
      levelIcon = Icons.sentiment_dissatisfied;
    }
    
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withValues(alpha: 0.3),
            blurRadius: 2,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(levelIcon, color: barColor, size: 16),
              const SizedBox(width: 8),
              Text(
                levelText,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: barColor,
                ),
              ),
              const Spacer(),
              Text(
                '$intimacy/$maxIntimacy',
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.grey,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            height: 8,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
              color: Colors.grey[200],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress,
                backgroundColor: Colors.transparent,
                valueColor: AlwaysStoppedAnimation<Color>(barColor),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // チャット画面を構築
  Widget _buildChatPage() {
    final personality = _currentPartnerMac != null 
        ? _getPersonalityFromMac(_currentPartnerMac!) 
        : null;
    
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            _generateAvatar(_currentPartnerMac ?? '', size: 35),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _currentPartnerName ?? '',
                    style: const TextStyle(fontSize: 18),
                  ),
                ],
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
          // アイテム使用ボタン
          PopupMenuButton<String>(
            icon: const Icon(Icons.inventory),
            onSelected: (itemId) => _useItem(itemId),
            itemBuilder: (context) {
              final availableItems = _ownedItems.entries
                  .where((entry) => entry.value > 0)
                  .toList();
              
              if (availableItems.isEmpty) {
                return [
                   PopupMenuItem(
                    value: '',
                    enabled: false,
                    child: Text(_getText('no_items_owned')),
                  ),
                ];
              }
              
              return availableItems.map((entry) {
                final itemId = entry.key;
                final count = entry.value;
                final item = _itemDefinitions[itemId]!;
                
                return PopupMenuItem(
                  value: itemId,
                  child: Row(
                    children: [
                      Icon(
                        _getIconFromString(item['icon']),
                        color: _getColorFromString(item['color']),
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${_getItemName(itemId)} ($count個)',
                          style: const TextStyle(fontSize: 14),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList();
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadMessages,
          ),
        ],
      ),
      body: Column(
        children: [
          // 親密度バー
          _buildIntimacyBar(),
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
                    controller: _chatScrollController,
                    padding: const EdgeInsets.all(16),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final message = _messages[index];
                      final isMyMessage = message['sender_name'] == _myName;
                      final sentAt = DateTime.parse(message['sent_at']).add(const Duration(hours: 9));
                      
                      return Container(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          mainAxisAlignment: isMyMessage 
                              ? MainAxisAlignment.end 
                              : MainAxisAlignment.start,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            // パートナーのメッセージの場合、アバターを表示
                            if (!isMyMessage) ...[
                              _buildSpeakingAvatar(_currentPartnerMac!, size: 40),
                              const SizedBox(width: 8),
                            ],
                            Container(
                              constraints: BoxConstraints(
                                maxWidth: MediaQuery.of(context).size.width * 0.6,
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
                            // 自分のメッセージの場合、アイコンを表示
                            if (isMyMessage) ...[
                              const SizedBox(width: 8),
                              Container(
                                width: 40,
                                height: 40,
                                decoration: const BoxDecoration(
                                  color: Colors.blue,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.person,
                                  color: Colors.white,
                                  size: 24,
                                ),
                              ),
                            ],
                          ],
                        ),
                      );
                    },
                  ),
          ),
          // 話題選択ボタンエリア
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              border: Border(
                bottom: BorderSide(color: Colors.grey.withValues(alpha: 0.2)),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _getText('conversation_starters'),
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.grey,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildTopicButton('weather', _getTopicLabel('weather'), Icons.wb_sunny, Colors.orange),
                      _buildTopicButton('hobbies', _getTopicLabel('hobbies'), Icons.sports_esports, Colors.blue),
                      _buildTopicButton('food', _getTopicLabel('food'), Icons.restaurant, Colors.green),
                      _buildTopicButton('future', _getTopicLabel('future'), Icons.star, Colors.purple),
                      _buildTopicButton('memories', _getTopicLabel('memories'), Icons.photo_library, Colors.pink),
                    ],
                  ),
                ),
              ],
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
