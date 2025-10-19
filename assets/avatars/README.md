# アバター画像フォルダ

このフォルダにアバター画像を配置してください。

## 画像ファイルについて
- このフォルダ内の画像ファイルがランダムで表示されます
- ファイル名は任意（`lib/main.dart`の`_avatarImages`リストに追加が必要）
- 現在登録済み: `avatars_yasu.png`

## 推奨仕様
- **形式**: PNG/JPG形式
- **サイズ**: 200x200px以上（正方形推奨）
- **内容**: 人物の写真、アバター画像など

## 新しい画像を追加する方法
1. このフォルダに画像ファイルを配置
2. `lib/main.dart`の`_avatarImages`リストにファイルパスを追加：
   ```dart
   static const List<String> _avatarImages = [
     'assets/avatars/avatars_yasu.png',
     'assets/avatars/your_new_image.png', // ← 追加
   ];
   ```
3. `flutter pub get`を実行してアセットを更新

## フォールバック
画像が見つからない場合、グレーの人型アイコンが表示されます。