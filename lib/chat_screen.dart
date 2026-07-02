import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'catalog_service.dart';
import 'chat_service.dart';

class ChatScreen extends StatefulWidget {
  ChatScreen({Key? key}) : super(key: key);

  @override
  ChatScreenState createState() => ChatScreenState();
}

class ChatScreenState extends State<ChatScreen> {
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  
  List<RemoteModel> _installedModels = [];
  RemoteModel? _selectedModel;
  bool _isSwitchingModel = false;
  
  List<ChatSession> _sessions = [];
  ChatSession? _currentSession;
  
  bool _isGenerating = false;
  String _streamingMessage = '';
  StreamSubscription? _chatSubscription;
  InferenceChat? _chatContext;
  
  static final Set<String> _failedModels = {};

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  void refreshModels() {
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    final catalog = await CatalogService.fetchCatalog();
    final installedFilenames = await FlutterGemma.listInstalledModels();
    
    _installedModels = catalog
        .where((m) => m.type == 'Generation' && installedFilenames.contains(m.filename))
        .toList();

    _sessions = await ChatService.loadSessions();
    if (_sessions.isNotEmpty) {
      _currentSession = _sessions.first;
    } else {
      _createNewSession();
    }

    // Attempt to select the active model
    final prefs = await SharedPreferences.getInstance();
    final activeUrl = prefs.getString('active_model_url');
    if (activeUrl != null) {
      try {
        _selectedModel = _installedModels.firstWhere((m) => m.downloadUrl == activeUrl);
      } catch (e) {
        _selectedModel = _installedModels.isNotEmpty ? _installedModels.first : null;
      }
    } else {
      _selectedModel = _installedModels.isNotEmpty ? _installedModels.first : null;
    }

    if (mounted) {
      setState(() {});
    }
    _initChatContext();
  }

  void _createNewSession() {
    final newSession = ChatSession(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: 'New Chat',
      messages: [],
    );
    _sessions.insert(0, newSession);
    _currentSession = newSession;
    _chatContext = null;
    _saveSessions();
    _initChatContext();
    setState(() {});
  }

  Future<void> _saveSessions() async {
    await ChatService.saveSessions(_sessions);
  }

  Future<void> _switchModel(RemoteModel model) async {
    setState(() {
      _isSwitchingModel = true;
      _selectedModel = model;
    });

    try {
      final dir = await getApplicationDocumentsDirectory();
      final path = '${dir.path}/${model.filename}';
      
      if (_failedModels.contains(path)) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Model previously failed to load. Try another model.')));
        return;
      }

      var builder = FlutterGemma.installModel(
        modelType: ModelType.gemma4,
        fileType: ModelFileType.litertlm,
      ).fromFile(path);
      await builder.install();
      
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('active_model_url', model.downloadUrl);
      
      _chatContext = null;
      await _initChatContext();
    } catch (e) {
      final dir = await getApplicationDocumentsDirectory();
      _failedModels.add('${dir.path}/${model.filename}');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to switch model: $e')));
    } finally {
      setState(() {
        _isSwitchingModel = false;
      });
    }
  }

  Future<void> _initChatContext() async {
    if (_selectedModel == null) return;
    try {
      final model = await FlutterGemma.getActiveModel();
      _chatContext = await model.createChat();
      
      // Load context for current session
      if (_currentSession != null) {
        for (var msg in _currentSession!.messages) {
          await _chatContext!.addQuery(Message.text(text: msg.content, isUser: msg.role == 'user'));
        }
      }
    } catch (e) {
      print('Error initializing chat context: $e');
    }
  }

  Future<void> _sendMessage() async {
    final text = _inputController.text.trim();
    if (text.isEmpty || _isGenerating || _selectedModel == null) return;

    _inputController.clear();
    setState(() {
      _isGenerating = true;
      _streamingMessage = '';
      _currentSession!.messages.add(ChatMessage(role: 'user', content: text));
    });
    
    // Autogenerate title if this is the first message
    if (_currentSession!.title == 'New Chat' && _currentSession!.messages.length == 1) {
      _currentSession!.title = text.length > 20 ? '${text.substring(0, 20)}...' : text;
    }
    
    _saveSessions();
    _scrollToBottom();

    if (_chatContext == null) {
      await _initChatContext();
    }

    try {
      await _chatContext!.addQuery(Message.text(text: text, isUser: true));
      final stream = _chatContext!.generateChatResponseAsync();

      _chatSubscription = stream.listen((response) {
        if (response is TextResponse) {
          setState(() {
            _streamingMessage += response.token;
          });
          _scrollToBottom();
        }
      }, onDone: () {
        setState(() {
          _isGenerating = false;
          _currentSession!.messages.add(ChatMessage(role: 'assistant', content: _streamingMessage));
          _streamingMessage = '';
        });
        _saveSessions();
      }, onError: (e) {
        setState(() {
          _isGenerating = false;
          _streamingMessage += '\n\n[Error generating response]';
          _currentSession!.messages.add(ChatMessage(role: 'assistant', content: _streamingMessage));
          _streamingMessage = '';
        });
        _saveSessions();
      });
    } catch (e) {
      setState(() {
        _isGenerating = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Inference error: $e')));
    }
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _renameSession(ChatSession session) {
    final controller = TextEditingController(text: session.title);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: Text('Rename Chat', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          style: TextStyle(color: Colors.white),
          decoration: InputDecoration(
            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.grey)),
            focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white)),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text('Cancel', style: TextStyle(color: Colors.grey))),
          TextButton(
            onPressed: () {
              setState(() => session.title = controller.text);
              _saveSessions();
              Navigator.pop(context);
            },
            child: Text('Rename', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _deleteSession(ChatSession session) {
    setState(() {
      _sessions.remove(session);
      if (_currentSession == session) {
        if (_sessions.isNotEmpty) {
          _currentSession = _sessions.first;
        } else {
          _createNewSession();
        }
      }
    });
    _saveSessions();
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: ThemeData(
        brightness: Brightness.dark,
        primaryColor: Colors.white,
        scaffoldBackgroundColor: Colors.black,
        cardColor: Color(0xFF1E1E1E),
        appBarTheme: AppBarTheme(backgroundColor: Colors.black, elevation: 0),
        colorScheme: ColorScheme.dark(primary: Colors.white, secondary: Colors.grey[400]!),
      ),
      child: Scaffold(
        appBar: AppBar(
          title: DropdownButton<RemoteModel>(
            value: _selectedModel,
            dropdownColor: Colors.grey[900],
            icon: Icon(Icons.arrow_drop_down, color: Colors.white),
            underline: SizedBox(),
            items: _installedModels.map((m) {
              return DropdownMenuItem<RemoteModel>(
                value: m,
                child: Text(m.filename, style: TextStyle(color: Colors.white, fontSize: 14)),
              );
            }).toList(),
            onChanged: (model) {
              if (model != null && model != _selectedModel) {
                _switchModel(model);
              }
            },
            hint: Text('Select Model', style: TextStyle(color: Colors.white)),
          ),
          bottom: _isSwitchingModel
              ? PreferredSize(preferredSize: Size.fromHeight(4.0), child: LinearProgressIndicator(color: Colors.white))
              : null,
        ),
        drawer: Drawer(
          backgroundColor: Colors.grey[900],
          child: Column(
            children: [
              DrawerHeader(
                decoration: BoxDecoration(color: Colors.black),
                child: Center(child: Text('Beak', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold))),
              ),
              ListTile(
                leading: Icon(Icons.add, color: Colors.white),
                title: Text('New Chat', style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(context);
                  _createNewSession();
                },
              ),
              Divider(color: Colors.grey[800]),
              Expanded(
                child: ListView.builder(
                  itemCount: _sessions.length,
                  itemBuilder: (context, index) {
                    final session = _sessions[index];
                    final isSelected = session == _currentSession;
                    return ListTile(
                      selected: isSelected,
                      selectedTileColor: Colors.white.withValues(alpha: 0.1),
                      title: Text(session.title, style: TextStyle(color: Colors.white), maxLines: 1, overflow: TextOverflow.ellipsis),
                      onTap: () {
                        setState(() {
                          _currentSession = session;
                          _chatContext = null;
                          _isGenerating = false;
                        });
                        _initChatContext();
                        Navigator.pop(context);
                      },
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: Icon(Icons.edit, size: 16, color: Colors.grey),
                            onPressed: () => _renameSession(session),
                          ),
                          IconButton(
                            icon: Icon(Icons.delete, size: 16, color: Colors.grey),
                            onPressed: () => _deleteSession(session),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        body: Column(
          children: [
            Expanded(
              child: _currentSession == null
                  ? Center(child: CircularProgressIndicator())
                  : ListView.builder(
                      controller: _scrollController,
                      padding: EdgeInsets.all(16),
                      itemCount: _currentSession!.messages.length + (_isGenerating ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (index == _currentSession!.messages.length) {
                          return _buildMessageBubble(role: 'assistant', content: _streamingMessage);
                        }
                        final msg = _currentSession!.messages[index];
                        return _buildMessageBubble(role: msg.role, content: msg.content);
                      },
                    ),
            ),
            _buildInputArea(),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageBubble({required String role, required String content}) {
    final isUser = role == 'user';
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: EdgeInsets.symmetric(vertical: 8),
        padding: EdgeInsets.all(12),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.8),
        decoration: BoxDecoration(
          color: isUser ? Colors.white.withValues(alpha: 0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: isUser ? null : Border.all(color: Colors.white.withValues(alpha: 0.2)),
        ),
        child: isUser
            ? Text(content, style: TextStyle(color: Colors.white, fontSize: 16))
            : MarkdownBody(
                data: content,
                styleSheet: MarkdownStyleSheet(
                  p: TextStyle(color: Colors.grey[300], fontSize: 16),
                  code: TextStyle(backgroundColor: Colors.black, color: Colors.white, fontFamily: 'monospace'),
                  codeblockDecoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey[800]!)),
                ),
              ),
      ),
    );
  }

  Widget _buildInputArea() {
    return Container(
      padding: EdgeInsets.all(16),
      color: Colors.black,
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _inputController,
              style: TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Type a message...',
                hintStyle: TextStyle(color: Colors.grey),
                filled: true,
                fillColor: Colors.grey[900],
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              ),
              onSubmitted: (_) => _sendMessage(),
            ),
          ),
          SizedBox(width: 8),
          CircleAvatar(
            backgroundColor: _isGenerating ? Colors.grey : Colors.white,
            child: IconButton(
              icon: Icon(Icons.send, color: Colors.black),
              onPressed: _isGenerating ? null : _sendMessage,
            ),
          ),
        ],
      ),
    );
  }
}
