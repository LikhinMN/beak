import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';

class LocalLLMServer {
  final int port;
  final String host;
  final String authToken;
  HttpServer? _server;
  
  LocalLLMServer({this.port = 8080, this.host = '127.0.0.1', required this.authToken});
  
  Future<void> start() async {
    final router = Router();

    router.post('/v1/chat/completions', (Request request) async {
      // 1. Basic Auth check
      final authHeader = request.headers['authorization'];
      if (authHeader != 'Bearer $authToken') {
        return Response.forbidden(jsonEncode({"error": {"message": "Invalid or missing Bearer token"}}), headers: {'Content-Type': 'application/json'});
      }

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
                "model": "gemma-4-E2B-it",
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
              "model": "gemma-4-E2B-it",
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
            "model": "gemma-4-E2B-it",
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
