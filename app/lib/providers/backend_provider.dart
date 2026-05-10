import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../backend/api/omi_api_client.dart';
import '../backend/models/conversation.dart';
import '../services/models.dart';

/// Backend Provider
/// Manages connection to the Omi Omni backend and provides data
class BackendProvider extends ChangeNotifier {
  final OmiApiClient _apiClient;
  
  // Connection state
  BackendConnectionState _connectionState = BackendConnectionState.disconnected;
  String? _errorMessage;
  
  // Data
  List<Conversation> _conversations = [];
  List<Memory> _memories = [];
  AppStats? _stats;
  bool _isLoading = false;
  
  // WebSocket state
  bool _isAudioConnected = false;
  String? _currentConversationId;

  BackendProvider() : _apiClient = OmiApiClient(
    baseUrl: '', // Will be set from config
    apiKey: '', // Will be set from config
  );

  // ===========================================================================
  // Initialization
  // ===========================================================================

  void initialize({required String baseUrl, required String apiKey}) {
    _apiClient.dispose(); // Dispose old client
    _apiClient = OmiApiClient(
      baseUrl: baseUrl,
      apiKey: apiKey,
    );
    
    // Set up WebSocket callbacks
    _setupWebSocketCallbacks();
    
    // Connect to backend
    connect();
  }

  void _setupWebSocketCallbacks() {
    _apiClient.onAudioProgress = (message) {
      debugPrint('Audio progress: ${message.step}');
      notifyListeners();
    };
    
    _apiClient.onAudioComplete = (message) {
      debugPrint('Audio complete: ${message.conversationId}');
      _currentConversationId = message.conversationId;
      
      // Add the new conversation to the list
      final newConversation = Conversation(
        id: message.conversationId,
        title: message.summary.isNotEmpty 
            ? message.summary.length > 50 
                ? '${message.summary.substring(0, 47)}...' 
                : message.summary
            : 'Untitled',
        summary: message.summary,
        actionItems: message.actionItems,
        keyTopics: message.keyTopics,
        startedAt: message.startedAt,
        finishedAt: message.finishedAt,
        audioPath: message.audioPath,
      );
      
      _conversations.insert(0, newConversation);
      _currentConversationId = null;
      
      notifyListeners();
    };
    
    _apiClient.onAudioError = (message) {
      debugPrint('Audio error: ${message.message}');
      _errorMessage = message.message;
      _currentConversationId = null;
      notifyListeners();
    };
    
    _apiClient.onAudioMessage = (message) {
      debugPrint('Audio message: $message');
      notifyListeners();
    };
  }

  // ===========================================================================
  // Connection Management
  // ===========================================================================

  Future<void> connect() async {
    if (_connectionState == BackendConnectionState.connected) {
      return;
    }
    
    _connectionState = BackendConnectionState.connecting;
    _errorMessage = null;
    notifyListeners();
    
    try {
      // Check health
      final health = await _apiClient.healthCheck();
      
      if (health.isHealthy) {
        _connectionState = BackendConnectionState.connected;
        
        // Connect WebSocket for audio streaming
        await _connectAudioWebSocket();
        
        // Load initial data
        await _loadInitialData();
      } else {
        _connectionState = BackendConnectionState.error;
        _errorMessage = 'Backend is not healthy: ${health.services}';
      }
    } catch (e) {
      _connectionState = BackendConnectionState.error;
      _errorMessage = 'Failed to connect: $e';
    }
    
    notifyListeners();
  }

  Future<void> _connectAudioWebSocket() async {
    try {
      await _apiClient.connectAudioWebSocket();
      _isAudioConnected = true;
      debugPrint('Audio WebSocket connected');
    } catch (e) {
      debugPrint('Failed to connect audio WebSocket: $e');
      _isAudioConnected = false;
    }
  }

  Future<void> disconnect() async {
    _connectionState = BackendConnectionState.disconnected;
    _errorMessage = null;
    
    try {
      await _apiClient.disconnectAudioWebSocket();
      _isAudioConnected = false;
    } catch (e) {
      debugPrint('Error disconnecting: $e');
    }
    
    notifyListeners();
  }

  Future<void> reconnect() async {
    await disconnect();
    await Future.delayed(const Duration(seconds: 2));
    await connect();
  }

  // ===========================================================================
  // Data Loading
  // ===========================================================================

  Future<void> _loadInitialData() async {
    if (_isLoading) return;
    
    _isLoading = true;
    notifyListeners();
    
    try {
      // Load conversations
      _conversations = await _apiClient.listConversations(limit: 20);
      
      // Load memories
      _memories = await _apiClient.listMemories(limit: 50);
      
      // Load stats
      _stats = await _apiClient.getStats();
      
      debugPrint('Loaded ${_conversations.length} conversations, ${_memories.length} memories');
    } catch (e) {
      debugPrint('Error loading initial data: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> refreshConversations() async {
    try {
      _conversations = await _apiClient.listConversations(limit: 20);
      notifyListeners();
    } catch (e) {
      debugPrint('Error refreshing conversations: $e');
    }
  }

  Future<void> refreshMemories() async {
    try {
      _memories = await _apiClient.listMemories(limit: 50);
      notifyListeners();
    } catch (e) {
      debugPrint('Error refreshing memories: $e');
    }
  }

  Future<void> refreshStats() async {
    try {
      _stats = await _apiClient.getStats();
      notifyListeners();
    } catch (e) {
      debugPrint('Error refreshing stats: $e');
    }
  }

  // ===========================================================================
  // Audio Streaming
  // ===========================================================================

  Future<void> startAudioStreaming() async {
    if (!_isAudioConnected) {
      await _connectAudioWebSocket();
    }
    
    try {
      await _apiClient.startAudioConversation();
      debugPrint('Started audio streaming');
    } catch (e) {
      debugPrint('Error starting audio streaming: $e');
      throw e;
    }
  }

  Future<void> stopAudioStreaming() async {
    try {
      await _apiClient.stopAudioConversation();
      debugPrint('Stopped audio streaming');
    } catch (e) {
      debugPrint('Error stopping audio streaming: $e');
    }
  }

  Future<void> sendAudioData(List<int> audioData) async {
    if (!_isAudioConnected) {
      throw Exception('Audio WebSocket is not connected');
    }
    
    try {
      await _apiClient.sendAudioData(Uint8List.fromList(audioData));
    } catch (e) {
      debugPrint('Error sending audio data: $e');
      throw e;
    }
  }

  // ===========================================================================
  // Chat
  // ===========================================================================

  Future<ChatResponse> sendChatMessage(String message, {int contextLimit = 5}) async {
    try {
      return await _apiClient.chat(message, contextLimit: contextLimit);
    } catch (e) {
      debugPrint('Error sending chat message: $e');
      rethrow;
    }
  }

  // ===========================================================================
  // Search
  // ===========================================================================

  Future<List<MemorySearchResult>> searchMemories(String query, {int limit = 10}) async {
    try {
      return await _apiClient.searchMemories(query, limit: limit);
    } catch (e) {
      debugPrint('Error searching memories: $e');
      rethrow;
    }
  }

  // ===========================================================================
  // Getters
  // ===========================================================================

  BackendConnectionState get connectionState => _connectionState;
  bool get isConnected => _connectionState == BackendConnectionState.connected;
  bool get isConnecting => _connectionState == BackendConnectionState.connecting;
  bool get hasError => _connectionState == BackendConnectionState.error;
  String? get errorMessage => _errorMessage;
  
  bool get isAudioConnected => _isAudioConnected;
  String? get currentConversationId => _currentConversationId;
  
  List<Conversation> get conversations => _conversations;
  List<Memory> get memories => _memories;
  AppStats? get stats => _stats;
  bool get isLoading => _isLoading;

  OmiApiClient get apiClient => _apiClient;

  // ===========================================================================
  // Cleanup
  // ===========================================================================

  @override
  void dispose() {
    _apiClient.dispose();
    super.dispose();
  }
}
