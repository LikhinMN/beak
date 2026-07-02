import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'server.dart';
import 'main.dart';
import 'beak_theme.dart';

class SettingsScreen extends StatefulWidget {
  @override
  _SettingsScreenState createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _serverEnabled = true;
  String _activeModel = 'None';
  String _activeEmbeddingModel = 'None';
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
      _activeEmbeddingModel = prefs.getString('active_embedding_url') ?? 'None';
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
      await prefs.remove('active_embedding_url');
      setState(() {
        _activeModel = 'None';
        _activeEmbeddingModel = 'None';
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
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: EdgeInsets.all(16),
        children: [
        Card(
          margin: EdgeInsets.only(bottom: 16),
          color: Color(0xFF161616),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: SwitchListTile(
              title: Text('Enable Local HTTP Server', style: TextStyle(color: BeakTheme.primaryText)),
              subtitle: Text(
                _serverEnabled ? 'Running on port 8080\nEndpoints: /v1/chat/completions, /v1/embeddings' : 'Stopped',
                style: TextStyle(color: BeakTheme.secondaryText)
              ),
              value: _serverEnabled,
              activeColor: BeakTheme.goldLight,
              onChanged: _toggleServer,
            ),
          ),
        ),
        Card(
          margin: EdgeInsets.only(bottom: 16),
          color: Color(0xFF161616),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Column(
              children: [
                ListTile(
                  title: Text('Current Generation Model', style: TextStyle(color: BeakTheme.primaryText)),
                  subtitle: Text(
                    _activeModel.isEmpty || _activeModel == 'None' ? 'None' : _activeModel.split('/').last,
                    style: TextStyle(color: BeakTheme.goldLight)
                  ),
                ),
                Divider(color: Colors.grey[800], height: 1),
                ListTile(
                  title: Text('Current Embedding Model', style: TextStyle(color: BeakTheme.primaryText)),
                  subtitle: Text(
                    _activeEmbeddingModel.isEmpty || _activeEmbeddingModel == 'None' ? 'None' : _activeEmbeddingModel.split('/').last,
                    style: TextStyle(color: BeakTheme.goldLight)
                  ),
                ),
              ],
            ),
          ),
        ),
        Card(
          color: Color(0xFF161616),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: ListTile(
              title: Text('Clear All Local Models', style: TextStyle(color: Colors.redAccent)),
              subtitle: Text('Deletes all downloaded weights to free up space', style: TextStyle(color: BeakTheme.secondaryText)),
              trailing: _isClearing ? CircularProgressIndicator(color: Colors.redAccent) : Icon(Icons.delete_forever, color: Colors.redAccent),
              onTap: _isClearing ? null : _clearAllModels,
            ),
          ),
        ),
      ],
    ),
    );
  }
}
