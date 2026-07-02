import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
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
  bool _isClearing = false;

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

  Future<void> _clearAllModels() async {
    bool confirm = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Clear All Models?'),
        content: Text('This will delete all downloaded models. If the server is running, you must stop it first.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text('CANCEL')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: Text('CLEAR ALL', style: TextStyle(color: Colors.red))),
        ],
      ),
    ) ?? false;

    if (!confirm) return;

    if (_serverEnabled) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Please stop the server first before clearing all models.')),
      );
      return;
    }

    setState(() {
      _isClearing = true;
    });

    try {
      final installed = await FlutterGemma.listInstalledModels();
      for (String modelName in installed) {
        await FlutterGemma.uninstallModel(modelName);
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('active_model_url');
      setState(() {
        _activeModel = 'None';
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('All models cleared successfully!')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error clearing models: $e')),
      );
    } finally {
      setState(() {
        _isClearing = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.all(16),
      children: [
        SwitchListTile(
          title: Text('Enable Local HTTP Server'),
          subtitle: Text(
            _serverEnabled ? 'Running on port 8080\nEndpoints: /v1/chat/completions' : 'Stopped'
          ),
          value: _serverEnabled,
          onChanged: _toggleServer,
        ),
        Divider(),
        ListTile(
          title: Text('Current Loaded Model'),
          subtitle: Text(_activeModel.isEmpty ? 'None' : _activeModel.split('/').last),
        ),
        Divider(),
        ListTile(
          title: Text('Clear All Models', style: TextStyle(color: Colors.red)),
          subtitle: Text('Deletes all downloaded models from local storage'),
          trailing: _isClearing ? CircularProgressIndicator() : Icon(Icons.delete_forever, color: Colors.red),
          onTap: _isClearing ? null : _clearAllModels,
        ),
      ],
    );
  }
}
