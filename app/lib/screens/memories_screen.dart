import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import '../providers/backend_provider.dart';
import '../backend/models/conversation.dart';

/// Memories Screen
/// Shows extracted memories and allows semantic search
class MemoriesScreen extends StatefulWidget {
  const MemoriesScreen({super.key});

  @override
  State<MemoriesScreen> createState() => _MemoriesScreenState();
}

class _MemoriesScreenState extends State<MemoriesScreen> {
  final TextEditingController _searchController = TextEditingController();
  List<MemorySearchResult> _searchResults = [];
  bool _isSearching = false;

  @override
  void initState() {
    super.initState();
    // Refresh memories when screen loads
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final backendProvider = Provider.of<BackendProvider>(context, listen: false);
      backendProvider.refreshMemories();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final backendProvider = Provider.of<BackendProvider>(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Memories'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: () => backendProvider.refreshMemories(),
          ),
        ],
      ),
      body: Column(
        children: [
          // Search Bar
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                labelText: 'Search memories',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _isSearching
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          setState(() {
                            _searchResults = [];
                          });
                        },
                      ),
                border: const OutlineInputBorder(),
              ),
              onSubmitted: (query) => _performSearch(query),
              onChanged: (query) {
                if (query.isEmpty) {
                  setState(() {
                    _searchResults = [];
                  });
                }
              },
            ),
          ),
          
          // Search Results
          if (_isSearching)
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Center(child: CircularProgressIndicator()),
            ),
          
          if (_searchResults.isNotEmpty)
            Expanded(
              child: ListView.builder(
                itemCount: _searchResults.length,
                itemBuilder: (context, index) {
                  final result = _searchResults[index];
                  return _buildMemoryCard(context, result);
                },
              ),
            ),
          
          // All Memories (when not searching)
          if (_searchResults.isEmpty && !_isSearching)
            Expanded(
              child: Consumer<BackendProvider>(
                builder: (context, provider, child) {
                  if (provider.isLoading && provider.memories.isEmpty) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (provider.memories.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.memory, size: 64, color: Colors.grey),
                          const SizedBox(height: 16),
                          Text(
                            'No memories yet',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Memories will be extracted from your conversations',
                            style: Theme.of(context).textTheme.bodyMedium,
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    );
                  }

                  return ListView.builder(
                    itemCount: provider.memories.length,
                    itemBuilder: (context, index) {
                      final memory = provider.memories[index];
                      return _buildMemoryCard(context, MemorySearchResult(
                        id: memory.id,
                        text: memory.content,
                        score: 1.0, // Full match for direct memories
                        conversationId: memory.conversationId,
                        createdAt: memory.createdAt,
                      ));
                    },
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMemoryCard(BuildContext context, MemorySearchResult memory) {
    final dateFormat = DateFormat('MMM dd, yyyy');
    DateTime? createdAt = memory.createdAt != null 
        ? DateTime.tryParse(memory.createdAt!) 
        : null;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: InkWell(
        onTap: () => _showMemoryDetails(context, memory),
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
                      memory.text ?? 'Untitled Memory',
                      style: Theme.of(context).textTheme.titleMedium,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (memory.score < 1.0)
                    Text(
                      '${(memory.score * 100).toStringAsFixed(0)}%',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                ],
              ),
              const SizedBox(height: 8),
              if (createdAt != null)
                Text(
                  dateFormat.format(createdAt),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              if (memory.conversationId != null)
                Text(
                  'From conversation: ${memory.conversationId!.substring(0, 8)}...',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _performSearch(String query) async {
    if (query.isEmpty) return;
    
    setState(() {
      _isSearching = true;
    });
    
    try {
      final backendProvider = Provider.of<BackendProvider>(context, listen: false);
      final results = await backendProvider.searchMemories(query, limit: 20);
      
      setState(() {
        _searchResults = results;
        _isSearching = false;
      });
    } catch (e) {
      setState(() {
        _isSearching = false;
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error searching memories: $e')),
      );
    }
  }

  void _showMemoryDetails(BuildContext context, MemorySearchResult memory) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => _MemoryDetailsSheet(memory: memory),
    );
  }
}

/// Memory Details Sheet
class _MemoryDetailsSheet extends StatelessWidget {
  final MemorySearchResult memory;

  const _MemoryDetailsSheet({required this.memory});

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('MMM dd, yyyy - HH:mm:ss');
    DateTime? createdAt = memory.createdAt != null 
        ? DateTime.tryParse(memory.createdAt!) 
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
                'Memory Details',
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
          
          // Memory content
          Text(
            memory.text ?? 'No content',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          
          // Metadata
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (memory.score < 1.0)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    'Match confidence: ${(memory.score * 100).toStringAsFixed(0)}%',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              if (createdAt != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    'Created: ${dateFormat.format(createdAt)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              if (memory.conversationId != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    'Conversation: ${memory.conversationId!.substring(0, 8)}...',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              if (memory.id.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    'ID: ${memory.id}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
            ],
          ),
          
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
