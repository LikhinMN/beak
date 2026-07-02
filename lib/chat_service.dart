import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

class ChatMessage {
  final String role;
  final String content;

  ChatMessage({required this.role, required this.content});

  Map<String, dynamic> toJson() => {'role': role, 'content': content};
  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
    role: json['role'],
    content: json['content'],
  );
}

class ChatSession {
  String id;
  String title;
  List<ChatMessage> messages;

  ChatSession({required this.id, required this.title, required this.messages});

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'messages': messages.map((m) => m.toJson()).toList(),
  };

  factory ChatSession.fromJson(Map<String, dynamic> json) => ChatSession(
    id: json['id'],
    title: json['title'],
    messages: (json['messages'] as List).map((m) => ChatMessage.fromJson(m)).toList(),
  );
}

class ChatService {
  static const String _fileName = 'chat_history.json';
  
  static Future<File> get _file async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_fileName');
  }

  static Future<List<ChatSession>> loadSessions() async {
    try {
      final file = await _file;
      if (!await file.exists()) return [];
      final contents = await file.readAsString();
      final jsonList = jsonDecode(contents) as List;
      return jsonList.map((j) => ChatSession.fromJson(j)).toList();
    } catch (e) {
      print('Error loading chat sessions: $e');
      return [];
    }
  }

  static Future<void> saveSessions(List<ChatSession> sessions) async {
    try {
      final file = await _file;
      final jsonStr = jsonEncode(sessions.map((s) => s.toJson()).toList());
      await file.writeAsString(jsonStr);
    } catch (e) {
      print('Error saving chat sessions: $e');
    }
  }
}
