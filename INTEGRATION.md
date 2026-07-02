# Integrating with Gemma Local Server

The Gemma Local Server provides an OpenAI-compatible HTTP endpoint (`/v1/chat/completions`) that runs entirely on-device. This allows any external RAG application to securely query the local model without any cloud dependency.

## Prerequisites
1. Ensure the server is toggled **ON** in the Settings tab.
2. Ensure a model is actively downloaded and loaded via the Catalog tab.

## Endpoint Details
* **Base URL:** `http://127.0.0.1:8080`
* **Path:** `/v1/chat/completions`
* **Method:** `POST`
* **Headers:** 
  * `Content-Type: application/json`

## 1. Non-Streaming Example

### cURL Request
```bash
curl http://127.0.0.1:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "messages": [
      {"role": "user", "content": "What is Retrieval-Augmented Generation?"}
    ],
    "stream": false
  }'
```

### JSON Response
```json
{
  "id": "chatcmpl-local",
  "object": "chat.completion",
  "created": 1714578123,
  "model": "gemma-4-E2B-it",
  "choices": [
    {
      "index": 0,
      "message": {
        "role": "assistant",
        "content": "Retrieval-Augmented Generation (RAG) is a technique that..."
      },
      "finish_reason": "stop"
    }
  ],
  "usage": {
    "prompt_tokens": 0,
    "completion_tokens": 0,
    "total_tokens": 0
  }
}
```

## 2. Streaming Example (SSE)

### cURL Request
```bash
curl http://127.0.0.1:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "messages": [
      {"role": "user", "content": "Explain RAG step by step."}
    ],
    "stream": true
  }'
```

### SSE Response
```text
data: {"id":"chatcmpl-local","object":"chat.completion.chunk","created":1714578125,"model":"gemma-4-E2B-it","choices":[{"index":0,"delta":{"content":"Step "},"finish_reason":null}]}

data: {"id":"chatcmpl-local","object":"chat.completion.chunk","created":1714578125,"model":"gemma-4-E2B-it","choices":[{"index":0,"delta":{"content":"1:"},"finish_reason":null}]}

data: {"id":"chatcmpl-local","object":"chat.completion.chunk","created":1714578127,"model":"gemma-4-E2B-it","choices":[{"index":0,"delta":{},"finish_reason":"stop"}]}

data: [DONE]
```

## Error Handling
The server provides graceful error responses. For instance:
- **400 Bad Request:** Malformed JSON body or empty `messages` array.
- **500 Internal Server Error:** Returned if the model is still downloading or if an out-of-memory exception occurs during inference. 
```json
{
  "error": {
    "message": "Model not loaded or still downloading: ..."
  }
}
```
