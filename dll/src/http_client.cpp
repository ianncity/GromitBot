#include "http_client.h"
// NOTE: Place the real httplib.h (single-header) in dll/include/ before building.
// Download: https://raw.githubusercontent.com/yhirose/cpp-httplib/master/httplib.h
#include "../include/httplib.h"
#include <sstream>

// ============================================================
// http_client.cpp
// ============================================================

namespace HttpClient {

// Minimal JSON serialiser (avoids pulling in nlohmann for a small project)
static std::string BuildOllamaJSON(const OllamaRequest& req) {
    // Escape a string for JSON embedding
    auto esc = [](const std::string& s) -> std::string {
        std::string out;
        out.reserve(s.size() + 8);
        for (char c : s) {
            switch (c) {
            case '"':  out += "\\\""; break;
            case '\\': out += "\\\\"; break;
            case '\n': out += "\\n";  break;
            case '\r': out += "\\r";  break;
            case '\t': out += "\\t";  break;
            default:   out += c;      break;
            }
        }
        return out;
    };

    std::ostringstream ss;
    ss << "{"
       << "\"model\":\"" << esc(req.model) << "\","
       << "\"prompt\":\"" << esc(req.prompt) << "\","
       << "\"system\":\"" << esc(req.system) << "\","
       << "\"stream\":" << (req.stream ? "true" : "false")
       << "}";
    return ss.str();
}

// Very small JSON value extractor — pulls the first "response":"..." field
static std::string ExtractResponseField(const std::string& json) {
    const std::string key = "\"response\":\"";
    auto pos = json.find(key);
    if (pos == std::string::npos) return json; // field not found — return raw body
    size_t start = pos + key.size();
    std::string out;
    bool escape = false;
    for (size_t i = start; i < json.size(); ++i) {
        char c = json[i];
        if (escape) { out += c; escape = false; continue; }
        if (c == '\\') { escape = true; continue; }
        if (c == '"') break;
        out += c;
    }
    return out;
}

OllamaResponse PostOllama(const OllamaRequest& req,
                           const std::string& host,
                           int port,
                           int timeoutSec) {
    OllamaResponse result;
    try {
        httplib::Client cli(host, port);
        cli.set_connection_timeout(timeoutSec);
        cli.set_read_timeout(timeoutSec);

        std::string body = BuildOllamaJSON(req);
        auto res = cli.Post("/api/generate", body, "application/json");
        if (!res) {
            result.error = "No response from Ollama (connection refused or timeout)";
            return result;
        }
        if (res->status != 200) {
            result.error = "HTTP " + std::to_string(res->status);
            return result;
        }
        result.success  = true;
        result.response = ExtractResponseField(res->body);
    } catch (const std::exception& e) {
        result.error = e.what();
    } catch (...) {
        result.error = "Unknown exception in PostOllama";
    }
    return result;
}

std::string PostJSON(const std::string& host, int port,
                     const std::string& path,
                     const std::string& jsonBody,
                     int timeoutSec) {
    try {
        httplib::Client cli(host, port);
        cli.set_connection_timeout(timeoutSec);
        cli.set_read_timeout(timeoutSec);
        auto res = cli.Post(path.c_str(), jsonBody, "application/json");
        if (res && res->status == 200) return res->body;
    } catch (...) {}
    return "";
}

} // namespace HttpClient
