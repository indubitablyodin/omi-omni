import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/backend_provider.dart';
import '../backend/models/conversation.dart';

/// Chat Screen
/// Allows chatting with your conversation history using AI
class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final List<_ChatMessage> _messages = [];
  bool _isSending = false;
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final backendProvider = Provider.of<BackendProvider>(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('AI Chat'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete),
            tooltip: 'Clear chat',
            onPressed: () {
              setState(() {
                _messages.clear();
              });
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Chat messages
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final message = _messages[index];
                return _buildChatMessage(context, message);
              },
              padding: const EdgeInsets.all(16.0),
            ),
          ),
          
          // Input area
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    decoration: InputDecoration(
                      labelText: 'Type your message',
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.send),
                        onPressed: _isSending 
                            ? null 
                            : () => _sendMessage(),
                      ),
                    ),
                    onSubmitted: _isSending ? null : (_) => _sendMessage(),
                    enabled: !_isSending && backendProvider.isConnected,
                  ),
                ),
              ],
            ),
          ),
          
          // Connection status
          if (!_isSending && !backendProvider.isConnected)
            Padding(
              padding: const EdgeInsets.only(bottom: 16.0, left: 16, right: 16),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Row(
                    children: [
                      const Icon(Icons.cloud_off, color: Colors.orange),
                      const SizedBox(width: 8),
                      Text(
                        'Connect to backend to use chat',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const Spacer(),
                      ElevatedButton(
                        onPressed: () => backendProvider.connect(),
                        child: const Text('Connect'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildChatMessage(BuildContext context, _ChatMessage message) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Avatar/Icon
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: message.isUser 
                  ? Theme.of(context).colorScheme.primaryContainer 
                  : Theme.of(context).colorScheme.secondaryContainer,
            ),
            child: Icon(
              message.isUser ? Icons.person : Icons.smart_toy,
              size: 18,
              color: message.isUser 
                  ? Theme.of(context).colorScheme.onPrimaryContainer 
                  : Theme.of(context).colorScheme.onSecondaryContainer,
            ),
          ),
          const SizedBox(width: 8),
          
          // Message content
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Sender name
                Text(
                  message.isUser ? 'You' : 'AI Assistant',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                
                // Message text
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: message.isUser 
                        ? Theme.of(context).colorScheme.primaryContainer 
                        : Theme.of(context).colorScheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    message.text,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
                
                // Timestamp
                if (message.timestamp != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4, left: 4),
                    child: Text(
                      '${message.timestamp!.hour}:${message.timestamp!.minute.toString().padLeft(2, '0')}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _sendMessage() async {
    final message = _messageController.text.trim();
    if (message.isEmpty) return;
    
    final backendProvider = Provider.of<BackendProvider>(context, listen: false);
    if (!backendProvider.isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please connect to backend first')),
      );
      return;
    }
    
    // Add user message to chat
    setState(() {
      _messages.add(_ChatMessage(
        text: message,
        isUser: true,
        timestamp: DateTime.now(),
      ));
      _isSending = true;
      _messageController.clear();
    });
    
    // Scroll to bottom
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    });
    
    try {
      // Send message to backend
      final response = await backendProvider.sendChatMessage(message);
      
      // Add AI response to chat
      setState(() {
        _messages.add(_ChatMessage(
          text: response.response,
          isUser: false,
          timestamp: DateTime.now(),
        ));
        _isSending = false;
      });
      
      // Scroll to bottom
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      });
    } catch (e) {
      setState(() {
        _isSending = false;
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }
}

/// Chat message model for display
class _ChatMessage {
  final String text;
  final bool isUser;
  final DateTime? timestamp;

  _ChatMessage({
    required this.text,
    required this.isUser,
    this.timestamp,
  });
}
