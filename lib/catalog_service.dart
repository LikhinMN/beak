import 'dart:convert';
import 'package:http/http.dart' as http;

class RemoteModel {
  final String repo;
  final String filename;
  final int sizeBytes;
  final String description;
  final String type;
  final String? tokenizerFilename;

  RemoteModel({
    required this.repo,
    required this.filename,
    required this.sizeBytes,
    required this.description,
    this.type = 'Generation',
    this.tokenizerFilename,
  });

  String get downloadUrl => 'https://huggingface.co/$repo/resolve/main/$filename';
  String? get tokenizerUrl => tokenizerFilename != null ? 'https://huggingface.co/$repo/resolve/main/$tokenizerFilename' : null;
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

    // Fetch Generation Models
    for (final repo in repos) {
      final url = Uri.parse('https://huggingface.co/api/models/$repo/tree/main');
      try {
        final response = await http.get(url);
        if (response.statusCode == 200) {
          final List<dynamic> files = jsonDecode(response.body);
          for (final file in files) {
            final filename = file['path'] as String;
            if (filename.endsWith('.litertlm')) {
              if (filename.contains('Google_Tensor') || filename.contains('intel') || filename.contains('qualcomm') || filename.contains('-web')) {
                continue;
              }

              models.add(RemoteModel(
                repo: repo,
                filename: filename,
                sizeBytes: file['size'] as int,
                description: 'Full Vision/Audio Native Build',
                type: 'Generation',
              ));
            }
          }
        }
      } catch (e) {
        print('Error fetching catalog for $repo: $e');
      }
    }

    // Add Embedding Model explicitly
    models.add(RemoteModel(
      repo: 'litert-community/embeddinggemma-300m',
      filename: 'embeddinggemma-300M_seq512_mixed-precision.tflite',
      sizeBytes: 179132472, // From HF API
      description: 'EmbeddingGemma 300M (seq512)',
      type: 'Embedding',
      tokenizerFilename: 'sentencepiece.model',
    ));

    return models;
  }
}
