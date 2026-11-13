import 'package:flutter/material.dart';

import '../theme/theme.dart';

/// Grey segmented tab bar (Upcoming / Completed / Cancelled, etc.).
class Segmented extends StatelessWidget {
  final List<String> labels;
  final int index;
  final ValueChanged<int> onChanged;
  final List<int>? counts;
  final List<int>? badges;
  final Color bg;
  final double height;
  const Segmented({
    super.key,
    required this.labels,
    required this.index,
    required this.onChanged,
    this.counts,
    this.badges,
    this.bg = C.segment,
    this.height = 42,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(4),
    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(16)),
    child: Row(
      children: [
        for (var i = 0; i < labels.length; i++) ...[
          if (i > 0) const SizedBox(width: 4),
          Expanded(
            child: Semantics(
              selected: i == index,
              button: true,
              child: GestureDetector(
                onTap: () => onChanged(i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  height: height,
                  decoration: BoxDecoration(
                    color: i == index ? Colors.white : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: i == index
                        ? const [BoxShadow(color: Color(0x1F0C2419), blurRadius: 3, offset: Offset(0, 1))]
                        : null,
                  ),
                  alignment: Alignment.center,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Flexible(
                        child: Text(
                          labels[i],
                          overflow: TextOverflow.ellipsis,
                          style: t(13, w: FontWeight.w600, c: i == index ? C.ink : C.muted),
                        ),
                      ),
                      if (counts != null) ...[
                        const SizedBox(width: 6),
                        Container(
                          constraints: const BoxConstraints(minWidth: 20),
                          height: 20,
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: i == index ? C.brand : const Color(0xFFD9E2D5),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text('${counts![i]}', style: t(11, c: i == index ? Colors.white : C.mutedInk)),
                        ),
                      ],
                      if (badges != null && badges![i] > 0) ...[
                        const SizedBox(width: 6),
                        Container(
                          constraints: const BoxConstraints(minWidth: 18),
                          height: 18,
                          padding: const EdgeInsets.symmetric(horizontal: 5),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(color: C.coral, borderRadius: BorderRadius.circular(999)),
                          child: Text('${badges![i]}', style: t(11, c: Colors.white)),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    ),
  );
}
