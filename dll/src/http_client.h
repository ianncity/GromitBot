#pragma once
#include <string>
#include <functional>

// ============================================================
// http_client.h — Async HTTP helpers wrapping cpp-httplib
// Used for talking to the local Ollama REST API.
// ============================================================

struct OllamaRequest {
    std::string model;      // e.g. "llama3"
    std::string prompt;
    std::string system;     // persona / system prompt
    bool        stream = false;
};

struct OllamaResponse {
    bool        success = false;
    std::string response;
    std::string error;
};

namespace HttpClient {
    // Synchronous POST to Ollama /api/generate
    OllamaResponse PostOllama(const OllamaRequest& req,
                               const std::string& host = "127.0.0.1",
                               int port = 11434,
                               int timeoutSec = 30);

    // Generic JSON POST — returns body string or empty on error
    std::string PostJSON(const std::string& host, int port,
                         const std::string& path,
                         const std::string& jsonBody,
                         int timeoutSec = 10);
}
