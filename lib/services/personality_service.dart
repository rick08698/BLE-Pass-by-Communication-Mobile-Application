import 'dart:math';

class PersonalityService {
  static final PersonalityService _instance = PersonalityService._internal();
  factory PersonalityService() => _instance;
  PersonalityService._internal();

  // ユーザーの好みの性格
  String? _userPreferredPersonality;
  
  // ユーザーの選択したアバターグループ
  String? _selectedAvatarGroup;

  // 利用可能な性格タイプ（拡張可能）
  static const List<Map<String, dynamic>> availablePersonalities = [
    {'style': 'gentle', 'name': '優しい'},
    {'style': 'cool', 'name': 'クール'},
    {'style': 'cute', 'name': '可愛い'},
    {'style': 'aggressive', 'name': '攻撃的'},
    {'style': 'seductive', 'name': '色気'},
    {'style': 'cheerful', 'name': '明るい'},
    {'style': 'shy', 'name': '恥ずかしがり屋'},
    {'style': 'mysterious', 'name': 'ミステリアス'},
    {'style': 'energetic', 'name': '元気'},
    {'style': 'intellectual', 'name': '知的'},
  ];

  // アバターグループの定義
  static const Map<String, Map<String, dynamic>> avatarGroups = {
    'anime': {
      'name_ja': 'アニメ風',
      'name_en': 'Anime Style',
      'description_ja': 'かわいいアニメキャラクター風のアバター',
      'description_en': 'Cute anime character style avatars',
      'avatars': ['assets/avatars/avatar1.png', 'assets/avatars/avatar2.png'],
      'color': 0xFFFF9AA2, // ピンク
    },
    'realistic': {
      'name_ja': 'リアル風',
      'name_en': 'Realistic Style', 
      'description_ja': '写実的でリアルなアバター',
      'description_en': 'Photorealistic and natural avatars',
      'avatars': ['assets/avatars/avatar3.png', 'assets/avatars/avatar4.png'],
      'color': 0xFF4ECDC4, // ティール
    },
    'illustration': {
      'name_ja': 'イラスト風',
      'name_en': 'Illustration Style',
      'description_ja': 'おしゃれなイラスト風アバター',
      'description_en': 'Stylish illustration style avatars',
      'avatars': ['assets/avatars/avatar5.png'],
      'color': 0xFFFFE66D, // イエロー
    },
  };

  // アバター画像のリスト（後方互換性のため）
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

  // MACアドレスからアバター画像を取得（選択されたグループから）
  String generateAvatarPath(String macAddress) {
    final hash = macAddress.hashCode.abs();
    
    // アバターグループが選択されている場合
    if (_selectedAvatarGroup != null && avatarGroups.containsKey(_selectedAvatarGroup)) {
      final groupAvatars = avatarGroups[_selectedAvatarGroup]!['avatars'] as List<String>;
      final index = hash % groupAvatars.length;
      return groupAvatars[index];
    }
    
    // 選択されていない場合は全体からランダム
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

  // アバターグループを設定
  void setSelectedAvatarGroup(String groupKey) {
    _selectedAvatarGroup = groupKey;
  }

  // 選択されたアバターグループを取得
  String? getSelectedAvatarGroup() {
    return _selectedAvatarGroup;
  }

  // アバターグループの情報を取得
  Map<String, dynamic>? getAvatarGroupInfo(String groupKey) {
    return avatarGroups[groupKey];
  }

  // 利用可能なアバターグループのリストを取得
  List<String> getAvailableAvatarGroups() {
    return avatarGroups.keys.toList();
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
      'gentle': [
        'ありがとうございます😊',
        'とても嬉しいです💕',
        'あなたも素敵ですね✨',
        'そんな風に言ってもらえて幸せです🌸',
        'お気遣いありがとうございます😌',
      ],
      'cool': [
        'そうですね😎',
        'まあ、悪くないね👍',
        'ふーん、なるほど🤔',
        '別に普通だけど💭',
        'そんなところかな😏',
      ],
      'cute': [
        'わーい！ありがとう🥰',
        'えへへ〜照れちゃう💕',
        'そんなこと言われたら嬉しいな〜😊',
        'きゃー！恥ずかしい〜☺️',
        'ほんと？やったー！🎉',
      ],
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
      'cheerful': [
        'ありがとう〜！超嬉しい！😆',
        'やったー！最高だね〜🎉',
        'えー！本当に？ありがとう！✨',
        'うわー！テンション上がる〜！🚀',
        'すっごく嬉しいよ〜！💫',
      ],
      'shy': [
        'あ、ありがとう...💦',
        'そんな...恥ずかしいです😳',
        'え、えっと...嬉しいです...☺️',
        'あの...ありがとうございます...🙈',
        'そんなこと言われると...ドキドキしちゃいます💓',
      ],
      'mysterious': [
        'フフ...そうですか...🌙',
        '興味深いですね...✨',
        'それは...秘密です...😏',
        'あなたには話しましょうか...🔮',
        '不思議な縁ですね...🌟',
      ],
      'energetic': [
        'おー！ありがとう！💪',
        'やるじゃん！最高だぜ！🔥',
        'よっしゃ！ナイス！⚡',
        'うおー！テンション最高！🚀',
        'ガハハ！いいねえ！😄',
      ],
      'intellectual': [
        '興味深い観点ですね📚',
        'なるほど、的確な分析です🤓',
        '論理的な考察ですね💭',
        'データに基づく判断ですか🔬',
        '合理的なアプローチですね⚗️',
      ],
    };

    return replyPatterns[personalityStyle] ?? replyPatterns['gentle']!;
  }
}