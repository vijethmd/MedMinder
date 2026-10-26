import 'package:flutter/material.dart';

import 'theme.dart';

// ========== SHARED WIDGETS ==========

// White rounded card with a soft shadow, optionally tappable
class AppCard extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final Color color;
  final Color? borderColor;
  final EdgeInsetsGeometry padding;

  const AppCard({
    super.key,
    required this.child,
    this.onTap,
    this.color = AppColors.surface,
    this.borderColor,
    this.padding = const EdgeInsets.all(20),
  });

  @override
  Widget build(BuildContext context) {
    final shape = BorderRadius.circular(24);
    return Container(
      decoration: BoxDecoration(
        borderRadius: shape,
        boxShadow: const [
          BoxShadow(color: Color(0x12000000), blurRadius: 16, offset: Offset(0, 4)),
        ],
      ),
      child: Material(
        color: color,
        borderRadius: shape,
        child: InkWell(
          onTap: onTap,
          borderRadius: shape,
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              borderRadius: shape,
              border: Border.all(
                color: borderColor ?? AppColors.border,
                width: borderColor == null ? 1.5 : 2.5,
              ),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

// Round tinted icon
class IconBadge extends StatelessWidget {
  final IconData icon;
  final Color color;
  final double size;
  final bool onDark;

  const IconBadge(this.icon, this.color, {super.key, this.size = 56, this.onDark = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: onDark
            ? Colors.white.withValues(alpha: 0.2)
            : color.withValues(alpha: 0.12),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, color: onDark ? Colors.white : color, size: size * 0.55),
    );
  }
}

// Heading above a group of cards
class SectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;

  const SectionHeader(this.title, {super.key, this.subtitle});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(top: 32, bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: text.titleLarge),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(subtitle!, style: text.bodyMedium?.copyWith(color: AppColors.textMuted)),
          ],
        ],
      ),
    );
  }
}

// Large menu button on the home screen
class BigMenuButton extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;
  final bool filled;

  const BigMenuButton({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
    this.filled = false,
  });

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final foreground = filled ? Colors.white : AppColors.text;
    return AppCard(
      onTap: onTap,
      color: filled ? color : AppColors.surface,
      borderColor: filled ? color : null,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      child: Row(
        children: [
          IconBadge(icon, color, size: 60, onDark: filled),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: text.titleMedium?.copyWith(color: foreground)),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: text.bodyMedium?.copyWith(
                    color: filled ? Colors.white : AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, size: 36, color: foreground),
        ],
      ),
    );
  }
}

// Small rounded label, e.g. "Ongoing"
class StatusPill extends StatelessWidget {
  final String text;
  final Color color;
  final IconData? icon;

  const StatusPill(this.text, this.color, {super.key, this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 20, color: color),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Text(
              text,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}

// ========== DIALOGS ==========
// Big, centred message with a single OK button (stays until dismissed)
Future<void> showInfoDialog(
  BuildContext context, {
  required IconData icon,
  required Color color,
  required String title,
  required String message,
}) {
  return showDialog(
    context: context,
    builder: (context) => AlertDialog(
      icon: IconBadge(icon, color, size: 80),
      title: Text(title, textAlign: TextAlign.center),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ),
        ],
      ),
    ),
  );
}

// Yes / no question with two full-width buttons
Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  bool destructive = false,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title, textAlign: TextAlign.center),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              style: destructive
                  ? FilledButton.styleFrom(backgroundColor: AppColors.danger)
                  : null,
              onPressed: () => Navigator.pop(context, true),
              child: Text(confirmLabel),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('No, go back'),
            ),
          ),
        ],
      ),
    ),
  );
  return confirmed ?? false;
}
