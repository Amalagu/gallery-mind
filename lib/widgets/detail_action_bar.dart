import 'package:flutter/material.dart';

// Bottom action bar used only on the image detail page. Most actions are visual
// placeholders for now, while the center button represents image-similarity flow.
class DetailActionBar extends StatelessWidget {
  const DetailActionBar({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 76,
      padding: const EdgeInsets.symmetric(horizontal: 13),
      decoration: BoxDecoration(
        color: const Color(0xF21A1C27),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF2D3145)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.34),
            blurRadius: 24,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _ActionItem(
            icon: Icons.edit_rounded,
            label: 'Edit',
            color: Color(0xFF9AA6B8),
          ),
          _ActionItem(
            icon: Icons.archive_rounded,
            label: 'Add to',
            color: Color(0xFF9AA6B8),
          ),
          _CenterSearchAction(),
          _ActionItem(
            icon: Icons.lock_rounded,
            label: 'Secure',
            color: Color(0xFF9AA6B8),
          ),
          _ActionItem(
            icon: Icons.delete_rounded,
            label: 'Delete',
            color: Color(0xFFFF686D),
          ),
        ],
      ),
    );
  }
}

class _ActionItem extends StatelessWidget {
  const _ActionItem({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 48,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 7),
          Text(
            label,
            maxLines: 1,
            style: TextStyle(
              color: color,
              fontSize: 9,
              fontWeight: FontWeight.w700,
              letterSpacing: 0,
            ),
          ),
        ],
      ),
    );
  }
}

class _CenterSearchAction extends StatelessWidget {
  const _CenterSearchAction();

  @override
  Widget build(BuildContext context) {
    // The larger center button mirrors the design intention: use the current
    // image as a query to find visually similar gallery images.
    return SizedBox(
      width: 58,
      child: Center(
        child: Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            color: const Color(0xFF8790FF),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF8790FF).withOpacity(0.32),
                blurRadius: 18,
              ),
            ],
          ),
          child: const Icon(
            Icons.search_rounded,
            color: Color(0xFF070812),
            size: 25,
          ),
        ),
      ),
    );
  }
}
