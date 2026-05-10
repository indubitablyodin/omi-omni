import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as status;

import '../models/conversation.dart';

/// Omi Omni API Client
/// Handles all communication with the self-hosted backend
class OmiApiClient {
  final String baseUrl;
  final String apiKey;
  final http.Client _httpClient;
  
  // WebSocket connection
  WebSocketChannel? _audioWebSocket;
  Stream<dynamic>? _audioStream;
  
  // Connection state
  bool _isConnected = false;
  String? _currentConversationId;
  
  // Callbacks
  Function(AudioProgressMessage)? onAudioProgress;
  Function(AudioCompleteMessage)? onAudioComplete;
  Function(ErrorMessage)? onAudioError;
  Function(dynamic)? onAudioMessage;

  OmiApiClient({
    required this.baseUrl,
    required this.apiKey,
    http.Client? httpClient,
  }) : _httpClient = httpClient ?? http.Client();

  // ===========================================================================
  // HTTP API Methods
  // ===========================================================================

  /// Check backend health
  Future<HealthResponse> healthCheck() async {
    try {
      final response = await _get('/health');
      return HealthResponse.fromJson(jsonDecode(response.body));
    } catch (e) {
      throw ApiException('Failed to check health: $e');
    }
  }

  /// Get list of conversations
  Future<List<Conversation>> listConversations({
    int limit = 20,
    int offset = 0,
  }) async {
    try {
      final response = await _get('/v1/conversations?limit=$limit&offset=$offset');
      final List<dynamic> data = jsonDecode(response.body) as List<dynamic>;
      return data.map((json) => Conversation.fromApiResponse(json)).toList();
    } catch (e) {
      throw ApiException('Failed to list conversations: $e');
    }
  }

  /// Get a specific conversation
  Future<Conversation> getConversation(String conversationId) async {
    try {
      final response = await _get('/v1/conversations/$conversationId');
      return Conversation.fromApiResponse(jsonDecode(response.body));
    } catch (e) {
      throw ApiException('Failed to get conversation: $e');
    }
  }

  /// Delete a conversation
  Future<void> deleteConversation(String conversationId) async {
    try {
      await _delete('/v1/conversations/$conversationId');
    } catch (e) {
      throw ApiException('Failed to delete conversation: $e');
    }
  }

  /// List memories
  Future<List<Memory>> listMemories({int limit = 50}) async {
    try {
      final response = await _get('/v1/memories?limit=$limit');
      final List<dynamic> data = jsonDecode(response.body) as List<dynamic>;
      return data.map((json) => Memory.fromApiResponse(json)).toList();
    } catch (e) {
      throw ApiException('Failed to list memories: $e');
    }
  }

  /// Search memories
  Future<List<MemorySearchResult>> searchMemories(String query, {int limit = 10}) async {
    try {
      final response = await _get('/v1/memories/search?q=$query&limit=$limit');
      final List<dynamic> data = jsonDecode(response.body) as List<dynamic>;
      return data.map((json) => MemorySearchResult.fromJson(json)).toList();
    } catch (e) {
      throw ApiException('Failed to search memories: $e');
    }
  }

  /// Chat with conversation history
  Future<ChatResponse> chat(String message, {int contextLimit = 5}) async {
    try {
      final request = ChatRequest(
        message: message,
        contextLimit: contextLimit,
      );
      final response = await _post('/v1/chat', body: request.toJson());
      return ChatResponse.fromJson(jsonDecode(response.body));
    } catch (e) {
      throw ApiException('Failed to chat: $e');
    }
  }

  /// Get statistics
  Future<StatsResponse> getStats() async {
    try {
      final response = await _get('/v1/stats');
      return StatsResponse.fromJson(jsonDecode(response.body));
    } catch (e) {
      throw ApiException('Failed to get stats: $e');
    }
  }

  /// Get configuration
  Future<Map<String, dynamic>> getConfig() async {
    try {
      final response = await _get('/v1/config');
      return jsonDecode(response.body) as Map<String, dynamic>;
    } catch (e) {
      throw ApiException('Failed to get config: $e');
    }
  }

  /// List audio files
  Future<List<String>> listAudioFiles() async {
    try {
      final response = await _get('/v1/audio');
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return (data['files'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList() ?? [];
    } catch (e) {
      throw ApiException('Failed to list audio files: $e');
    }
  }

  /// Get audio file
  Future<Uint8List> getAudioFile(String fileName) async {
    try {
      final response = await _get('/v1/audio/$fileName');
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return Uint8List.fromList((data['audio'] as String).hexToBytes());
    } catch (e) {
      throw ApiException('Failed to get audio file: $e');
    }
  }

  // ===========================================================================
  // WebSocket Audio Streaming
  // ===========================================================================

  /// Connect to audio WebSocket
  Future<void> connectAudioWebSocket() async {
    if (_isConnected) {
      return; // Already connected
    }

    try {
      final wsUrl = '$baseUrl/ws/audio';
      
      // Add API key to headers
      final headers = {
        'Authorization': 'Bearer $apiKey',
      };
      
      _audioWebSocket = WebSocketChannel.connect(
        Uri.parse(wsUrl),
        headers: headers,
      );
      
      _audioStream = _audioWebSocket?.stream;
      _isConnected = true;
      
      // Listen to messages
      _audioStream?.listen(
        (message) => _handleWebSocketMessage(message),
        onError: (error) => _handleWebSocketError(error),
        onDone: _handleWebSocketDone,
        cancelOnError: false,
      );
      
      debugPrint('Audio WebSocket connected');
    } catch (e) {
      _isConnected = false;
      throw ApiException('Failed to connect WebSocket: $e');
    }
  }

  /// Disconnect from audio WebSocket
  Future<void> disconnectAudioWebSocket() async {
    if (!_isConnected) {
      return; // Already disconnected
    }

    try {
      await _audioWebSocket?.sink.close(status.goingAway);
      _audioWebSocket = null;
      _audioStream = null;
      _isConnected = false;
      _currentConversationId = null;
      debugPrint('Audio WebSocket disconnected');
    } catch (e) {
      debugPrint('Error disconnecting WebSocket: $e');
      _audioWebSocket = null;
      _audioStream = null;
      _isConnected = false;
    }
  }

  /// Check if WebSocket is connected
  bool get isAudioConnected => _isConnected;

  /// Get current conversation ID
  String? get currentConversationId => _currentConversationId;

  /// Send audio data to WebSocket
  Future<void> sendAudioData(Uint8List audioData) async {
    if (!_isConnected) {
      throw ApiException('WebSocket is not connected');
    }

    try {
      _audioWebSocket?.sink.add(audioData);
    } catch (e) {
      throw ApiException('Failed to send audio data: $e');
    }
  }

  /// Start a new audio conversation
  Future<void> startAudioConversation() async {
    if (!_isConnected) {
      await connectAudioWebSocket();
    }

    try {
      final message = jsonEncode({
        'type': 'start',
      });
      _audioWebSocket?.sink.add(message);
      debugPrint('Started new audio conversation');
    } catch (e) {
      throw ApiException('Failed to start audio conversation: $e');
    }
  }

  /// Stop current audio conversation
  Future<void> stopAudioConversation() async {
    if (!_isConnected) {
      return;
    }

    try {
      final message = jsonEncode({
        'type': 'stop',
      });
      _audioWebSocket?.sink.add(message);
      debugPrint('Stopped audio conversation');
    } catch (e) {
      debugPrint('Error stopping audio conversation: $e');
    }
  }

  /// Send ping to keep connection alive
  Future<void> sendPing() async {
    if (!_isConnected) {
      return;
    }

    try {
      final message = jsonEncode({
        'type': 'ping',
      });
      _audioWebSocket?.sink.add(message);
    } catch (e) {
      debugPrint('Error sending ping: $e');
    }
  }

  // ===========================================================================
  // Private Methods
  // ===========================================================================

  /// Handle HTTP GET request
  Future<http.Response> _get(String path) async {
    final url = Uri.parse('$baseUrl$path');
    final response = await _httpClient.get(
      url,
      headers: _getHeaders(),
    );
    
    if (response.statusCode >= 400) {
      throw ApiException('${response.statusCode}: ${response.body}');
    }
    
    return response;
  }

  /// Handle HTTP POST request
  Future<http.Response> _post(String path, {dynamic body}) async {
    final url = Uri.parse('$baseUrl$path');
    final response = await _httpClient.post(
      url,
      headers: _getHeaders(),
      body: jsonEncode(body),
    );
    
    if (response.statusCode >= 400) {
      throw ApiException('${response.statusCode}: ${response.body}');
    }
    
    return response;
  }

  /// Handle HTTP DELETE request
  Future<http.Response> _delete(String path) async {
    final url = Uri.parse('$baseUrl$path');
    final response = await _httpClient.delete(
      url,
      headers: _getHeaders(),
    );
    
    if (response.statusCode >= 400) {
      throw ApiException('${response.statusCode}: ${response.body}');
    }
    
    return response;
  }

  /// Get HTTP headers with API key
  Map<String, String> _getHeaders() {
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $apiKey',
    };
  }

  /// Handle WebSocket message
  void _handleWebSocketMessage(dynamic message) {
    if (message is String) {
      try {
        final json = jsonDecode(message) as Map<String, dynamic>;
        final type = json['type'] as String?;
        
        switch (type) {
          case 'ack':
            // Acknowledgment message
            if (onAudioMessage != null) {
              onAudioMessage!(message);
            }
            break;
            
          case 'started':
            _currentConversationId = json['conversation_id'] as String?;
            if (onAudioMessage != null) {
              onAudioMessage!(message);
            }
            break;
            
          case 'progress':
            if (onAudioProgress != null) {
              onAudioProgress!(AudioProgressMessage.fromJson(json));
            }
            if (onAudioMessage != null) {
              onAudioMessage!(message);
            }
            break;
            
          case 'complete':
            if (onAudioComplete != null) {
              onAudioComplete!(AudioCompleteMessage.fromJson(json));
            }
            if (onAudioMessage != null) {
              onAudioMessage!(message);
            }
            _currentConversationId = null;
            break;
            
          case 'error':
            if (onAudioError != null) {
              onAudioError!(ErrorMessage.fromJson(json));
            }
            if (onAudioMessage != null) {
              onAudioMessage!(message);
            }
            _currentConversationId = null;
            break;
            
          case 'pong':
            // Ping response
            break;
            
          default:
            if (onAudioMessage != null) {
              onAudioMessage!(message);
            }
        }
      } catch (e) {
        debugPrint('Error parsing WebSocket message: $e');
      }
    }
  }

  /// Handle WebSocket error
  void _handleWebSocketError(dynamic error) {
    debugPrint('WebSocket error: $error');
    _isConnected = false;
    
    // Try to reconnect
    Future.delayed(const Duration(seconds: 5), () {
      if (!_isConnected) {
        connectAudioWebSocket().catchError((e) {
          debugPrint('Reconnect failed: $e');
        });
      }
    });
  }

  /// Handle WebSocket connection closed
  void _handleWebSocketDone() {
    debugPrint('WebSocket connection closed');
    _isConnected = false;
    _currentConversationId = null;
    
    // Try to reconnect
    Future.delayed(const Duration(seconds: 5), () {
      if (!_isConnected) {
        connectAudioWebSocket().catchError((e) {
          debugPrint('Reconnect failed: $e');
        });
      }
    });
  }

  /// Close the client
  void dispose() {
    disconnectAudioWebSocket();
    _httpClient.close();
  }
}

/// Custom exception for API errors
class ApiException implements Exception {
  final String message;

  const ApiException(this.message);

  @override
  String toString() => message;
}

/// Extension to convert hex string to bytes
extension on String {
  List<int> hexToBytes() {
    final result = <int>[];
    for (var i = 0; i < length; i += 2) {
      final hexByte = substring(i, i + 2);
      final byte = int.parse(hexByte, radix: 16);
      result.add(byte);
    }
    return result;
  }
}
