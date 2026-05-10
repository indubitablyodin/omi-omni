import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import '../providers/backend_provider.dart';
import '../backend/models/conversation.dart';

/// Conversations Screen
/// Shows list of conversations and their details
class ConversationsScreen extends StatefulWidget {
  const ConversationsScreen({super.key});

  @override
  State<ConversationsScreen> createState() => _ConversationsScreenState();
}

class _ConversationsScreenState extends State<ConversationsScreen> {
  @override
  void initState() {
    super.initState();
    // Refresh conversations when screen loads
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final backendProvider = Provider.of<BackendProvider>(context, listen: false);
      backendProvider.refreshConversations();
    });
  }

  @override
  Widget build(BuildContext context) {
    final backendProvider = Provider.of<BackendProvider>(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Conversations'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: () => backendProvider.refreshConversations(),
          ),
        ],
      ),
      body: Consumer<BackendProvider>(
        builder: (context, provider, child) {
          if (provider.isLoading && provider.conversations.isEmpty) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          }

          if (provider.conversations.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.chat_bubble_outline, size: 64, color: Colors.grey),
                  const SizedBox(height: 16),
                  Text(
                    'No conversations yet',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Start a conversation by recording audio with your Omi device',
                    style: Theme.of(context).textTheme.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            itemCount: provider.conversations.length,
            itemBuilder: (context, index) {
              final conversation = provider.conversations[index];
              return _buildConversationCard(context, conversation);
            },
          );
        },
      ),
    );
  }

  Widget _buildConversationCard(BuildContext context, Conversation conversation) {
    final dateFormat = DateFormat('MMM dd, yyyy - HH:mm');
    
    DateTime? startedAt;
    if (conversation.startedAt != null) {
      startedAt = DateTime.tryParse(conversation.startedAt!);
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: InkWell(
        onTap: () => _showConversationDetails(context, conversation),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      conversation.title ?? 'Untitled Conversation',
                      style: Theme.of(context).textTheme.titleMedium,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert),
                    onSelected: (value) => _handleConversationAction(context, value, conversation),
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'share',
                        child: ListTile(
                          leading: Icon(Icons.share),
                          title: Text('Share'),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'delete',
                        child: ListTile(
                          leading: Icon(Icons.delete, color: Colors.red),
                          title: Text('Delete', style: TextStyle(color: Colors.red)),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (conversation.summary != null && conversation.summary!.isNotEmpty)
                Text(
                  conversation.summary!,
                  style: Theme.of(context).textTheme.bodyMedium,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              const SizedBox(height: 8),
              Row(
                children: [
                  if (startedAt != null)
                    Text(
                      dateFormat.format(startedAt),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  if (startedAt != null && conversation.finishedAt != null)
                    Text(
                      ' - ${DateFormat('HH:mm').format(DateTime.tryParse(conversation.finishedAt!) ?? startedAt)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                ],
              ),
              const SizedBox(height: 8),
              // Action items and key topics
              if (conversation.actionItems.isNotEmpty || conversation.keyTopics.isNotEmpty)
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    ...conversation.actionItems.map((item) => Chip(
                      label: Text(item),
                      backgroundColor: Colors.blue.withOpacity(0.2),
                      labelStyle: TextStyle(color: Colors.blue.shade800),
                    )),
                    ...conversation.keyTopics.map((topic) => Chip(
                      label: Text(topic),
                      backgroundColor: Colors.green.withOpacity(0.2),
                      labelStyle: TextStyle(color: Colors.green.shade800),
                    )),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _showConversationDetails(BuildContext context, Conversation conversation) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => _ConversationDetailsSheet(conversation: conversation),
    );
  }

  void _handleConversationAction(BuildContext context, String action, Conversation conversation) {
    switch (action) {
      case 'share':
        // TODO: Implement share functionality
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Share functionality coming soon')),
        );
        break;
      case 'delete':
        _showDeleteConfirmation(context, conversation);
        break;
    }
  }

  void _showDeleteConfirmation(BuildContext context, Conversation conversation) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Conversation'),
        content: Text('Are you sure you want to delete this conversation? This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              final backendProvider = Provider.of<BackendProvider>(context, listen: false);
              backendProvider.deleteConversation(conversation.id)
                .then((_) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Conversation deleted')),
                  );
                })
                .catchError((e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error deleting conversation: $e')),
                  );
                });
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}

/// Conversation Details Sheet
class _ConversationDetailsSheet extends StatelessWidget {
  final Conversation conversation;

  const _ConversationDetailsSheet({required this.conversation});

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('MMM dd, yyyy - HH:mm:ss');
    
    DateTime? startedAt = conversation.startedAt != null 
        ? DateTime.tryParse(conversation.startedAt!) 
        : null;
    DateTime? finishedAt = conversation.finishedAt != null 
        ? DateTime.tryParse(conversation.finishedAt!) 
        : null;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 16,
        right: 16,
        top: 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                conversation.title ?? 'Untitled Conversation',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          const Divider(),
          const SizedBox(height: 8),
          
          // Summary
          if (conversation.summary != null && conversation.summary!.isNotEmpty)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Summary:',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  conversation.summary!,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 16),
              ],
            ),
          
          // Transcript
          if (conversation.transcript != null && conversation.transcript!.isNotEmpty)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Transcript:',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    conversation.transcript!,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          
          // Action Items
          if (conversation.actionItems.isNotEmpty)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Action Items:',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                ...conversation.actionItems.map((item) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle, size: 16, color: Colors.blue),
                      const SizedBox(width: 8),
                      Expanded(child: Text(item)),
                    ],
                  ),
                )),
                const SizedBox(height: 16),
              ],
            ),
          
          // Key Topics
          if (conversation.keyTopics.isNotEmpty)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Key Topics:',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: conversation.keyTopics.map((topic) => Chip(
                    label: Text(topic),
                    backgroundColor: Colors.green.withOpacity(0.2),
                    labelStyle: TextStyle(color: Colors.green.shade800),
                  )).toList(),
                ),
                const SizedBox(height: 16),
              ],
            ),
          
          // Metadata
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Details:',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              if (startedAt != null)
                Text(
                  'Started: ${dateFormat.format(startedAt)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              if (finishedAt != null)
                Text(
                  'Finished: ${dateFormat.format(finishedAt)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              if (conversation.audioPath != null)
                Text(
                  'Audio: ${conversation.audioPath!.split('/').last}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
            ],
          ),
          
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
