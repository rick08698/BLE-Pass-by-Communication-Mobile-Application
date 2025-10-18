# アバター設定ガイド

このガイドでは、Bluetooth Loveアプリのアバターシステムの設定と拡張方法について説明します。

## 📋 目次
1. [現在のアバター構成](#現在のアバター構成)
2. [新しいアバター画像の追加](#新しいアバター画像の追加)
3. [新しいアバターグループの追加](#新しいアバターグループの追加)
4. [専用アイテムの設定](#専用アイテムの設定)
5. [トラブルシューティング](#トラブルシューティング)

## 🎨 現在のアバター構成

### アバターグループ一覧
| グループ | 説明 | 含まれるアバター | 色 |
|---------|------|-----------------|-----|
| **anime** | アニメ風 | avatar1.png, avatar2.png | ピンク |
| **realistic** | リアル風 | avatar3.png, avatar4.png | ティール |
| **illustration** | イラスト風 | avatar5.png | イエロー |

### ファイル構成
```
assets/avatars/
├── README.md
├── avatar1.png  (アニメ風)
├── avatar2.png  (アニメ風)
├── avatar3.png  (リアル風)
├── avatar4.png  (リアル風)
└── avatar5.png  (イラスト風)
```

## 🆕 新しいアバター画像の追加

### 1. 画像ファイルの準備
- **ファイル形式**: PNG推奨（透明背景対応）
- **推奨サイズ**: 512x512px以上
- **命名規則**: `avatarX.png` (Xは連番)

### 2. ファイル配置
```bash
# assets/avatars/フォルダに新しいアバター画像を追加
cp your_new_avatar.png assets/avatars/avatar6.png
```

### 3. pubspec.yamlの更新
```yaml
flutter:
  assets:
    - assets/avatars/  # 既に設定済み（フォルダ全体）
```

### 4. PersonalityServiceの更新
`lib/services/personality_service.dart`を編集：

```dart
// 既存グループにアバターを追加する場合
'anime': {
  'name_ja': 'アニメ風',
  'name_en': 'Anime Style',
  'description_ja': 'かわいいアニメキャラクター風のアバター',
  'description_en': 'Cute anime character style avatars',
  'avatars': [
    'assets/avatars/avatar1.png', 
    'assets/avatars/avatar2.png',
    'assets/avatars/avatar6.png', // ← 新規追加
    'assets/avatars/avatar7.png', // ← 新規追加
  ],
  'color': 0xFFFF9AA2,
},

// 後方互換性のため、avatarImagesにも追加
static const List<String> avatarImages = [
  'assets/avatars/avatar1.png',
  'assets/avatars/avatar2.png',
  'assets/avatars/avatar3.png',
  'assets/avatars/avatar4.png',
  'assets/avatars/avatar5.png',
  'assets/avatars/avatar6.png', // ← 追加
  'assets/avatars/avatar7.png', // ← 追加
];
```

## 🎭 新しいアバターグループの追加

### 1. PersonalityServiceへのグループ追加
`lib/services/personality_service.dart`の`avatarGroups`に追加：

```dart
static const Map<String, Map<String, dynamic>> avatarGroups = {
  // 既存のグループ...
  
  // 新しいグループを追加
  'cyberpunk': {
    'name_ja': 'サイバーパンク風',
    'name_en': 'Cyberpunk Style',
    'description_ja': '未来的でクールなアバター',
    'description_en': 'Futuristic and cool avatars',
    'avatars': [
      'assets/avatars/cyber1.png',
      'assets/avatars/cyber2.png',
    ],
    'color': 0xFF00FFFF, // シアン色
  },
  'fantasy': {
    'name_ja': 'ファンタジー風',
    'name_en': 'Fantasy Style',
    'description_ja': '魔法的でファンタジックなアバター',
    'description_en': 'Magical and fantasy avatars',
    'avatars': [
      'assets/avatars/wizard1.png',
      'assets/avatars/elf1.png',
      'assets/avatars/knight1.png',
    ],
    'color': 0xFF9C27B0, // パープル色
  },
};
```

### 2. UIアイコンの追加
`lib/avatar_group_selection_page.dart`の`_getGroupIcon()`メソッドに追加：

```dart
IconData _getGroupIcon(String groupKey) {
  switch (groupKey) {
    case 'anime':
      return Icons.sentiment_very_satisfied;
    case 'realistic':
      return Icons.person;
    case 'illustration':
      return Icons.palette;
    case 'cyberpunk':        // ← 新規追加
      return Icons.computer;
    case 'fantasy':          // ← 新規追加
      return Icons.castle;
    default:
      return Icons.account_circle;
  }
}
```

### 3. 色の定義について
グループ色は16進数で指定します：
```dart
'color': 0xFFRRGGBB,  // FF(不透明度) + RRGGBB(RGB値)

// 例：
0xFFFF0000,  // 赤
0xFF00FF00,  // 緑  
0xFF0000FF,  // 青
0xFFFF9AA2,  // ピンク
0xFF4ECDC4,  // ティール
```

## 🎁 専用アイテムの設定

### 特定アバター専用アイテムの追加
`lib/main.dart`の`_itemDefinitions`に追加：

```dart
// 新しい専用アイテムの例
'magic_wand': {
  'name': {
    'ja': '魔法の杖',
    'en': 'Magic Wand',
  },
  'description': {
    'ja': 'wizard1専用アイテム。魔法の力で親密度大幅アップ！',
    'en': 'Exclusive item for wizard1. Magical power boosts intimacy!',
  },
  'price': 150,
  'icon': 'auto_awesome',
  'color': 'purple',
  'type': 'specific',
  'target_avatar': 'assets/avatars/wizard1.png', // 対象アバター
  'positive_effect': 20,  // 対象アバターへの効果
  'negative_effect': -5,  // 他アバターへの効果
},
```

### グループ専用アイテムの表示制御
アイテムショップでの表示制御例：

```dart
// lib/main.dart のアイテムリスト生成部分
children: _itemDefinitions.entries.where((entry) {
  final itemId = entry.key;
  final selectedGroup = PersonalityService().getSelectedAvatarGroup();
  
  // タバコはアニメ風グループのみ
  if (itemId == 'cigarette') {
    return selectedGroup == 'anime';
  }
  
  // 魔法の杖はファンタジーグループのみ
  if (itemId == 'magic_wand') {
    return selectedGroup == 'fantasy';
  }
  
  return true;  // その他のアイテムは常に表示
}).map((entry) {
  // アイテムカード生成...
}).toList(),
```

## 🚀 使用例：新しいグループ「サイバーパンク風」の完全な追加手順

### 1. アバター画像の準備
```bash
# 新しいアバター画像をassetsフォルダに配置
cp cyber_girl.png assets/avatars/cyber1.png
cp cyber_boy.png assets/avatars/cyber2.png
```

### 2. PersonalityService更新
```dart
// avatarGroupsに追加
'cyberpunk': {
  'name_ja': 'サイバーパンク風',
  'name_en': 'Cyberpunk Style', 
  'description_ja': '未来的でクールなアバター',
  'description_en': 'Futuristic and cool avatars',
  'avatars': [
    'assets/avatars/cyber1.png',
    'assets/avatars/cyber2.png',
  ],
  'color': 0xFF00FFFF,
},

// avatarImagesにも追加（後方互換性）
static const List<String> avatarImages = [
  // 既存のアバター...
  'assets/avatars/cyber1.png',
  'assets/avatars/cyber2.png',
];
```

### 3. UIアイコン追加
```dart
// AvatarGroupSelectionPage
case 'cyberpunk':
  return Icons.computer;
```

### 4. 専用アイテム追加（オプション）
```dart
// サイバーパンク専用アイテム
'neural_chip': {
  'name': {
    'ja': 'ニューラルチップ',
    'en': 'Neural Chip',
  },
  'description': {
    'ja': 'サイバーパンク系アバター専用の未来技術！',
    'en': 'Future tech for cyberpunk avatars!',
  },
  'price': 200,
  'icon': 'memory',
  'color': 'cyan',
  'type': 'specific',
  'target_avatar': 'assets/avatars/cyber1.png',
  'positive_effect': 25,
  'negative_effect': -5,
},
```

### 5. アイテム表示制御追加
```dart
// アイテムショップでの表示制御
if (itemId == 'neural_chip') {
  return selectedGroup == 'cyberpunk';
}
```

## 🔧 トラブルシューティング

### よくある問題と解決方法

#### 1. アバター画像が表示されない
**症状**: 新しく追加したアバターが表示されない

**解決方法**:
- `flutter clean && flutter pub get` を実行
- `pubspec.yaml`のassetsセクションを確認
- 画像ファイルパスの大文字小文字を確認
- 画像ファイルの形式（PNG/JPG）を確認

#### 2. 新しいグループが選択画面に出ない
**症状**: PersonalityServiceに追加したグループが表示されない

**解決方法**:
- `avatarGroups`のマップ構造を確認
- 必須フィールド（name_ja, name_en, avatars, color）の存在を確認
- `_getGroupIcon()`にアイコンを追加

#### 3. 専用アイテムが正しく動作しない
**症状**: 専用アイテムの効果が期待通りに動作しない

**解決方法**:
- `target_avatar`のパスが正確か確認
- アバター生成ロジック（PersonalityService）との整合性確認
- アイテム表示制御の条件を確認

#### 4. 色が正しく表示されない
**症状**: グループの色が期待通りに表示されない

**解決方法**:
```dart
// 正しい形式で色を指定
'color': 0xFFRRGGBB,  // 16進数形式

// 間違った例
'color': '#RRGGBB',   // 文字列形式（サポートされていない）
'color': Colors.red,  // Colorオブジェクト（サポートされていない）
```

### デバッグのヒント

#### ログ出力でデバッグ
```dart
// PersonalityServiceにデバッグログを追加
String generateAvatarPath(String macAddress) {
  print('Selected group: $_selectedAvatarGroup');
  print('Available groups: ${avatarGroups.keys}');
  
  final hash = macAddress.hashCode.abs();
  // ... 既存のロジック
}
```

#### アバターグループの確認
```dart
// 現在選択されているグループを確認
void debugSelectedGroup() {
  final service = PersonalityService();
  print('Current selected group: ${service.getSelectedAvatarGroup()}');
  print('Available groups: ${service.getAvailableAvatarGroups()}');
}
```

## 📝 注意事項

### パフォーマンス考慮
- アバター画像は適切なサイズ（512x512px程度）に最適化してください
- 過度に多くのアバターを追加するとアプリサイズが増加します

### 互換性
- 既存の`avatarImages`リストも更新して後方互換性を保ってください
- アイテムシステムとの整合性を確認してください

### UI考慮
- グループ名は短く、分かりやすい名前にしてください
- 色は他のグループと区別しやすい色を選択してください

## 🎯 まとめ

このガイドに従って、以下の拡張が可能です：
- ✅ 新しいアバター画像の追加
- ✅ 新しいアバターグループの作成  
- ✅ グループ専用アイテムの設定
- ✅ 表示制御のカスタマイズ

何か問題が発生した場合は、このトラブルシューティングセクションを参照するか、コードの該当部分を確認してください。