import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:beak/server.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MyHttpOverrides extends HttpOverrides {}

void main() {
  LocalLLMServer? server;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    HttpOverrides.global = MyHttpOverrides();
    SharedPreferences.setMockInitialValues({});
    // Initialize flutter gemma if needed
    try {
      await FlutterGemma.initialize();
    } catch (e) {
      // Ignore if it fails in test environment
    }
    server = LocalLLMServer(port: 8085);
    await server!.start();
  });

  tearDownAll(() async {
    await server?.stop();
  });

  test('Test /v1/chat/completions endpoint with missing model', () async {
    final response = await http.post(
      Uri.parse('http://127.0.0.1:8085/v1/chat/completions'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        "model": "non-existent-model",
        "messages": [
          {"role": "user", "content": "Hello"}
        ]
      }),
    );

    final json = jsonDecode(response.body);
    print('Response body: ${response.body}');
    expect(response.statusCode, 404);
    expect(json['error']['message'], contains('not found'));
  });

  test('Test /v1/embeddings endpoint', () async {
    final response = await http.post(
      Uri.parse('http://127.0.0.1:8085/v1/embeddings'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        "input": "Hello"
      }),
    );

    // Expect 500 because flutter_gemma has no active embedder in the test environment
    expect(response.statusCode, 500);
    final json = jsonDecode(response.body);
    expect(json['error']['message'], contains('No active embedding model loaded'));
  });
}
