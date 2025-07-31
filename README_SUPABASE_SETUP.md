# Supabase セットアップガイド

## 1. Supabaseプロジェクトの設定

### 必要な設定値
`lib/main.dart` の以下の部分を自分のSupabaseプロジェクトの値に置き換えてください：

```dart
await Supabase.initialize(
  url: 'YOUR_SUPABASE_URL_HERE',        // ← あなたのSupabase URL
  anonKey: 'YOUR_SUPABASE_ANON_KEY_HERE', // ← あなたのSupabase anon key
);
```

### 設定値の取得方法
1. [Supabase Dashboard](https://app.supabase.com) にログイン
2. プロジェクトを作成または選択
3. Settings → API から以下を取得：
   - `Project URL` → `url` に設定
   - `anon public` key → `anonKey` に設定

## 2. データベーススキーマの作成

1. Supabase Dashboard の「SQL Editor」を開く
2. `database_schema.sql` ファイルの内容をコピー＆ペースト
3. 「RUN」ボタンをクリックして実行

## 3. テーブル構造

### `ble_scan_results` テーブル
| カラム名 | 型 | 説明 |
|---------|----|----- |
| id | BIGSERIAL | 主キー（自動増分） |
| scan_session | TEXT | スキャンセッションID（同じスキャンでの検出を識別） |
| device_name | TEXT | BLEデバイス名 |
| device_id | TEXT | BLEデバイスID（MACアドレス） |
| rssi | INTEGER | 受信信号強度 |
| detected_at | TIMESTAMP | デバイス検出時刻 |
| created_at | TIMESTAMP | レコード作成時刻 |

## 4. データの確認

Supabase Dashboard の「Table Editor」で `ble_scan_results` テーブルを確認し、
アプリからのデータが正常に保存されているかチェックできます。

## 5. セキュリティ設定（推奨）

現在は匿名ユーザーでも読み書き可能な設定になっています。
本格運用では以下を検討してください：

- ユーザー認証の実装
- より厳密なRow Level Security (RLS) ポリシーの設定
- API キーの環境変数化

## 6. データ管理

- 30日以上古いデータを自動削除する関数を用意済み
- 必要に応じてSupabaseのcronジョブで定期実行可能