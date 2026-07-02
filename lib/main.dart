import 'package:flutter/material.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma_litertlm/flutter_gemma_litertlm.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'server.dart';
import 'models_screen.dart';
import 'settings_screen.dart';

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
  FlutterForegroundTask.initCommunicationPort();
  
  await FlutterGemma.initialize(
    inferenceEngines: [LiteRtLmEngine()],
  );

  final prefs = await SharedPreferences.getInstance();

  // Restore previous model if any
  final lastUrl = prefs.getString('active_model_url');
  if (lastUrl != null) {
    // Fire and forget the model installation/restoration
    FlutterGemma.installModel(
      modelType: ModelType.gemma4,
      fileType: ModelFileType.litertlm,
    ).fromNetwork(lastUrl).install().then((_) {
      print('Model restored successfully.');
    }).catchError((e) {
      print('Failed to restore model: $e');
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
  
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('Gemma Local Server')),
        body: IndexedStack(
          index: _currentIndex,
          children: [
            ModelsScreen(),
            SettingsScreen(),
          ],
        ),
        bottomNavigationBar: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: (index) => setState(() => _currentIndex = index),
          items: const [
            BottomNavigationBarItem(icon: Icon(Icons.list), label: 'Catalog'),
            BottomNavigationBarItem(icon: Icon(Icons.settings), label: 'Settings'),
          ],
        ),
      ),
    );
  }
}
