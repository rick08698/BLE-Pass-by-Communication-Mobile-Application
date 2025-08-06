import 'package:flutter/material.dart';
import 'services/personality_service.dart';
import 'main.dart';

class AvatarGroupSelectionPage extends StatefulWidget {
  final String language;
  
  const AvatarGroupSelectionPage({Key? key, required this.language}) : super(key: key);

  @override
  State<AvatarGroupSelectionPage> createState() => _AvatarGroupSelectionPageState();
}

class _AvatarGroupSelectionPageState extends State<AvatarGroupSelectionPage> {
  String? _selectedAvatarGroup;
  final PersonalityService _personalityService = PersonalityService();
  late String _currentLanguage;

  @override
  void initState() {
    super.initState();
    _currentLanguage = widget.language;
  }

  // 多言語対応テキスト
  final Map<String, Map<String, String>> _texts = {
    'ja': {
      'title': 'アバタースタイル選択',
      'subtitle': 'マッチした相手に表示するアバターのスタイルを選んでください',
      'start_button': 'アプリを開始',
      'select_first': 'スタイルを選択してください',
      'back': '戻る',
    },
    'en': {
      'title': 'Select Avatar Style',
      'subtitle': 'Choose the avatar style for your matched partners',
      'start_button': 'Start App',
      'select_first': 'Please select a style',
      'back': 'Back',
    },
  };

  String _getText(String key) {
    return _texts[_currentLanguage]?[key] ?? _texts['ja']?[key] ?? key;
  }

  String _getAvatarGroupName(String groupKey) {
    final groupInfo = _personalityService.getAvatarGroupInfo(groupKey);
    final nameKey = _currentLanguage == 'ja' ? 'name_ja' : 'name_en';
    return groupInfo?[nameKey] ?? groupKey;
  }

  String _getAvatarGroupDescription(String groupKey) {
    final groupInfo = _personalityService.getAvatarGroupInfo(groupKey);
    final descKey = _currentLanguage == 'ja' ? 'description_ja' : 'description_en';
    return groupInfo?[descKey] ?? '';
  }

  Color _getAvatarGroupColor(String groupKey) {
    final groupInfo = _personalityService.getAvatarGroupInfo(groupKey);
    final colorValue = groupInfo?['color'] as int?;
    return Color(colorValue ?? 0xFFFF6B6B);
  }

  List<String> _getAvatarGroupAvatars(String groupKey) {
    final groupInfo = _personalityService.getAvatarGroupInfo(groupKey);
    final avatars = groupInfo?['avatars'] as List<String>?;
    return avatars ?? [];
  }

  @override
  Widget build(BuildContext context) {
    final availableGroups = _personalityService.getAvailableAvatarGroups();
    
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFFFF6B6B),
              Color(0xFFFFE66D),
              Color(0xFF4ECDC4),
            ],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              children: [
                const SizedBox(height: 20),
                
                // 戻るボタンと言語切り替え
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    TextButton.icon(
                      onPressed: () {
                        Navigator.of(context).pop();
                      },
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                      label: Text(
                        _getText('back'),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        setState(() {
                          _currentLanguage = _currentLanguage == 'ja' ? 'en' : 'ja';
                        });
                      },
                      child: Text(
                        _currentLanguage == 'ja' ? 'English' : '日本語',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                
                const SizedBox(height: 20),
                
                // タイトル
                Text(
                  _getText('title'),
                  style: const TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    shadows: [
                      Shadow(
                        blurRadius: 10.0,
                        color: Colors.black26,
                        offset: Offset(2.0, 2.0),
                      ),
                    ],
                  ),
                ),
                
                const SizedBox(height: 16),
                
                Text(
                  _getText('subtitle'),
                  style: const TextStyle(
                    fontSize: 16,
                    color: Colors.white,
                    shadows: [
                      Shadow(
                        blurRadius: 5.0,
                        color: Colors.black26,
                        offset: Offset(1.0, 1.0),
                      ),
                    ],
                  ),
                  textAlign: TextAlign.center,
                ),
                
                const SizedBox(height: 40),
                
                // アバターグループ選択カード
                Expanded(
                  child: ListView.builder(
                    itemCount: availableGroups.length,
                    itemBuilder: (context, index) {
                      final groupKey = availableGroups[index];
                      final isSelected = _selectedAvatarGroup == groupKey;
                      final groupColor = _getAvatarGroupColor(groupKey);
                      final groupAvatars = _getAvatarGroupAvatars(groupKey);
                      
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 20.0),
                        child: GestureDetector(
                          onTap: () {
                            setState(() {
                              _selectedAvatarGroup = groupKey;
                            });
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.all(24),
                            decoration: BoxDecoration(
                              color: isSelected 
                                ? Colors.white.withOpacity(0.9)
                                : Colors.white.withOpacity(0.7),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: isSelected 
                                  ? groupColor
                                  : Colors.transparent,
                                width: 3,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.1),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    // グループアイコン
                                    Container(
                                      width: 60,
                                      height: 60,
                                      decoration: BoxDecoration(
                                        color: groupColor,
                                        shape: BoxShape.circle,
                                      ),
                                      child: Icon(
                                        _getGroupIcon(groupKey),
                                        color: Colors.white,
                                        size: 30,
                                      ),
                                    ),
                                    
                                    const SizedBox(width: 20),
                                    
                                    // グループ情報
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            _getAvatarGroupName(groupKey),
                                            style: TextStyle(
                                              fontSize: 24,
                                              fontWeight: FontWeight.bold,
                                              color: isSelected 
                                                ? groupColor
                                                : Colors.grey[800],
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            _getAvatarGroupDescription(groupKey),
                                            style: TextStyle(
                                              fontSize: 14,
                                              color: Colors.grey[600],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    
                                    // 選択アイコン
                                    if (isSelected)
                                      Icon(
                                        Icons.check_circle,
                                        color: groupColor,
                                        size: 30,
                                      ),
                                  ],
                                ),
                                
                                const SizedBox(height: 16),
                                
                                // アバタープレビュー
                                Row(
                                  children: [
                                    Text(
                                      _currentLanguage == 'ja' ? 'プレビュー:' : 'Preview:',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.grey[700],
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Row(
                                        children: groupAvatars.take(3).map((avatarPath) {
                                          return Padding(
                                            padding: const EdgeInsets.only(right: 8.0),
                                            child: Container(
                                              width: 40,
                                              height: 40,
                                              decoration: BoxDecoration(
                                                shape: BoxShape.circle,
                                                border: Border.all(
                                                  color: groupColor.withOpacity(0.5),
                                                  width: 2,
                                                ),
                                              ),
                                              child: ClipOval(
                                                child: Image.asset(
                                                  avatarPath,
                                                  fit: BoxFit.cover,
                                                  errorBuilder: (context, error, stackTrace) {
                                                    return Container(
                                                      color: groupColor.withOpacity(0.3),
                                                      child: Icon(
                                                        Icons.person,
                                                        color: groupColor,
                                                        size: 20,
                                                      ),
                                                    );
                                                  },
                                                ),
                                              ),
                                            ),
                                          );
                                        }).toList(),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                
                // 開始ボタン
                Padding(
                  padding: const EdgeInsets.only(top: 20),
                  child: SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: _selectedAvatarGroup != null ? _startApp : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFF6B6B),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(28),
                        ),
                        elevation: 8,
                        shadowColor: Colors.black.withOpacity(0.3),
                      ),
                      child: Text(
                        _selectedAvatarGroup != null ? _getText('start_button') : _getText('select_first'),
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  IconData _getGroupIcon(String groupKey) {
    switch (groupKey) {
      case 'anime':
        return Icons.sentiment_very_satisfied;
      case 'realistic':
        return Icons.person;
      case 'illustration':
        return Icons.palette;
      default:
        return Icons.account_circle;
    }
  }

  void _startApp() {
    if (_selectedAvatarGroup != null) {
      // 選択したアバターグループを保存
      _personalityService.setSelectedAvatarGroup(_selectedAvatarGroup!);
      
      // メインアプリに遷移
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) => BleTestPage(language: _currentLanguage),
        ),
      );
    }
  }
}