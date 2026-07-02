import 'package:flutter/material.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma_litertlm/flutter_gemma_litertlm.dart';
import 'package:flutter_gemma_embeddings/flutter_gemma_embeddings.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'server.dart';
import 'models_screen.dart';
import 'settings_screen.dart';
import 'chat_screen.dart';

// Global reference to the server
LocalLLMServer? globalServer;

@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(MyTaskHandler());
}

class MyTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}
  @override
  void onRepeatEvent(DateTime timestamp) {}
  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}
  @override
  void onReceiveData(Object data) {}
  @override
  void onNotificationButtonPressed(String id) {}
  @override
  void onNotificationPressed() {}
  @override
  void onNotificationDismissed() {}
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  try {
    await dotenv.load(fileName: ".env");
  } catch (e) {
    print("No .env file found");
  }
  
  FlutterForegroundTask.initCommunicationPort();
  
  await FlutterGemma.initialize(
    inferenceEngines: [LiteRtLmEngine()],
    embeddingBackends: [LiteRtEmbeddingBackend()],
  );

  final prefs = await SharedPreferences.getInstance();

  // Restore previous generation model if any
  final lastUrl = prefs.getString('active_model_url');
  if (lastUrl != null) {
    FlutterGemma.installModel(
      modelType: ModelType.gemma4,
      fileType: ModelFileType.litertlm,
    ).fromNetwork(lastUrl).install().then((_) {
      print('Generation model restored successfully.');
    }).catchError((e) {
      print('Failed to restore generation model: $e');
    });
  }

  // Restore previous embedding model if any
  final lastEmbeddingUrl = prefs.getString('active_embedding_url');
  if (lastEmbeddingUrl != null) {
    // We assume the tokenizer is always sentencepiece.model in the same repo, which we fetch based on the url
    final baseRepoUrl = lastEmbeddingUrl.substring(0, lastEmbeddingUrl.lastIndexOf('/'));
    final tokenizerUrl = '$baseRepoUrl/sentencepiece.model';
    
    FlutterGemma.installEmbedder()
      .modelFromNetwork(lastEmbeddingUrl)
      .tokenizerFromNetwork(tokenizerUrl)
      .install().then((_) {
      print('Embedding model restored successfully.');
    }).catchError((e) {
      print('Failed to restore embedding model: $e');
    });
  }
  
  // Start server if it was enabled, irrespective of model download status
  final serverEnabled = prefs.getBool('server_enabled') ?? true;
  if (serverEnabled) {
    globalServer = LocalLLMServer(port: 8080);
    globalServer!.start().then((_) async {
      FlutterForegroundTask.init(
        androidNotificationOptions: AndroidNotificationOptions(
          channelId: 'llm_service',
          channelName: 'LLM Server',
          channelDescription: 'Keeps the local LLM server running',
          channelImportance: NotificationChannelImportance.LOW,
          priority: NotificationPriority.LOW,
        ),
        iosNotificationOptions: const IOSNotificationOptions(),
        foregroundTaskOptions: ForegroundTaskOptions(
          eventAction: ForegroundTaskEventAction.nothing(),
          autoRunOnBoot: false,
          autoRunOnMyPackageReplaced: false,
          allowWakeLock: true,
          allowWifiLock: true,
        ),
      );
      
      await FlutterForegroundTask.requestNotificationPermission();
      await FlutterForegroundTask.requestIgnoreBatteryOptimization();
      
      if (!(await FlutterForegroundTask.isRunningService)) {
        await FlutterForegroundTask.startService(
          notificationTitle: 'Local LLM Server',
          notificationText: 'Server is running on port 8080',
          callback: startCallback,
        );
      }
    });
  }

  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  int _currentIndex = 0;
  final GlobalKey<ChatScreenState> _chatKey = GlobalKey();
  
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData(
        brightness: Brightness.dark,
        primaryColor: Colors.white,
        scaffoldBackgroundColor: Colors.black,
        cardColor: const Color(0xFF1E1E1E),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.black,
          elevation: 0,
          iconTheme: IconThemeData(color: Colors.white),
        ),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: Colors.black,
          selectedItemColor: Colors.white,
          unselectedItemColor: Colors.grey,
        ),
        colorScheme: const ColorScheme.dark(
          primary: Colors.white,
          secondary: Colors.grey,
          surface: Colors.black,
        ),
      ),
      home: Scaffold(
        body: IndexedStack(
          index: _currentIndex,
          children: [
            ChatScreen(key: _chatKey),
            ModelsScreen(),
            SettingsScreen(),
          ],
        ),
        bottomNavigationBar: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: (index) {
            setState(() => _currentIndex = index);
            if (index == 0) {
              _chatKey.currentState?.refreshModels();
            }
          },
          items: const [
            BottomNavigationBarItem(icon: Icon(Icons.chat), label: 'Chat'),
            BottomNavigationBarItem(icon: Icon(Icons.list), label: 'Catalog'),
            BottomNavigationBarItem(icon: Icon(Icons.settings), label: 'Settings'),
          ],
        ),
      ),
    );
  }
}
