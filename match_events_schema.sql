-- マッチイベントを保存するテーブル
CREATE TABLE match_events (
    id BIGSERIAL PRIMARY KEY,
    device_name TEXT NOT NULL,
    mac_address TEXT NOT NULL,
    rssi INTEGER NOT NULL,
    matched_at TIMESTAMP WITH TIME ZONE NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- インデックスの作成
CREATE INDEX idx_match_events_mac_address ON match_events(mac_address);
CREATE INDEX idx_match_events_matched_at ON match_events(matched_at);

-- Row Level Security (RLS) の有効化
ALTER TABLE match_events ENABLE ROW LEVEL SECURITY;

-- 匿名ユーザーが挿入と読み取りを行えるポリシー
CREATE POLICY "Enable insert for anonymous users" ON match_events
    FOR INSERT WITH CHECK (true);

CREATE POLICY "Enable read for anonymous users" ON match_events
    FOR SELECT USING (true);