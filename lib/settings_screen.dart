import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'server.dart';
import 'main.dart';

class SettingsScreen extends StatefulWidget {
  @override
  _SettingsScreenState createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _serverEnabled = true;
  String _activeModel = 'None';

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _serverEnabled = prefs.getBool('server_enabled') ?? true;
      _activeModel = prefs.getString('active_model_url') ?? 'None';
    });
  }

  Future<void> _toggleServer(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('server_enabled', value);
    setState(() {
      _serverEnabled = value;
    });

    if (value) {
      if (globalServer == null) {
        globalServer = LocalLLMServer(port: 8080);
      }
      await globalServer!.start();
      
      if (!(await FlutterForegroundTask.isRunningService)) {
        await FlutterForegroundTask.startService(
          notificationTitle: 'Local LLM Server',
          notificationText: 'Server is running on port 8080',
          callback: startCallback,
        );
      }
    } else {
      if (globalServer != null) {
        await globalServer!.stop();
      }
      if (await FlutterForegroundTask.isRunningService) {
        await FlutterForegroundTask.stopService();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.all(16),
      children: [
        SwitchListTile(
          title: Text('Enable Local HTTP Server'),
          subtitle: Text('Port: 8080\nEndpoints: /v1/chat/completions'),
          value: _serverEnabled,
          onChanged: _toggleServer,
        ),
        Divider(),
        ListTile(
          title: Text('Current Loaded Model'),
          subtitle: Text(_activeModel.isEmpty ? 'None' : _activeModel.split('/').last),
        ),
      ],
    );
  }
}
