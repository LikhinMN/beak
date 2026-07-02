import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'catalog_service.dart';

class LocalLLMServer {
  final int port;
  final String host;
  HttpServer? _server;
  final Set<String> _failedModels = {};
  
  LocalLLMServer({this.port = 8080, this.host = '127.0.0.1'});
  
  Future<void> start() async {
    final router = Router();

    router.post('/v1/chat/completions', (Request request) async {
      Map<String, dynamic> json;
      try {
        final payload = await request.readAsString();
        json = jsonDecode(payload) as Map<String, dynamic>;
      } catch (e) {
        return Response.badRequest(body: jsonEncode({"error": {"message": "Malformed JSON request body: $e"}}), headers: {'Content-Type': 'application/json'});
      }

      try {
        final messages = json['messages'] as List<dynamic>? ?? [];
        final stream = json['stream'] == true;
        
        if (messages.isEmpty) {
          return Response.badRequest(body: jsonEncode({"error": {"message": "Empty messages array"}}), headers: {'Content-Type': 'application/json'});
        }
        
        final requestedModelStr = json['model'] as String?;
        final prefs = await SharedPreferences.getInstance();
        final currentActiveUrl = prefs.getString('active_model_url') ?? '';
        String modelResponseName = "gemma-4-E2B-it";
        
        if (requestedModelStr != null && requestedModelStr.isNotEmpty) {
          final catalog = await CatalogService.fetchCatalog();
          final matches = catalog.where((m) => m.type == 'Generation' && (m.filename.toLowerCase().contains(requestedModelStr.toLowerCase()) || m.repo.toLowerCase().contains(requestedModelStr.toLowerCase())));
          
          if (matches.isEmpty) {
            return Response.notFound(jsonEncode({"error": {"message": "model '$requestedModelStr' not found, download it in Beak first"}}), headers: {'Content-Type': 'application/json'});
          }
          
          final matchedModel = matches.first;
          modelResponseName = requestedModelStr;
          
          if (matchedModel.downloadUrl != currentActiveUrl) {
            final installed = await FlutterGemma.listInstalledModels();
            if (!installed.contains(matchedModel.filename)) {
              return Response.notFound(jsonEncode({"error": {"message": "model '$requestedModelStr' not found, download it in Beak first"}}), headers: {'Content-Type': 'application/json'});
            }
            
            final dir = await getApplicationDocumentsDirectory();
            final path = '${dir.path}/${matchedModel.filename}';
            
            if (_failedModels.contains(path)) {
              return Response.internalServerError(
                body: jsonEncode({"error": {"message": "Model previously failed to initialize. Please check model format or device compatibility."}}),
                headers: {'Content-Type': 'application/json'}
              );
            }
            
            try {
              var builder = FlutterGemma.installModel(
                modelType: ModelType.gemma4,
                fileType: ModelFileType.litertlm,
              ).fromFile(path);
              await builder.install();
              await prefs.setString('active_model_url', matchedModel.downloadUrl);
            } catch (e) {
              _failedModels.add(path);
              return Response.internalServerError(body: jsonEncode({"error": {"message": "Failed to switch model: $e"}}), headers: {'Content-Type': 'application/json'});
            }
          }
        }
        
        // Get the active model and create a chat session
        InferenceChat chat;
        try {
          final model = await FlutterGemma.getActiveModel();
          chat = await model.createChat();
        } catch (e) {
          return Response.internalServerError(body: jsonEncode({"error": {"message": "Model not loaded or still downloading: $e"}}), headers: {'Content-Type': 'application/json'});
        }
        
        // Add all previous messages as context
        for (final msg in messages) {
          final content = msg['content']?.toString() ?? '';
          final role = msg['role']?.toString() ?? 'user';
          if (content.isNotEmpty) {
            await chat.addQuery(Message.text(text: content, isUser: role == 'user'));
          }
        }
        
        if (stream) {
          // Streaming response (SSE)
          final chatStream = chat.generateChatResponseAsync();
          
          final controller = StreamController<List<int>>();
          
          chatStream.listen((response) {
            if (response is TextResponse) {
              final token = response.token;
              final chunk = {
                "id": "chatcmpl-local",
                "object": "chat.completion.chunk",
                "created": DateTime.now().millisecondsSinceEpoch ~/ 1000,
                "model": modelResponseName,
                "choices": [
                  {
                    "index": 0,
                    "delta": {"content": token},
                    "finish_reason": null
                  }
                ]
              };
              controller.add(utf8.encode('data: ${jsonEncode(chunk)}\n\n'));
            }
          }, onDone: () {
            final doneChunk = {
              "id": "chatcmpl-local",
              "object": "chat.completion.chunk",
              "created": DateTime.now().millisecondsSinceEpoch ~/ 1000,
              "model": modelResponseName,
              "choices": [
                {
                  "index": 0,
                  "delta": {},
                  "finish_reason": "stop"
                }
              ]
            };
            controller.add(utf8.encode('data: ${jsonEncode(doneChunk)}\n\ndata: [DONE]\n\n'));
            controller.close();
          }, onError: (e) {
            controller.addError(e);
            controller.close();
          });
          
          return Response.ok(controller.stream, headers: {
            'Content-Type': 'text/event-stream',
            'Cache-Control': 'no-cache',
            'Connection': 'keep-alive',
          });
        } else {
          // Non-streaming response
          final response = await chat.generateChatResponse();
          String responseText = "";
          if (response is TextResponse) {
            responseText = response.token;
          }
          
          final openaiResponse = {
            "id": "chatcmpl-local",
            "object": "chat.completion",
            "created": DateTime.now().millisecondsSinceEpoch ~/ 1000,
            "model": modelResponseName,
            "choices": [
              {
                "index": 0,
                "message": {
                  "role": "assistant",
                  "content": responseText
                },
                "finish_reason": "stop"
              }
            ],
            "usage": {
              "prompt_tokens": 0,
              "completion_tokens": 0,
              "total_tokens": 0
            }
          };
          
          return Response.ok(jsonEncode(openaiResponse), headers: {'Content-Type': 'application/json'});
        }
      } catch (e) {
        // Catch out of memory or other inference errors gracefully
        return Response.internalServerError(body: jsonEncode({"error": {"message": "Inference error (possibly out of memory): $e"}}), headers: {'Content-Type': 'application/json'});
      }
    });

    router.post('/v1/embeddings', (Request request) async {
      Map<String, dynamic> json;
      try {
        final payload = await request.readAsString();
        json = jsonDecode(payload);
      } catch (e) {
        return Response.badRequest(
          body: jsonEncode({"error": {"message": "Invalid JSON payload"}}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      final input = json['input'];
      if (input == null || (input is! String && input is! List)) {
        return Response.badRequest(
          body: jsonEncode({"error": {"message": "'input' field is required and must be a string or array of strings"}}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      List<String> inputs = [];
      if (input is String) {
        inputs.add(input);
      } else {
        inputs = List<String>.from(input);
      }

      if (!FlutterGemma.hasActiveEmbedder()) {
        return Response.internalServerError(
          body: jsonEncode({"error": {"message": "No active embedding model loaded"}}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      try {
        final embedder = await FlutterGemma.getActiveEmbedder();
        final List<Map<String, dynamic>> data = [];
        
        for (int i = 0; i < inputs.length; i++) {
          String text = inputs[i];
          // Add default task prefix if not present
          if (!text.startsWith('task:')) {
            text = 'task: search result | query: $text';
          }
          
          final embedding = await embedder.generateEmbedding(text);
          data.add({
            "object": "embedding",
            "index": i,
            "embedding": embedding,
          });
        }

        return Response.ok(
          jsonEncode({
            "object": "list",
            "data": data,
            "model": "embeddinggemma-300m",
            "usage": {
              "prompt_tokens": 0,
              "total_tokens": 0
            }
          }),
          headers: {'Content-Type': 'application/json'},
        );
      } catch (e) {
        return Response.internalServerError(
          body: jsonEncode({"error": {"message": "Error generating embedding: $e"}}),
          headers: {'Content-Type': 'application/json'},
        );
      }
    });

    final handler = Pipeline().addMiddleware(logRequests()).addHandler(router.call);
    _server = await shelf_io.serve(handler, host, port);
    print('Server listening on http://${_server!.address.host}:${_server!.port}');
  }

  Future<void> stop() async {
    if (_server != null) {
      await _server!.close(force: true);
      _server = null;
      print('Server stopped');
    }
  }
}
