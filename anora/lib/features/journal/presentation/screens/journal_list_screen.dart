import 'package:flutter/material.dart';
import '../../../../models/journal_entry.dart';
import '../../../../core/services/storage_service.dart';
import 'journal_editor_screen.dart';

class JournalListScreen extends StatefulWidget {
  const JournalListScreen({Key? key}) : super(key: key);

  @override
  State<JournalListScreen> createState() => _JournalListScreenState();
}

class _JournalListScreenState extends State<JournalListScreen> {
  late StorageService _storageService;
  List<JournalEntry> _entries = [];

  @override
  void initState() {
    super.initState();
    _storageService = StorageService();
    _storageService.initBox().then((_) {
      _loadEntries();
    });
  }

  Future<void> _loadEntries() async {
    final entries = await _storageService.getAllEntries();
    setState(() {
      _entries = entries.toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Anora'),
        // subtitle: const Text('Your Private Journal'), // AppBar doesn't have a subtitle property directly
      ),
      body: _entries.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.book_outlined, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text('No entries yet', style: Theme.of(context).textTheme.headlineSmall),
                  SizedBox(height: 8),
                  Text('Start journaling to see your entries here'),
                ],
              ),
            )
          : ListView.builder(
              itemCount: _entries.length,
              itemBuilder: (context, index) {
                final entry = _entries[index];
                return ListTile(
                  title: Text(entry.title.isEmpty ? 'Untitled' : entry.title),
                  subtitle: Text(
                    '${entry.mood} • ${entry.wordCount} words • ${entry.createdAt.toString().split(' ')[0]}',
                  ),
                  trailing: Chip(label: Text(entry.mood)),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => JournalEditorScreen(entry: entry),
                      ),
                    ).then((_) => _loadEntries());
                  },
                  onLongPress: () {
                    showDialog(
                      context: context,
                      builder: (c) => AlertDialog(
                        title: Text('Delete entry?'),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(c), child: Text('Cancel')),
                          TextButton(
                            onPressed: () {
                              _storageService.deleteEntry(entry.id);
                              _loadEntries();
                              Navigator.pop(c);
                            },
                            child: Text('Delete'),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const JournalEditorScreen()),
          ).then((_) => _loadEntries());
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}