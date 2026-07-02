import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:flutter_markdown_latex/flutter_markdown_latex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'catalog_service.dart';
import 'chat_service.dart';
import 'beak_theme.dart';
import 'thinking_indicator.dart';

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
      _chatContext = await model.createChat(
        temperature: 0.7,
        topP: 0.9,
        maxOutputTokens: 1024,
        systemInstruction: 'You are a helpful AI assistant. Always use LaTeX enclosed in \$ for inline math and \$\$ for block math. Keep your responses concise and precise.',
      );
      
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
          
          final String tail = _streamingMessage.length > 300 
              ? _streamingMessage.substring(_streamingMessage.length - 300) 
              : _streamingMessage;
          final RegExp loopRegex = RegExp(r'(.{4,50}?)\1{3,}$');
          
          if (loopRegex.hasMatch(tail)) {
            _chatSubscription?.cancel();
            setState(() {
              _isGenerating = false;
              _streamingMessage += '\n\n[Generation truncated due to repetition]';
              _currentSession!.messages.add(ChatMessage(role: 'assistant', content: _streamingMessage));
              _streamingMessage = '';
            });
            _saveSessions();
            return;
          }

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
    return Scaffold(
      appBar: AppBar(
          title: BeakTheme.applyGradient(
            DropdownButton<RemoteModel>(
              value: _selectedModel,
              dropdownColor: Colors.grey[900],
              icon: Icon(Icons.arrow_drop_down, color: Colors.white),
              underline: SizedBox(),
              items: _installedModels.map((m) {
                return DropdownMenuItem<RemoteModel>(
                  value: m,
                  child: Text(m.filename, style: TextStyle(color: Colors.white, fontSize: 16)),
                );
              }).toList(),
              onChanged: (model) {
                if (model != null && model != _selectedModel) {
                  _switchModel(model);
                }
              },
              hint: Text('Select Model', style: TextStyle(color: Colors.white)),
            ),
          ),
          bottom: _isSwitchingModel
              ? PreferredSize(preferredSize: Size.fromHeight(4.0), child: BeakTheme.applyGradient(LinearProgressIndicator(color: Colors.white)))
              : null,
        ),
        drawer: Drawer(
          backgroundColor: Color(0xFF111111),
          child: Column(
            children: [
              DrawerHeader(
                decoration: BoxDecoration(color: BeakTheme.backgroundBlack),
                child: Center(
                  child: BeakTheme.applyGradient(
                    Text('Beak', style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold, letterSpacing: 1.2))
                  ),
                ),
              ),
              ListTile(
                leading: BeakTheme.applyGradient(Icon(Icons.add_circle_outline)),
                title: Text('New Chat', style: TextStyle(color: BeakTheme.primaryText, fontWeight: FontWeight.w600)),
                onTap: () {
                  Navigator.pop(context);
                  _createNewSession();
                },
              ),
              Divider(color: BeakTheme.secondaryText.withValues(alpha: 0.1), height: 1),
              Expanded(
                child: ListView.builder(
                  padding: EdgeInsets.zero,
                  itemCount: _sessions.length,
                  itemBuilder: (context, index) {
                    final session = _sessions[index];
                    final isSelected = session == _currentSession;
                    return Card(
                      margin: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      color: Color(0xFF161616),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: isSelected ? BorderSide(color: BeakTheme.goldLight.withValues(alpha: 0.5), width: 1) : BorderSide.none,
                      ),
                      child: ListTile(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        selected: isSelected,
                        selectedTileColor: BeakTheme.goldLight.withValues(alpha: 0.1),
                        title: Text(
                        session.title, 
                        style: TextStyle(
                          color: isSelected ? BeakTheme.goldLight : BeakTheme.secondaryText,
                          fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                        ),
                        maxLines: 1, 
                        overflow: TextOverflow.ellipsis
                      ),
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
                            icon: Icon(Icons.edit, size: 16, color: isSelected ? BeakTheme.goldLight.withValues(alpha: 0.7) : Colors.grey[700]),
                            onPressed: () => _renameSession(session),
                          ),
                          IconButton(
                            icon: Icon(Icons.delete, size: 16, color: isSelected ? BeakTheme.goldLight.withValues(alpha: 0.7) : Colors.grey[700]),
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
                          return _buildMessageBubble(role: 'assistant', content: _streamingMessage, isGenerating: true);
                        }
                        final msg = _currentSession!.messages[index];
                        return _buildMessageBubble(role: msg.role, content: msg.content);
                      },
                    ),
            ),
            _buildInputArea(),
          ],
        ),
      );
  }

  Widget _buildMessageBubble({required String role, required String content, bool isGenerating = false}) {
    final isUser = role == 'user';
    
    if (!isUser) {
      // Assistant message: Clean text block, no borders
      Widget childWidget;
      if (isGenerating && content.isEmpty) {
        childWidget = Padding(
          key: const ValueKey('thinking'),
          padding: const EdgeInsets.only(top: 8.0, bottom: 8.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const ThinkingIndicator(size: 40),
              const SizedBox(height: 12),
              Text('Thinking...', style: TextStyle(color: BeakTheme.secondaryText, fontSize: 14)),
            ],
          ),
        );
      } else {
        childWidget = MarkdownBody(
          key: const ValueKey('markdown'),
          data: content,
          selectable: true,
          builders: {
            'latex': LatexElementBuilder(
              textStyle: TextStyle(color: BeakTheme.goldLight, fontSize: 16),
            ),
          },
          extensionSet: md.ExtensionSet(
            [LatexBlockSyntax(), ...md.ExtensionSet.gitHubFlavored.blockSyntaxes],
            [LatexInlineSyntax(), ...md.ExtensionSet.gitHubFlavored.inlineSyntaxes],
          ),
          styleSheet: MarkdownStyleSheet(
            p: TextStyle(color: BeakTheme.primaryText, fontSize: 16, height: 1.6),
            code: TextStyle(backgroundColor: Color(0xFF111111), color: BeakTheme.goldLight, fontFamily: 'monospace'),
            codeblockDecoration: BoxDecoration(color: Color(0xFF111111), borderRadius: BorderRadius.circular(8)),
          ),
        );
      }

      return Align(
        alignment: Alignment.centerLeft,
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 16, horizontal: 8),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 150),
            layoutBuilder: (Widget? currentChild, List<Widget> previousChildren) {
              return Stack(
                alignment: Alignment.topLeft,
                children: <Widget>[
                  ...previousChildren,
                  if (currentChild != null) currentChild,
                ],
              );
            },
            child: SizedBox(
              key: ValueKey<bool>(isGenerating && content.isEmpty),
              width: double.infinity,
              child: childWidget,
            ),
          ),
        ),
      );
    }
    
    // User message: Subtle gold tinted border and background
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        margin: EdgeInsets.symmetric(vertical: 12),
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
        decoration: BoxDecoration(
          color: BeakTheme.goldLight.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: BeakTheme.goldLight.withValues(alpha: 0.2)),
        ),
        child: Text(content, style: TextStyle(color: BeakTheme.primaryText, fontSize: 16, height: 1.4)),
      ),
    );
  }

  Widget _buildInputArea() {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      color: BeakTheme.backgroundBlack,
      child: Row(
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Color(0xFF161616),
                borderRadius: BorderRadius.circular(30),
                border: Border.all(color: BeakTheme.goldLight.withValues(alpha: 0.5)),
              ),
              child: TextField(
                controller: _inputController,
                style: TextStyle(color: BeakTheme.primaryText, fontSize: 16),
                decoration: InputDecoration(
                  hintText: 'Type a message...',
                  hintStyle: TextStyle(color: BeakTheme.secondaryText),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                ),
                onSubmitted: (_) => _sendMessage(),
              ),
            ),
          ),
          SizedBox(width: 12),
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: BeakTheme.goldGradient,
            ),
            child: IconButton(
              icon: Icon(Icons.send, color: Colors.black, size: 20),
              onPressed: _isGenerating ? null : _sendMessage,
            ),
          ),
        ],
      ),
    );
  }
}
