# Beak 

![Beak Banner](assets/image.png)

Beak is a premium, localized AI interface running strictly on-device using LiteRT inference and Flutter. Featuring an elegant gold-on-black design aesthetic, it runs completely offline while offering dynamic model switching and an OpenAI-compatible REST API for use as a background embedding/LLM backend by external RAG applications.

## Key Features

- **On-Device Inference**: Powered by `flutter_gemma`, executing large language models entirely locally (no cloud compute required).
- **RAG API Backend**: Hosts a local REST server running in the background to serve embeddings and chat completions for external applications.
- **Dynamic Model Switching**: Hot-swap between models and embedders downloaded seamlessly from Hugging Face.
- **Intelligent Streaming UI**: Progressive markdown rendering with native LaTeX mathematics support, a custom-animated "Thinking" indicator, and automatic repetition-loop safety nets.

---

## External RAG App Integration

Beak exposes an OpenAI-compatible HTTP server running locally on port `8080`. The server binds to `0.0.0.0` by default, meaning it is accessible over your local Wi-Fi network (LAN). By enabling the "Local HTTP Server" in Beak's Settings, you can use your phone as a dedicated local AI backend for other devices on your network (like your laptop).

To connect from another device, find your phone's local IP address (e.g., `192.168.1.15`) and use it in place of `localhost`.

### 1. Generating Embeddings

Use this endpoint to generate vector embeddings for your RAG documents.

**Endpoint**: `POST http://<YOUR_DEVICE_IP>:8080/v1/embeddings`

```bash
curl http://<YOUR_DEVICE_IP>:8080/v1/embeddings \
  -H "Content-Type: application/json" \
  -d '{"model":"embeddinggemma-300m","input":"your text here"}'
```

**Response**:
```json
{
  "object": "list",
  "data": [
    {
      "object": "embedding",
      "embedding": [0.012, -0.043, ...],
      "index": 0
    }
  ],
  "model": "active-embedding-model"
}
```

### 2. Chat Completions

Use this endpoint for passing retrieved RAG context and querying the active language model.

**Endpoint**: `POST http://<YOUR_DEVICE_IP>:8080/v1/chat/completions`

```bash
curl http://<YOUR_DEVICE_IP>:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"gemma-4-E2B-it","messages":[{"role":"user","content":"hello"}],"stream":false}'
```

**Response**:
```json
{
  "id": "chatcmpl-123",
  "object": "chat.completion",
  "created": 1719946800,
  "model": "active-generation-model",
  "choices": [
    {
      "index": 0,
      "message": {
        "role": "assistant",
        "content": "Transformers rely on a mechanism called self-attention..."
      },
      "finish_reason": "stop"
    }
  ]
}
```

### Important Notes for Integration

1. Beak uses a Foreground Service (`flutter_foreground_task`) to keep the server alive even when the app is backgrounded.
2. The user must manually enable the HTTP Server in Beak's Settings tab and have actively downloaded an embedding/generation model.
3. Beak will dynamically route API calls to the currently active model selected in its Catalog. If a requested operation relies on a model type not currently loaded, the API will safely return a descriptive HTTP 400 or 500 error. 
