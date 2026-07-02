import 'package:flutter/material.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma_litertlm/flutter_gemma_litertlm.dart';
import 'dart:io';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  await FlutterGemma.initialize(
    inferenceEngines: [LiteRtLmEngine()],
  );

  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  String _status = "Initializing...";

  @override
  void initState() {
    super.initState();
    _runGemma();
  }

  Future<void> _runGemma() async {
    try {
      final modelUrl = "https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/resolve/main/gemma-4-E2B-it.litertlm";
      
      setState(() { _status = "Downloading/Loading model... This might take a while!"; });
      print("Downloading model from $modelUrl");
      
      await FlutterGemma.installModel(
        modelType: ModelType.gemma4,
        fileType: ModelFileType.litertlm,
      ).fromNetwork(modelUrl).install();
      
      setState(() { _status = "Getting active model..."; });
      
      final model = await FlutterGemma.getActiveModel(maxTokens: 1024);
      final chat = await model.createChat();
      
      setState(() { _status = "Model initialized. Generating response..."; });
      
      print("Sending prompt to model...");
      await chat.addQuery(Message.text(text: "Hello! Who are you?", isUser: true));
      final response = await chat.generateChatResponse();
      
      String responseText = "No text";
      if (response is TextResponse) {
        responseText = response.token;
      }
      
      setState(() { _status = "Response: $responseText"; });
      print("FlutterGemma Response: $responseText");
      
    } catch (e) {
      setState(() { _status = "Error: $e"; });
      print("FlutterGemma Error: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('flutter_gemma Test')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: SingleChildScrollView(child: Text(_status)),
          ),
        ),
      ),
    );
  }
}
