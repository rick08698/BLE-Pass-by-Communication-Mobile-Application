-- チャット機能用のデータベーススキーマ

-- チャットルームテーブル
CREATE TABLE chat_rooms (
    id BIGSERIAL PRIMARY KEY,
    room_id TEXT UNIQUE NOT NULL, -- 2つのMACアドレスから生成されるユニークID
    device1_mac TEXT NOT NULL,
    device2_mac TEXT NOT NULL,
    device1_name TEXT DEFAULT 'Unknown',
    device2_name TEXT DEFAULT 'Unknown',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- メッセージテーブル
CREATE TABLE chat_messages (
    id BIGSERIAL PRIMARY KEY,
    room_id TEXT NOT NULL,
    sender_mac TEXT NOT NULL,
    sender_name TEXT DEFAULT 'Unknown',
    message TEXT NOT NULL,
    message_type TEXT DEFAULT 'text', -- 'text', 'emoji', 'system'
    sent_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    FOREIGN KEY (room_id) REFERENCES chat_rooms(room_id) ON DELETE CASCADE
);

-- インデックスの作成
CREATE INDEX idx_chat_rooms_room_id ON chat_rooms(room_id);
CREATE INDEX idx_chat_rooms_device1_mac ON chat_rooms(device1_mac);
CREATE INDEX idx_chat_rooms_device2_mac ON chat_rooms(device2_mac);
CREATE INDEX idx_chat_messages_room_id ON chat_messages(room_id);
CREATE INDEX idx_chat_messages_sent_at ON chat_messages(sent_at);

-- Row Level Security (RLS) の有効化
ALTER TABLE chat_rooms ENABLE ROW LEVEL SECURITY;
ALTER TABLE chat_messages ENABLE ROW LEVEL SECURITY;

-- 匿名ユーザーが読み書きできるポリシー
CREATE POLICY "Enable insert for anonymous users" ON chat_rooms
    FOR INSERT WITH CHECK (true);

CREATE POLICY "Enable select for anonymous users" ON chat_rooms
    FOR SELECT USING (true);

CREATE POLICY "Enable update for anonymous users" ON chat_rooms
    FOR UPDATE USING (true) WITH CHECK (true);

CREATE POLICY "Enable insert for anonymous users" ON chat_messages
    FOR INSERT WITH CHECK (true);

CREATE POLICY "Enable select for anonymous users" ON chat_messages
    FOR SELECT USING (true);

-- チャットルーム作成関数
CREATE OR REPLACE FUNCTION create_or_get_chat_room(
    mac1 TEXT,
    mac2 TEXT,
    name1 TEXT DEFAULT 'Unknown',
    name2 TEXT DEFAULT 'Unknown'
)
RETURNS TEXT AS $$
DECLARE
    room_id_result TEXT;
BEGIN
    -- MACアドレスをソートしてユニークなroom_idを生成
    IF mac1 < mac2 THEN
        room_id_result := mac1 || '_' || mac2;
    ELSE
        room_id_result := mac2 || '_' || mac1;
    END IF;
    
    -- 既存ルームをチェック
    IF NOT EXISTS (SELECT 1 FROM chat_rooms WHERE room_id = room_id_result) THEN
        -- 新しいルームを作成
        IF mac1 < mac2 THEN
            INSERT INTO chat_rooms (room_id, device1_mac, device2_mac, device1_name, device2_name)
            VALUES (room_id_result, mac1, mac2, name1, name2);
        ELSE
            INSERT INTO chat_rooms (room_id, device1_mac, device2_mac, device1_name, device2_name)
            VALUES (room_id_result, mac2, mac1, name2, name1);
        END IF;
    END IF;
    
    RETURN room_id_result;
END;
$$ LANGUAGE plpgsql;

-- メッセージ送信関数
CREATE OR REPLACE FUNCTION send_message(
    room_id_param TEXT,
    sender_mac_param TEXT,
    sender_name_param TEXT,
    message_param TEXT,
    message_type_param TEXT DEFAULT 'text'
)
RETURNS BIGINT AS $$
DECLARE
    message_id BIGINT;
BEGIN
    INSERT INTO chat_messages (room_id, sender_mac, sender_name, message, message_type)
    VALUES (room_id_param, sender_mac_param, sender_name_param, message_param, message_type_param)
    RETURNING id INTO message_id;
    
    -- チャットルームの更新時刻を更新
    UPDATE chat_rooms SET updated_at = NOW() WHERE room_id = room_id_param;
    
    RETURN message_id;
END;
$$ LANGUAGE plpgsql;