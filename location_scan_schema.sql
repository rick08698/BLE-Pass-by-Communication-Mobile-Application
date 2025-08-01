-- 位置情報付きスキャンデータを保存するテーブル
CREATE TABLE location_scans (
    id BIGSERIAL PRIMARY KEY,
    scan_session_id TEXT NOT NULL,
    latitude DOUBLE PRECISION NOT NULL,
    longitude DOUBLE PRECISION NOT NULL,
    accuracy DOUBLE PRECISION,
    mac_addresses JSONB NOT NULL, -- 検出されたMACアドレス群をJSON配列で保存
    device_count INTEGER NOT NULL DEFAULT 0,
    scanned_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 位置情報での検索を高速化するためのインデックス
CREATE INDEX idx_location_scans_coordinates ON location_scans (latitude, longitude);
CREATE INDEX idx_location_scans_session ON location_scans (scan_session_id);
CREATE INDEX idx_location_scans_scanned_at ON location_scans (scanned_at);

-- 位置の近似検索用のインデックス（PostGISがなくても使える範囲検索用）
CREATE INDEX idx_location_scans_lat_range ON location_scans (latitude) WHERE latitude BETWEEN -90 AND 90;
CREATE INDEX idx_location_scans_lng_range ON location_scans (longitude) WHERE longitude BETWEEN -180 AND 180;

-- Row Level Security (RLS) を有効化
ALTER TABLE location_scans ENABLE ROW LEVEL SECURITY;

-- 全ユーザーが読み書き可能にするポリシー（開発用）
CREATE POLICY "Enable all operations for all users" ON location_scans
    FOR ALL USING (true) WITH CHECK (true);

-- 古いデータを自動削除する関数（30日以上前のデータ）
CREATE OR REPLACE FUNCTION cleanup_old_location_scans()
RETURNS void AS $$
BEGIN
    DELETE FROM location_scans 
    WHERE scanned_at < NOW() - INTERVAL '30 days';
END;
$$ LANGUAGE plpgsql;

-- データ統計取得用のヘルパー関数
CREATE OR REPLACE FUNCTION get_frequent_devices_at_location(
    target_lat DOUBLE PRECISION,
    target_lng DOUBLE PRECISION,
    radius_km DOUBLE PRECISION DEFAULT 0.1,
    min_occurrences INTEGER DEFAULT 4
)
RETURNS TABLE(
    mac_address TEXT,
    occurrence_count BIGINT,
    first_seen TIMESTAMP WITH TIME ZONE,
    last_seen TIMESTAMP WITH TIME ZONE
) AS $$
BEGIN
    RETURN QUERY
    WITH location_filtered AS (
        -- 指定位置から半径内のスキャンデータを取得
        SELECT ls.mac_addresses, ls.scanned_at
        FROM location_scans ls
        WHERE 
            -- 簡易距離計算（緯度経度の差分ベース、精密ではないが高速）
            ABS(ls.latitude - target_lat) <= (radius_km / 111.0) AND
            ABS(ls.longitude - target_lng) <= (radius_km / (111.0 * COS(RADIANS(target_lat))))
    ),
    mac_expanded AS (
        -- JSON配列からMACアドレスを展開
        SELECT 
            jsonb_array_elements_text(lf.mac_addresses) as mac_addr,
            lf.scanned_at
        FROM location_filtered lf
    )
    SELECT 
        me.mac_addr::TEXT,
        COUNT(*)::BIGINT as occurrence_count,
        MIN(me.scanned_at) as first_seen,
        MAX(me.scanned_at) as last_seen
    FROM mac_expanded me
    GROUP BY me.mac_addr
    HAVING COUNT(*) >= min_occurrences
    ORDER BY COUNT(*) DESC, me.mac_addr;
END;
$$ LANGUAGE plpgsql;