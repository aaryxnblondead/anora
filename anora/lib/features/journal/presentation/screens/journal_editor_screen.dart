import 'package:flutter/material.dart';
import '../../../../models/journal_entry.dart';
import '../../../../core/services/storage_service.dart';

class JournalEditorScreen extends StatefulWidget {
  final JournalEntry? entry;
  const JournalEditorScreen({Key? key, this.entry}) : super(key: key);

  @override
  State<JournalEditorScreen> createState() => _JournalEditorScreenState();
}

class _JournalEditorScreenState extends State<JournalEditorScreen> {
  late TextEditingController _titleController;
  late TextEditingController _bodyController;
  String _selectedMood = 'Neutral';
  final _storageService = StorageService();

  final moods = ['Happy', 'Sad', 'Anxious', 'Neutral', 'Angry', 'Joyful', 'Peaceful'];

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.entry?.title ?? '');
    _bodyController = TextEditingController(text: widget.entry?.body ?? '');
    _selectedMood = widget.entry?.mood ?? 'Neutral';
  }

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  Future<void> _saveEntry() async {
    if (_bodyController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Entry cannot be empty')));
      return;
    }

    final entry = JournalEntry(
      id: widget.entry?.id,
      title: _titleController.text.isEmpty ? 'Untitled' : _titleController.text,
      body: _bodyController.text,
      mood: _selectedMood,
      createdAt: widget.entry?.createdAt,
    );

    await _storageService.saveEntry(entry);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.entry == null ? 'New Entry' : 'Edit Entry'),
        actions: [
          IconButton(
            onPressed: _saveEntry,
            icon: const Icon(Icons.check),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _titleController,
              decoration: InputDecoration(
                hintText: 'Title (optional)',
                border: OutlineInputBorder(),
              ),
            ),
            SizedBox(height: 16),
            TextField(
              controller: _bodyController,
              maxLines: 12,
              decoration: InputDecoration(
                hintText: 'Write your thoughts...',
                border: OutlineInputBorder(),
              ),
            ),
            SizedBox(height: 16),
            Text('How are you feeling?', style: Theme.of(context).textTheme.titleMedium),
            SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: moods
                  .map(
                    (mood) => FilterChip(
                      label: Text(mood),
                      selected: _selectedMood == mood,
                      onSelected: (selected) {
                        setState(() => _selectedMood = selected ? mood : 'Neutral');
                      },
                    ),
                  )
                  .toList(),
            ),
            SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _saveEntry,
                child: Text('Save Entry'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}