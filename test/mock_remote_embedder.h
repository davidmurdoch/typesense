#pragma once

#include <string>

// Provide a fixed embedding response only for the lifetime of a unit test.
class MockRemoteEmbedder {
public:
    static inline std::string response;

    explicit MockRemoteEmbedder(const std::string& body) {
        response = body;
    }

    ~MockRemoteEmbedder() {
        response.clear();
    }

    MockRemoteEmbedder(const MockRemoteEmbedder&) = delete;
    MockRemoteEmbedder& operator=(const MockRemoteEmbedder&) = delete;
};
