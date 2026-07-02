import 'dart:convert';
import 'package:http/http.dart' as http;

class RemoteModel {
  final String repo;
  final String filename;
  final int sizeBytes;
  final String description;

  RemoteModel({
    required this.repo,
    required this.filename,
    required this.sizeBytes,
    required this.description,
  });

  String get downloadUrl => 'https://huggingface.co/$repo/resolve/main/$filename';
  double get sizeMB => sizeBytes / (1024 * 1024);
  double get sizeGB => sizeBytes / (1024 * 1024 * 1024);
}

class CatalogService {
  static const List<String> repos = [
    'litert-community/gemma-4-E2B-it-litert-lm',
    'litert-community/gemma-4-E4B-it-litert-lm',
  ];

  static Future<List<RemoteModel>> fetchCatalog() async {
    final List<RemoteModel> models = [];

    for (final repo in repos) {
      final url = Uri.parse('https://huggingface.co/api/models/$repo/tree/main');
      try {
        final response = await http.get(url);
        if (response.statusCode == 200) {
          final List<dynamic> files = jsonDecode(response.body);
          for (final file in files) {
            final filename = file['path'] as String;
            if (filename.endsWith('.litertlm')) {
              // Filter out hardware-specific builds
              if (filename.contains('Google_Tensor') || filename.contains('intel') || filename.contains('qualcomm')) {
                continue;
              }

              String description = 'Generic Mobile Build';
              if (filename.contains('-web')) {
                description = 'Text-Only Web Build';
              } else {
                description = 'Full Vision/Audio Build';
              }

              models.add(RemoteModel(
                repo: repo,
                filename: filename,
                sizeBytes: file['size'] as int,
                description: description,
              ));
            }
          }
        }
      } catch (e) {
        print('Error fetching catalog for $repo: $e');
      }
    }
    return models;
  }
}
