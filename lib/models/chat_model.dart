// チャット機能関連のモデルクラス
class ChatRoom {
  final String id;
  final String partnerMac;
  final String partnerName;
  final int intimacyLevel;
  final List<ChatMessage> messages;

  ChatRoom({
    required this.id,
    required this.partnerMac,
    required this.partnerName,
    this.intimacyLevel = 0,
    this.messages = const [],
  });
}

class ChatMessage {
  final String id;
  final String senderMac;
  final String senderName;
  final String message;
  final DateTime sentAt;
  final String messageType;

  ChatMessage({
    required this.id,
    required this.senderMac,
    required this.senderName,
    required this.message,
    required this.sentAt,
    this.messageType = 'text',
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      id: json['id']?.toString() ?? '',
      senderMac: json['sender_mac'] ?? '',
      senderName: json['sender_name'] ?? '',
      message: json['message'] ?? '',
      sentAt: DateTime.parse(json['sent_at']).add(const Duration(hours: 9)),
      messageType: json['message_type'] ?? 'text',
    );
  }
}

class PersonalityProfile {
  final String style;
  final String name;
  final String description;
  final List<String> traits;

  PersonalityProfile({
    required this.style,
    required this.name,
    required this.description,
    required this.traits,
  });
}