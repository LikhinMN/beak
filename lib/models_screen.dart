import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:disk_space_2/disk_space_2.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'catalog_service.dart';
import 'beak_theme.dart';

class ModelsScreen extends StatefulWidget {
  @override
  _ModelsScreenState createState() => _ModelsScreenState();
}

class _ModelsScreenState extends State<ModelsScreen> {
  List<RemoteModel> _models = [];
  bool _isLoading = true;
  String _activeUrl = '';
  String _activeEmbeddingUrl = '';
  List<String> _installedModelIds = [];
  double _freeDiskSpaceMB = 0.0;
  double _totalSpaceMB = 0.0;
  
  Map<String, double> _downloadProgress = {};
  Map<String, String> _downloadStatus = {};
  Map<String, CancelToken> _cancelTokens = {};

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    final activeUrl = prefs.getString('active_model_url') ?? '';
    final activeEmbeddingUrl = prefs.getString('active_embedding_url') ?? '';
    final models = await CatalogService.fetchCatalog();
    final rawInstalled = await FlutterGemma.listInstalledModels();
    final dir = await getApplicationDocumentsDirectory();
    List<String> validInstalled = [];

    for (var filename in rawInstalled) {
      final file = File('${dir.path}/$filename');
      if (await file.exists()) {
        final length = await file.length();
        final model = models.firstWhere((m) => m.filename == filename, orElse: () => RemoteModel(repo: '', filename: '', sizeBytes: length, description: ''));
        // Allow a small margin (e.g. 5%) because of possible sparse allocations or metadata
        if (model.repo.isEmpty || length >= (model.sizeBytes * 0.95).toInt()) {
          validInstalled.add(filename);
        } else {
          print('Incomplete model $filename: $length bytes / ${model.sizeBytes} bytes expected');
        }
      }
    }

    double freeSpace = 0.0;
    double totalSpace = 0.0;
    try {
      freeSpace = await DiskSpace.getFreeDiskSpace ?? 0.0;
      totalSpace = await DiskSpace.getTotalDiskSpace ?? 0.0;
    } catch (e) {
      print('Could not get disk space: $e');
    }

    setState(() {
      _activeUrl = activeUrl;
      _activeEmbeddingUrl = activeEmbeddingUrl;
      _models = models;
      _installedModelIds = validInstalled;
      _freeDiskSpaceMB = freeSpace;
      _totalSpaceMB = totalSpace;
      _isLoading = false;
    });
  }

  void _cancelDownload(RemoteModel model) {
    if (_cancelTokens.containsKey(model.downloadUrl)) {
      _cancelTokens[model.downloadUrl]!.cancel('User cancelled');
      setState(() {
        _cancelTokens.remove(model.downloadUrl);
        _downloadStatus.remove(model.downloadUrl);
        _downloadProgress.remove(model.downloadUrl);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Download cancelled for ${model.filename}')),
      );
    }
  }

  Future<void> _deleteModel(RemoteModel model) async {
    if ((model.type == 'Generation' && _activeUrl == model.downloadUrl) ||
        (model.type == 'Embedding' && _activeEmbeddingUrl == model.downloadUrl)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Cannot delete the active model while it is loaded. Switch to another model first.')),
      );
      return;
    }

    bool confirm = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete Model?'),
        content: Text('Are you sure you want to delete ${model.filename}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text('CANCEL')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: Text('DELETE', style: TextStyle(color: Colors.red))),
        ],
      ),
    ) ?? false;

    if (!confirm) return;

    setState(() {
      _isLoading = true;
    });

    try {
      await FlutterGemma.uninstallModel(model.filename);
      await _loadData(); // Refresh data
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${model.filename} deleted successfully.')),
      );
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to delete model: $e')),
      );
    }
  }

  Future<void> _handleModelTap(RemoteModel model) async {
    if (model.type == 'Generation' && _activeUrl == model.downloadUrl) return;
    if (model.type == 'Embedding' && _activeEmbeddingUrl == model.downloadUrl) return;

    // If not installed yet, check disk space before attempting
    if (!_installedModelIds.contains(model.filename)) {
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

      final hfToken = dotenv.env['HF_TOKEN'] ?? '';
      
      try {
        final headers = hfToken.isNotEmpty ? {'Authorization': 'Bearer $hfToken'} : <String, String>{};
        final response = await http.head(
          Uri.parse(model.downloadUrl), 
          headers: headers
        ).timeout(const Duration(seconds: 15));
        
        if (response.statusCode == 401 || response.statusCode == 403) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("This model requires a Hugging Face account. Add your access token in Settings, and make sure you've accepted the model's license on huggingface.co first."),
              duration: Duration(seconds: 5),
            ),
          );
          return;
        } else if (response.statusCode == 404) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Not Found (404): The repository or file no longer exists.')),
          );
          return;
        } else if (response.statusCode >= 500) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Server Error (${response.statusCode}): Hugging Face is currently unreachable.')),
          );
          return;
        }
      } on TimeoutException {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Timeout: The request to Hugging Face timed out. Please check your connection.')),
        );
        return;
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Network Error: Could not reach Hugging Face. ($e)')),
        );
        return;
      }
    }

    final cancelToken = CancelToken();

    setState(() {
      _downloadStatus[model.downloadUrl] = _installedModelIds.contains(model.filename) ? 'Loading...' : 'Downloading...';
      _downloadProgress[model.downloadUrl] = 0.0;
      _cancelTokens[model.downloadUrl] = cancelToken;
    });

    try {
      final hfToken = dotenv.env['HF_TOKEN'] ?? '';

      if (model.type == 'Embedding') {
        var builder = FlutterGemma.installEmbedder()
          .modelFromNetwork(model.downloadUrl, token: hfToken.isNotEmpty ? hfToken : null)
          .tokenizerFromNetwork(model.tokenizerUrl!, token: hfToken.isNotEmpty ? hfToken : null)
          .withCancelToken(cancelToken)
          .withModelProgress((progress) {
            setState(() {
              _downloadProgress[model.downloadUrl] = progress.toDouble();
            });
          });
        
        await builder.install();
      } else {
        var builder = FlutterGemma.installModel(
          modelType: ModelType.gemma4,
          fileType: ModelFileType.litertlm,
        )
        .fromNetwork(model.downloadUrl, token: hfToken.isNotEmpty ? hfToken : null)
        .withCancelToken(cancelToken)
        .withProgress((progress) {
          setState(() {
            _downloadProgress[model.downloadUrl] = progress.toDouble();
          });
        });

        await builder.install();
      }

      final prefs = await SharedPreferences.getInstance();
      if (model.type == 'Embedding') {
        await prefs.setString('active_embedding_url', model.downloadUrl);
      } else {
        await prefs.setString('active_model_url', model.downloadUrl);
      }
      
      await _loadData(); // Reload stats

      setState(() {
        _cancelTokens.remove(model.downloadUrl);
        _downloadStatus.remove(model.downloadUrl);
        if (model.type == 'Embedding') {
          _activeEmbeddingUrl = model.downloadUrl;
        } else {
          _activeUrl = model.downloadUrl;
        }
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Model switched to ${model.filename}')),
      );

    } catch (e) {
      if (e is DownloadCancelledException) {
        return;
      }
      setState(() {
        _cancelTokens.remove(model.downloadUrl);
        _downloadStatus[model.downloadUrl] = 'Error: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Catalog')),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    double totalUsedMB = 0;
    for (var m in _models) {
      if (_installedModelIds.contains(m.filename)) {
        totalUsedMB += m.sizeMB;
      }
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Catalog')),
      body: Column(
        children: [
        Container(
          padding: EdgeInsets.all(16),
          color: Color(0xFF111111),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Storage Usage', style: TextStyle(fontWeight: FontWeight.bold, color: BeakTheme.primaryText)),
              SizedBox(height: 8),
              LinearProgressIndicator(
                value: _totalSpaceMB > 0 ? totalUsedMB / _totalSpaceMB : 0,
                backgroundColor: Colors.grey[800],
                color: BeakTheme.goldLight,
              ),
              SizedBox(height: 4),
              Text(
                '${(totalUsedMB / 1024).toStringAsFixed(2)} GB used of ${(_totalSpaceMB / 1024).toStringAsFixed(2)} GB total',
                style: TextStyle(color: BeakTheme.secondaryText, fontSize: 12),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: _models.length,
            itemBuilder: (context, index) {
              final model = _models[index];
              final isActive = (model.type == 'Generation' && _activeUrl == model.downloadUrl) ||
                               (model.type == 'Embedding' && _activeEmbeddingUrl == model.downloadUrl);
              final isInstalled = _installedModelIds.contains(model.filename);
              final progress = _downloadProgress[model.downloadUrl];
              final status = _downloadStatus[model.downloadUrl];
              final isDownloading = status != null && status.contains('Downloading');

              return Card(
                margin: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: isActive ? BorderSide(color: BeakTheme.goldLight.withValues(alpha: 0.5), width: 1) : BorderSide.none,
                ),
                color: Color(0xFF161616),
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(model.filename, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16, color: BeakTheme.primaryText)),
                          ),
                          if (isActive)
                            Container(
                              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                gradient: BeakTheme.goldGradient,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text('ACTIVE', style: TextStyle(color: Colors.black, fontSize: 10, fontWeight: FontWeight.bold)),
                            )
                          else if (isInstalled)
                            Container(
                              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.grey[800],
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text('INSTALLED', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                            )
                        ],
                      ),
                      SizedBox(height: 8),
                      Text('${model.repo}', style: TextStyle(color: BeakTheme.secondaryText)),
                      Text('${model.sizeGB.toStringAsFixed(2)} GB - ${model.description}', style: TextStyle(color: BeakTheme.secondaryText)),
                      if (status != null) ...[
                        SizedBox(height: 12),
                        Text(status, style: TextStyle(color: BeakTheme.goldLight)),
                        if (progress != null && progress > 0 && progress < 100)
                          Padding(
                            padding: const EdgeInsets.only(top: 8.0),
                            child: BeakTheme.applyGradient(LinearProgressIndicator(value: progress / 100, backgroundColor: Colors.grey[800])),
                          ),
                      ],
                      SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          if (isInstalled && !isActive)
                            TextButton.icon(
                              icon: Icon(Icons.delete, color: Colors.redAccent, size: 18),
                              label: Text('DELETE', style: TextStyle(color: Colors.redAccent)),
                              onPressed: () => _deleteModel(model),
                            ),
                          if (!isActive)
                            isDownloading
                                ? TextButton.icon(
                                    icon: Icon(Icons.cancel, color: Colors.redAccent, size: 18),
                                    label: Text('CANCEL', style: TextStyle(color: Colors.redAccent)),
                                    onPressed: () => _cancelDownload(model),
                                  )
                                : ElevatedButton.icon(
                                    icon: Icon(isInstalled ? Icons.play_arrow : Icons.download, color: Colors.black, size: 18),
                                    label: Text(isInstalled ? 'LOAD' : 'DOWNLOAD', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                                    style: ElevatedButton.styleFrom(
                                      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                      backgroundColor: BeakTheme.goldLight, // Fallback if no gradient
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                    ),
                                    onPressed: () => _handleModelTap(model),
                                  ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    ),
    );
  }
}
