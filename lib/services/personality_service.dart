import 'dart:math';

class PersonalityService {
  static final PersonalityService _instance = PersonalityService._internal();
  factory PersonalityService() => _instance;
  PersonalityService._internal();

  // ユーザーの好みの性格
  String? _userPreferredPersonality;

  // 利用可能な性格タイプ（拡張可能）
  static const List<Map<String, dynamic>> availablePersonalities = [
    {'style': 'aggressive', 'name': '攻撃的'},
    {'style': 'seductive', 'name': '色気'},
    {'style': 'religious', 'name': '宗教'},
  ];

  // アバター画像のリスト
  static const List<String> avatarImages = [
    'assets/avatars/avatar1.png',
    'assets/avatars/avatar2.png',
    'assets/avatars/avatar3.png',
    'assets/avatars/avatar4.png',
    'assets/avatars/avatar5.png',
  ];

  // 話題選択用のユーザー定型文
  static const Map<String, String> topicUserMessages = {
    'weather': '今日はいい天気ですね！',
    'hobbies': '何か趣味とかありますか？',
    'food': '美味しいお店とか知ってますか？',
    'future': '将来の夢とかありますか？',
    'memories': '何か楽しい思い出ありますか？',
  };

  // MACアドレスからアバター画像を取得
  String generateAvatarPath(String macAddress) {
    final hash = macAddress.hashCode.abs();
    final index = hash % avatarImages.length;
    return avatarImages[index];
  }

  // ユーザーの好みの性格を設定
  void setUserPreferredPersonality(String personalityStyle) {
    _userPreferredPersonality = personalityStyle;
  }

  // ユーザーの好みの性格を取得
  String? getUserPreferredPersonality() {
    return _userPreferredPersonality;
  }

  // マッチ時にユーザーの好みに基づいて性格を割り当て
  Map<String, dynamic> assignPersonalityBasedOnPreference(String macAddress) {
    final avatarPath = generateAvatarPath(macAddress);
    
    // ユーザーの好みが設定されている場合はそれを使用
    if (_userPreferredPersonality != null) {
      final personality = availablePersonalities.firstWhere(
        (p) => p['style'] == _userPreferredPersonality,
        orElse: () => availablePersonalities[0], // フォールバック
      );
      
      return {
        'avatar_path': avatarPath,
        'style': personality['style'],
        'name': personality['name'],
      };
    }
    
    // 好みが設定されていない場合はランダム
    final random = Random(macAddress.hashCode);
    final personalityIndex = random.nextInt(availablePersonalities.length);
    final personality = availablePersonalities[personalityIndex];
    
    return {
      'avatar_path': avatarPath,
      'style': personality['style'],
      'name': personality['name'],
    };
  }

  // マッチ時にランダムに性格を割り当て（後方互換性のため）
  Map<String, dynamic> assignRandomPersonality(String macAddress) {
    return assignPersonalityBasedOnPreference(macAddress);
  }

  // 既存のコードとの互換性のため
  Map<String, dynamic> getPersonalityFromMac(String macAddress) {
    return assignRandomPersonality(macAddress);
  }

  // 性格に基づいた返信パターンを取得
  List<String> getReplyPatterns(String personalityStyle) {
    const replyPatterns = {
      'aggressive': [
        'チッ、まあ悪くねえじゃねえか💢',
        'ああ？ありがとよ😠',
        'けっ、そういうこと言うんじゃねえよ💢',
        'おい、照れるじゃねえか😤',
        'バカ、そんなこと言うなよ💦',
      ],
      'seductive': [
        'あら〜ありがとう💋',
        'うふふ、そんなこと言われちゃって〜😘',
        'あなたって素敵ね〜✨',
        'もっと褒めてもいいのよ？💕',
        'そういうの、嫌いじゃないわ〜😏',
      ],
      'religious': [
        '神のお恵みがありますように🙏',
        'あなたにも神の祝福を✝️',
        '主に感謝いたします🕊️',
        'これも神の導きですね🙏',
        '祈りが通じたようですね✨',
      ],
    };

    return replyPatterns[personalityStyle] ?? replyPatterns['aggressive']!;
  }
}