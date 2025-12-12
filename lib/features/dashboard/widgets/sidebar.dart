import 'package:flutter/material.dart';

class Sidebar extends StatelessWidget {
  final List<String> recentFiles;
  final Function(String) onFileSelected;
  final VoidCallback onNewNote;

  const Sidebar({
    super.key,
    this.recentFiles = const [],
    required this.onFileSelected,
    required this.onNewNote,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 280,
      color: const Color(0xFF161E2D), // Dark sidebar background
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Logo Area
          Padding(
            padding: const EdgeInsets.all(20.0),
            child: Row(
              children: [
                Icon(Icons.inbox, color: Colors.blueAccent, size: 32),
                const SizedBox(width: 12),
                const Text(
                  'Notes',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),

          // New Note Button
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: onNewNote,
                icon: const Icon(Icons.add),
                label: const Text('New Note'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blueAccent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ),

          const SizedBox(height: 24),

          // Search Bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: TextField(
              decoration: InputDecoration(
                filled: true,
                fillColor: const Color(0xFF1E293B),
                hintText: 'Search...',
                hintStyle: const TextStyle(color: Colors.grey),
                prefixIcon: const Icon(Icons.search, color: Colors.grey),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFF334155)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFF334155)),
                ),
              ),
              style: const TextStyle(color: Colors.white),
            ),
          ),

          const SizedBox(height: 24),

          _buildSectionHeader('RECENT'),
          Expanded(
            child: ListView.builder(
              itemCount: recentFiles.length,
              itemBuilder: (context, index) {
                final file = recentFiles[index];
                return ListTile(
                  leading: const Icon(
                    Icons.description,
                    color: Colors.white70,
                    size: 20,
                  ),
                  title: Text(
                    file,
                    style: const TextStyle(color: Colors.white70),
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () => onFileSelected(file),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                  dense: true,
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 8.0),
      child: Text(
        title,
        style: const TextStyle(
          color: Colors.grey,
          fontSize: 12,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}
