-- BLEスキャン結果を保存するテーブル
CREATE TABLE ble_scan_results (
    id BIGSERIAL PRIMARY KEY,
    scan_session TEXT NOT NULL,
    device_name TEXT NOT NULL,
    device_id TEXT NOT NULL,
    rssi INTEGER NOT NULL,
    detected_at TIMESTAMP WITH TIME ZONE NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- インデックスの作成（クエリパフォーマンス向上のため）
CREATE INDEX idx_ble_scan_results_scan_session ON ble_scan_results(scan_session);
CREATE INDEX idx_ble_scan_results_device_id ON ble_scan_results(device_id);
CREATE INDEX idx_ble_scan_results_detected_at ON ble_scan_results(detected_at);

-- Row Level Security (RLS) の有効化
ALTER TABLE ble_scan_results ENABLE ROW LEVEL SECURITY;

-- 匿名ユーザーが挿入と読み取りを行えるポリシー
-- （実際の運用では適切なユーザー認証を推奨）
CREATE POLICY "Enable insert for anonymous users" ON ble_scan_results
    FOR INSERT WITH CHECK (true);

CREATE POLICY "Enable read for anonymous users" ON ble_scan_results
    FOR SELECT USING (true);

-- データ保持期間の管理用（オプション）
-- 例：30日以上古いレコードを自動削除する関数
CREATE OR REPLACE FUNCTION cleanup_old_scan_results()
RETURNS void AS $$
BEGIN
    DELETE FROM ble_scan_results 
    WHERE created_at < NOW() - INTERVAL '30 days';
END;
$$ LANGUAGE plpgsql;

-- 定期実行用のコメント（Supabaseのcronジョブで使用可能）
-- SELECT cron.schedule('cleanup-ble-scans', '0 2 * * *', 'SELECT cleanup_old_scan_results();');