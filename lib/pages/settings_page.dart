import 'package:flutter/material.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({
    super.key,
    required this.similarityThreshold,
    required this.showFilenameMatches,
    required this.onSimilarityThresholdChanged,
    required this.onShowFilenameMatchesChanged,
  });

  final int similarityThreshold;
  final bool showFilenameMatches;
  final ValueChanged<int> onSimilarityThresholdChanged;
  final ValueChanged<bool> onShowFilenameMatchesChanged;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      key: const ValueKey('settings'),
      color: const Color(0xFF060710),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(22, 26, 22, 118),
        physics: const BouncingScrollPhysics(),
        children: [
          const Text(
            'Settings',
            style: TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.w900,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Tune how GalleryMind searches and suggests images.',
            style: TextStyle(
              color: Color(0xFF9BA1B8),
              fontSize: 13,
              fontWeight: FontWeight.w600,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 22),
          _SettingsCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const _SettingIcon(icon: Icons.auto_awesome_rounded),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Similar Image Threshold',
                            style: TextStyle(
                              color: Color(0xFFFFFFFF),
                              fontSize: 15,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Controls how closely similar suggestions must match.',
                            style: TextStyle(
                              color: Color(0xFF9BA1B8),
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      '$similarityThreshold%',
                      style: const TextStyle(
                        color: Color(0xFFBFC4FF),
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    activeTrackColor: const Color(0xFF8790FF),
                    inactiveTrackColor: const Color(0xFF252A3B),
                    thumbColor: const Color(0xFF8790FF),
                    overlayColor: const Color(0x338790FF),
                    trackHeight: 5,
                    valueIndicatorColor: const Color(0xFF202550),
                    valueIndicatorTextStyle: const TextStyle(
                      color: Color(0xFFE6E8FF),
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  child: Slider(
                    value: similarityThreshold.toDouble(),
                    min: 70,
                    max: 100,
                    divisions: 6,
                    label: '$similarityThreshold%',
                    onChanged: (value) =>
                        onSimilarityThresholdChanged(value.round()),
                  ),
                ),
                const Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '70%',
                      style: TextStyle(
                        color: Color(0xFF767D95),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0,
                      ),
                    ),
                    Text(
                      '100%',
                      style: TextStyle(
                        color: Color(0xFF767D95),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _SettingsCard(
            child: Row(
              children: [
                const _SettingIcon(icon: Icons.badge_rounded),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Show Filename Matches',
                        style: TextStyle(
                          color: Color(0xFFFFFFFF),
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Also show exact filename results below semantic matches.',
                        style: TextStyle(
                          color: Color(0xFF9BA1B8),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0,
                        ),
                      ),
                    ],
                  ),
                ),
                Switch.adaptive(
                  value: showFilenameMatches,
                  activeColor: const Color(0xFF8790FF),
                  onChanged: onShowFilenameMatchesChanged,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF10131D),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF282D3D)),
      ),
      child: child,
    );
  }
}

class _SettingIcon extends StatelessWidget {
  const _SettingIcon({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: const Color(0xFF1D2356),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, color: const Color(0xFF8790FF), size: 20),
    );
  }
}
