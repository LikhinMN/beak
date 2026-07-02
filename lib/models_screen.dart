import 'package:flutter/material.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:disk_space_2/disk_space_2.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'catalog_service.dart';

class ModelsScreen extends StatefulWidget {
  @override
  _ModelsScreenState createState() => _ModelsScreenState();
}

class _ModelsScreenState extends State<ModelsScreen> {
  List<RemoteModel> _models = [];
  bool _isLoading = true;
  String _activeUrl = '';
  
  Map<String, double> _downloadProgress = {};
  Map<String, String> _downloadStatus = {};

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _activeUrl = prefs.getString('active_model_url') ?? '';
    });

    final models = await CatalogService.fetchCatalog();
    setState(() {
      _models = models;
      _isLoading = false;
    });
  }

  Future<void> _handleModelTap(RemoteModel model) async {
    if (_activeUrl == model.downloadUrl) return; // Already active

    // Check disk space
    try {
      final freeSpace = await DiskSpace.getFreeDiskSpace;
      if (freeSpace != null && freeSpace < model.sizeMB) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Not enough free disk space! Need ${model.sizeMB.toStringAsFixed(0)} MB, but only ${freeSpace.toStringAsFixed(0)} MB available.')),
        );
        return;
      }
    } catch (e) {
      print('Could not check disk space: $e');
    }

    setState(() {
      _downloadStatus[model.downloadUrl] = 'Downloading...';
      _downloadProgress[model.downloadUrl] = 0.0;
    });

    try {
      await FlutterGemma.installModel(
        modelType: ModelType.gemma4,
        fileType: ModelFileType.litertlm,
      )
      .fromNetwork(model.downloadUrl)
      .withProgress((progress) {
        setState(() {
          _downloadProgress[model.downloadUrl] = progress.toDouble();
        });
      })
      .install();

      // Switch was successful
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('active_model_url', model.downloadUrl);
      
      // Note: By calling install(), flutter_gemma automatically sets it as the active model.
      // The server will use the newly active model on the very next /chat/completions request
      // without needing a restart!
      
      setState(() {
        _downloadStatus.remove(model.downloadUrl);
        _activeUrl = model.downloadUrl;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Model switched to ${model.filename}')),
      );

    } catch (e) {
      setState(() {
        _downloadStatus[model.downloadUrl] = 'Error: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Center(child: CircularProgressIndicator());
    }

    return ListView.builder(
      itemCount: _models.length,
      itemBuilder: (context, index) {
        final model = _models[index];
        final isActive = _activeUrl == model.downloadUrl;
        final progress = _downloadProgress[model.downloadUrl];
        final status = _downloadStatus[model.downloadUrl];

        return Card(
          margin: EdgeInsets.all(8),
          child: ListTile(
            title: Text(model.filename),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${model.repo}\n${model.sizeGB.toStringAsFixed(2)} GB - ${model.description}'),
                if (status != null) ...[
                  SizedBox(height: 8),
                  Text(status, style: TextStyle(color: Colors.blue)),
                  if (progress != null && progress > 0 && progress < 100)
                    LinearProgressIndicator(value: progress / 100),
                ]
              ],
            ),
            trailing: isActive
                ? Icon(Icons.check_circle, color: Colors.green)
                : IconButton(
                    icon: Icon(Icons.download),
                    onPressed: status != null && status.contains('Downloading') 
                        ? null 
                        : () => _handleModelTap(model),
                  ),
          ),
        );
      },
    );
  }
}
