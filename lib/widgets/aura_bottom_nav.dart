import 'package:flutter/material.dart';

// Main floating bottom navigation used by the Home/Albums/Settings shell.
// The center tab is intentionally emphasized because Home is the core action.
class AuraBottomNav extends StatelessWidget {
  const AuraBottomNav({
    super.key,
    required this.selectedIndex,
    required this.onSelected,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    // The middle item has no label and uses a larger circular button, matching
    // the supplied design mockups.
    const items = [
      _NavItem(icon: Icons.photo_album_rounded, label: 'Albums'),
      _NavItem(icon: Icons.inventory_2_rounded, label: 'Home'),
      _NavItem(icon: Icons.settings_rounded, label: 'Settings'),
    ];

    return Container(
      height: 82,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: const Color(0xF21A1C27),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: const Color(0xFF2D3145)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.35),
            blurRadius: 30,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: List.generate(items.length, (index) {
          final selected = selectedIndex == index;
          //final isCenter = index == 1;

          return GestureDetector(
            onTap: () => onSelected(index),
            child: SizedBox(
              width: selected ? 74 : 78,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    curve: Curves.easeOutCubic,
                    width: selected ? 54 : 28,
                    height: selected ? 54 : 28,
                    decoration: BoxDecoration(
                      color: /* selected 
                          ? const Color(0xFF8790FF)
                          : */
                          selected
                              ? const Color(
                                  0xFF8790FF) //const Color(0xFF2C335F)
                              : Colors.transparent,
                      shape: BoxShape.circle,
                      boxShadow: /* isCenter */ selected
                          ? [
                              BoxShadow(
                                color:
                                    const Color(0xFF8790FF).withOpacity(0.32),
                                blurRadius: 18,
                              ),
                            ]
                          : null,
                    ),
                    child: Icon(
                      items[index].icon,
                      size: /* isCenter ? 24 : */ 20,
                      color: /* isCenter */ selected
                          ? const Color(0xFF070812)
                          : const Color(0xFFA4ACBF),
                    ),
                  ),
                  /* if (!selected) */ ...[
                    const SizedBox(height: 3),
                    Text(
                      items[index].label,
                      maxLines: 1,
                      style: TextStyle(
                        fontSize: 10,
                        color: selected
                            ? const Color(0xFFE1E4FF)
                            : const Color(0xFFB7BDCC),
                        fontWeight:
                            selected ? FontWeight.w700 : FontWeight.w500,
                        letterSpacing: 0,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        }),
      ),
    );
  }
}

class _NavItem {
  const _NavItem({required this.icon, required this.label});

  final IconData icon;
  final String label;
}
