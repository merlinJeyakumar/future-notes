import 'package:flutter/material.dart';

class Sidebar extends StatelessWidget {
  const Sidebar({super.key});

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
            child: Icon(Icons.inbox, color: Colors.blueAccent, size: 32),
          ),

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

          // TODAY Section
          _buildSectionHeader('TODAY'),
          _buildNavItem('Meeting Notes', '10:00 AM', isSelected: true),
          _buildNavItem('API Config', '09:15 AM'),

          const SizedBox(height: 24),

          // YESTERDAY Section
          _buildSectionHeader('YESTERDAY'),
          _buildNavItem('Bug Fix #404', '4:50 PM'),
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

  Widget _buildNavItem(
    String title,
    String subtitle, {
    bool isSelected = false,
  }) {
    return Container(
      decoration: isSelected
          ? const BoxDecoration(
              border: Border(
                left: BorderSide(color: Colors.blueAccent, width: 3),
              ),
              color: Color(0xFF1E293B), // Slightly lighter for selection
            )
          : null,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 24.0),
        title: Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(
            color: isSelected ? Colors.blueAccent[100] : Colors.grey,
            fontSize: 12,
          ),
        ),
        onTap: () {},
      ),
    );
  }
}
