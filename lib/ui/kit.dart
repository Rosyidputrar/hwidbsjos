import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:simple_icons/simple_icons.dart';

import 'theme.dart';

/// Shared building blocks for the Rynex look: neutral surfaces with
/// hairline borders, one accent colour, and the spacing and radius tokens
/// from theme.dart.

/// The app mark: the Android-headed π symbol, with no tile behind it.
class LogoMark extends StatelessWidget {
  const LogoMark({super.key, this.size = 40, this.glow = true});
  final double size;
  final bool glow;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: Image.asset('assets/brand/logo.png', filterQuality: FilterQuality.medium),
  );
}

/// Primary call to action: solid accent, full width.
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.busy = false,
    this.compact = false,
  });
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool busy;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final enabled = onPressed != null && !busy;
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 150),
      opacity: enabled ? 1 : 0.45,
      child: Material(
        color: p.accent,
        borderRadius: BorderRadius.circular(Radii.md),
        child: InkWell(
          borderRadius: BorderRadius.circular(Radii.md),
          onTap: enabled ? onPressed : null,
          child: SizedBox(
            height: compact ? 44 : 52,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.lg),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (busy)
                    SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2, color: p.onAccent))
                  else if (icon != null)
                    Icon(icon, size: 18, color: p.onAccent),
                  if (busy || icon != null) const SizedBox(width: Space.sm),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: p.onAccent, fontWeight: FontWeight.w600, fontSize: compact ? 14 : 15),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A bordered card on the surface colour; tappable when [onTap] is set.
class SurfaceCard extends StatelessWidget {
  const SurfaceCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(Space.lg),
    this.onTap,
    this.onLongPress,
    this.highlight = false,
    this.color,
    this.radius = Radii.lg,
  });
  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool highlight;
  final Color? color;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Material(
      color: color ?? p.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radius),
        side: BorderSide(color: highlight ? p.accent : p.border, width: highlight ? 1.5 : 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

/// A rounded square holding an icon, tinted by [color] (or the accent).
class IconTile extends StatelessWidget {
  const IconTile({super.key, required this.icon, this.color, this.size = 36, this.solid = false});
  final IconData icon;
  final Color? color;
  final double size;

  /// Solid tiles use a white glyph on the colour (brand marks); soft ones tint.
  final bool solid;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final c = color ?? p.accent;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: solid ? c : c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(size * 0.3),
      ),
      alignment: Alignment.center,
      child: Icon(icon, size: size * 0.5, color: solid ? Colors.white : c),
    );
  }
}

/// A neutral tile for list rows: the icon carries the colour, the tile does not.
class GlyphTile extends StatelessWidget {
  const GlyphTile({super.key, required this.icon, this.color, this.size = 34});
  final IconData icon;
  final Color? color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: p.raised, borderRadius: BorderRadius.circular(Radii.sm)),
      alignment: Alignment.center,
      child: Icon(icon, size: size * 0.5, color: color ?? p.text),
    );
  }
}

/// Small uppercase label above a group.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.label, {super.key, this.trailing, this.padding = const EdgeInsets.fromLTRB(4, 24, 4, 8)});
  final String label;
  final Widget? trailing;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => Padding(
    padding: padding,
    child: Row(
      children: [
        Expanded(child: Text(label.toUpperCase(), style: Theme.of(context).textTheme.labelSmall)),
        ?trailing,
      ],
    ),
  );
}

/// A section title with an optional text action on the right ("See all").
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.action, this.onAction, this.padding});
  final String title;
  final String? action;
  final VoidCallback? onAction;
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) => Padding(
    padding: padding ?? const EdgeInsets.fromLTRB(2, Space.xxl, 0, Space.sm),
    child: Row(
      children: [
        Expanded(child: Text(title, style: Theme.of(context).textTheme.titleMedium)),
        if (action != null)
          TextButton(
            onPressed: onAction,
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: Space.sm),
              textStyle: const TextStyle(fontFamily: 'Geist', fontSize: 13, fontWeight: FontWeight.w600),
            ),
            child: Text(action!),
          ),
      ],
    ),
  );
}

/// The large title at the top of a tab, with an optional caption and actions.
class PageHeader extends StatelessWidget {
  const PageHeader(this.title, {super.key, this.subtitle, this.actions = const []});
  final String title;
  final String? subtitle;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(top: Space.sm, bottom: Space.lg),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: text.displaySmall),
                if (subtitle != null) ...[const SizedBox(height: Space.xs), Text(subtitle!, style: text.bodySmall)],
              ],
            ),
          ),
          for (var i = 0; i < actions.length; i++) ...[if (i > 0) const SizedBox(width: Space.sm), actions[i]],
        ],
      ),
    );
  }
}

/// Inset grouped rows, separated by hairlines.
class SettingsGroup extends StatelessWidget {
  const SettingsGroup({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(Radii.lg),
        border: Border.all(color: p.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) Divider(height: 1, indent: 62, endIndent: 0, color: p.border),
              children[i],
            ],
          ],
        ),
      ),
    );
  }
}

class SettingsRow extends StatelessWidget {
  const SettingsRow({
    super.key,
    required this.title,
    this.icon,
    this.leading,
    this.color,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.onLongPress,
    this.destructive = false,
  });
  final String title;
  final IconData? icon;
  final Widget? leading;

  /// Tints the icon glyph; the tile behind it stays neutral.
  final Color? color;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final text = Theme.of(context).textTheme;
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
        child: Row(
          children: [
            leading ??
                (icon != null
                    ? GlyphTile(icon: icon!, color: destructive ? p.danger : color)
                    : const SizedBox.shrink()),
            if (leading != null || icon != null) const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: text.titleSmall?.copyWith(color: destructive ? p.danger : null)),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(subtitle!, maxLines: 2, overflow: TextOverflow.ellipsis, style: text.bodySmall),
                  ],
                ],
              ),
            ),
            if (trailing != null)
              trailing!
            else if (onTap != null)
              Icon(LucideIcons.chevronRight, size: 18, color: p.faint),
          ],
        ),
      ),
    );
  }
}

/// A compact status pill.
class Pill extends StatelessWidget {
  const Pill(this.label, {super.key, this.color, this.icon, this.dot = false});
  final String label;
  final Color? color;
  final IconData? icon;
  final bool dot;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final c = color ?? p.muted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(Radii.pill)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dot) ...[
            StatusDot(color: c, size: 6),
            const SizedBox(width: 6),
          ] else if (icon != null) ...[
            Icon(icon, size: 12, color: c),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: c),
          ),
        ],
      ),
    );
  }
}

/// A small dot; with [pulse] it breathes, for "working" states.
class StatusDot extends StatefulWidget {
  const StatusDot({super.key, required this.color, this.size = 8, this.pulse = false});
  final Color color;
  final double size;
  final bool pulse;

  @override
  State<StatusDot> createState() => _StatusDotState();
}

class _StatusDotState extends State<StatusDot> with SingleTickerProviderStateMixin {
  late final controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200));

  @override
  void initState() {
    super.initState();
    if (widget.pulse) controller.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(StatusDot old) {
    super.didUpdateWidget(old);
    if (widget.pulse && !controller.isAnimating) controller.repeat(reverse: true);
    if (!widget.pulse && controller.isAnimating) controller.stop();
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dot = Container(
      width: widget.size,
      height: widget.size,
      decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
    );
    if (!widget.pulse) return dot;
    return FadeTransition(opacity: Tween(begin: 0.35, end: 1.0).animate(controller), child: dot);
  }
}

/// A square icon button with a hairline border; [filled] makes it the accent.
class AppIconButton extends StatelessWidget {
  const AppIconButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.onLongPress,
    this.size = 40,
    this.filled = false,
    this.badge = 0,
    this.color,
  });
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double size;
  final bool filled;
  final int badge;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final enabled = onTap != null;
    final button = Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: filled ? (enabled ? p.accent : p.raised) : p.surface,
          borderRadius: BorderRadius.circular(size * 0.32),
          border: filled ? null : Border.all(color: p.border),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(size * 0.32),
            onTap: enabled
                ? () {
                    HapticFeedback.selectionClick();
                    onTap!();
                  }
                : null,
            onLongPress: onLongPress,
            child: Icon(
              icon,
              size: size * 0.45,
              color: filled ? (enabled ? p.onAccent : p.faint) : (color ?? (enabled ? p.text : p.faint)),
            ),
          ),
        ),
      ),
    );
    return Badge(isLabelVisible: badge > 0, label: Text('$badge'), child: button);
  }
}

/// A rounded chip: filters, toggles and compact pickers.
class AppChip extends StatelessWidget {
  const AppChip({
    super.key,
    required this.label,
    required this.onTap,
    this.selected = false,
    this.icon,
    this.leading,
    this.trailingIcon,
    this.color,
    this.maxWidth,
  });
  final String label;
  final VoidCallback? onTap;
  final bool selected;
  final IconData? icon;
  final Widget? leading;
  final IconData? trailingIcon;

  /// Overrides the accent for a selected chip (warnings, for example).
  final Color? color;
  final double? maxWidth;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final c = color ?? p.accent;
    final fg = selected ? c : p.text;
    Widget label0 = Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: fg),
    );
    if (maxWidth != null) {
      label0 = ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth!),
        child: label0,
      );
    }
    return Material(
      color: selected ? c.withValues(alpha: 0.13) : p.surface,
      shape: StadiumBorder(side: BorderSide(color: selected ? c.withValues(alpha: 0.4) : p.border)),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Container(
          height: 34,
          padding: EdgeInsets.fromLTRB(leading != null ? 6 : 12, 0, 12, 0),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (leading != null) ...[leading!, const SizedBox(width: 6)],
              if (icon != null) ...[Icon(icon, size: 15, color: selected ? c : p.muted), const SizedBox(width: 6)],
              Flexible(child: label0),
              if (trailingIcon != null) ...[const SizedBox(width: 4), Icon(trailingIcon, size: 13, color: p.faint)],
            ],
          ),
        ),
      ),
    );
  }
}

/// A full-width segmented control with an optional caption above it.
class Segmented<T> extends StatelessWidget {
  const Segmented({super.key, required this.value, required this.options, required this.onChanged, this.label});
  final T value;
  final Map<T, String> options;
  final ValueChanged<T> onChanged;
  final String? label;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 0, Space.sm),
            child: Text(label!, style: Theme.of(context).textTheme.labelMedium),
          ),
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<T>(
            showSelectedIcon: false,
            segments: [
              for (final e in options.entries)
                ButtonSegment(
                  value: e.key,
                  label: Text(e.value, maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
            ],
            selected: {options.containsKey(value) ? value : options.keys.first},
            onSelectionChanged: (s) => onChanged(s.first),
          ),
        ),
      ],
    );
  }
}

/// A tinted strip for state the user should notice: approvals, plan mode,
/// running servers, warnings.
class InlineBanner extends StatelessWidget {
  const InlineBanner({
    super.key,
    required this.tone,
    required this.child,
    this.icon,
    this.trailing,
    this.onTap,
    this.padding = const EdgeInsets.fromLTRB(Space.md, Space.sm, Space.sm, Space.sm),
  });
  final Color tone;
  final IconData? icon;
  final Widget child;
  final Widget? trailing;
  final VoidCallback? onTap;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: tone.withValues(alpha: 0.08),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.md),
        side: BorderSide(color: tone.withValues(alpha: 0.28)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: padding,
          child: Row(
            children: [
              if (icon != null) ...[Icon(icon, size: 18, color: tone), const SizedBox(width: Space.md)],
              Expanded(child: child),
              ?trailing,
            ],
          ),
        ),
      ),
    );
  }
}

/// A square tile with an icon over a label, for grids of destinations.
class ActionTile extends StatelessWidget {
  const ActionTile({super.key, required this.icon, required this.label, required this.onTap, this.color});
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final enabled = onTap != null;
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: SurfaceCard(
        radius: Radii.md,
        padding: const EdgeInsets.symmetric(horizontal: Space.sm, vertical: Space.md),
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconTile(icon: icon, color: color ?? p.accent, size: 38),
            const SizedBox(height: Space.sm),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: p.text),
            ),
          ],
        ),
      ),
    );
  }
}

/// Opens a bottom sheet of actions and returns the picked value.
Future<T?> showActionSheet<T>(
  BuildContext context, {
  String? title,
  required List<({IconData icon, String title, String? subtitle, T value, bool destructive, bool enabled})> actions,
}) => showModalBottomSheet<T>(
  context: context,
  builder: (sheet) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.md),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, Space.md),
              child: Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(sheet).textTheme.titleMedium,
              ),
            ),
          SettingsGroup(
            children: [
              for (final a in actions)
                Opacity(
                  opacity: a.enabled ? 1 : 0.45,
                  child: SettingsRow(
                    icon: a.icon,
                    title: a.title,
                    subtitle: a.subtitle,
                    destructive: a.destructive,
                    trailing: const SizedBox.shrink(),
                    onTap: a.enabled ? () => Navigator.pop(sheet, a.value) : null,
                  ),
                ),
            ],
          ),
        ],
      ),
    ),
  ),
);

/// Centered picture, title and message for empty lists.
class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, this.message, this.action});
  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: Space.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: p.surface,
              borderRadius: BorderRadius.circular(Radii.lg),
              border: Border.all(color: p.border),
            ),
            child: Icon(icon, size: 26, color: p.muted),
          ),
          const SizedBox(height: Space.lg),
          Text(title, style: text.titleMedium, textAlign: TextAlign.center),
          if (message != null) ...[
            const SizedBox(height: Space.xs),
            Text(message!, style: text.bodySmall, textAlign: TextAlign.center),
          ],
          if (action != null) ...[const SizedBox(height: Space.lg), action!],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Brand marks and tool icons

class Brand {
  const Brand(this.icon, this.color);
  final IconData icon;
  final Color color;
}

/// The provider's own mark when Simple Icons has it; a neutral glyph otherwise.
Brand providerBrand(BuildContext context, String id) {
  final p = context.palette;
  final dark = Theme.of(context).brightness == Brightness.dark;
  // Near-black brand colours vanish on the dark theme; lift them to the text colour.
  Color c(Color brand) => dark && brand.computeLuminance() < 0.05 ? p.text : brand;
  final key = id.toLowerCase();
  if (key.contains('anthropic')) return Brand(SimpleIcons.anthropic, c(SimpleIconColors.anthropic));
  if (key.contains('claude')) return Brand(SimpleIcons.claude, c(SimpleIconColors.claude));
  if (key.contains('google') || key.contains('gemini') || key.contains('vertex')) {
    return Brand(SimpleIcons.googlegemini, c(SimpleIconColors.googlegemini));
  }
  if (key.contains('xiaomi') || key.contains('mimo')) return Brand(SimpleIcons.xiaomi, c(SimpleIconColors.xiaomi));
  if (key.contains('deepseek')) return Brand(SimpleIcons.deepseek, c(SimpleIconColors.deepseek));
  if (key.contains('openrouter')) return Brand(SimpleIcons.openrouter, c(SimpleIconColors.openrouter));
  if (key.contains('mistral')) return Brand(SimpleIcons.mistralai, c(SimpleIconColors.mistralai));
  if (key.contains('ollama')) return Brand(SimpleIcons.ollama, c(SimpleIconColors.ollama));
  if (key.contains('hugging')) return Brand(SimpleIcons.huggingface, c(SimpleIconColors.huggingface));
  if (key.contains('nvidia')) return Brand(SimpleIcons.nvidia, c(SimpleIconColors.nvidia));
  if (key.contains('perplexity')) return Brand(SimpleIcons.perplexity, c(SimpleIconColors.perplexity));
  if (key.contains('cloudflare')) return Brand(SimpleIcons.cloudflare, c(SimpleIconColors.cloudflare));
  if (key.contains('meta') || key.contains('llama')) return Brand(SimpleIcons.meta, c(SimpleIconColors.meta));
  if (key == 'xai' || key.contains('grok')) return Brand(SimpleIcons.x, c(SimpleIconColors.x));
  if (key.contains('github')) return Brand(SimpleIcons.github, c(SimpleIconColors.github));
  if (key.contains('vercel')) return Brand(SimpleIcons.vercel, c(SimpleIconColors.vercel));
  if (key.contains('openai') || key.contains('azure') || key.contains('codex')) {
    return Brand(LucideIcons.sparkle, p.text);
  }
  if (key.contains('bedrock') || key.contains('amazon')) return Brand(LucideIcons.cloud, const Color(0xFFFF9900));
  if (key.contains('llama.cpp') || key.contains('local')) return Brand(LucideIcons.cpu, p.muted);
  // Endpoints the user defined themselves: an unknown host, not a known vendor.
  if (key.startsWith('custom-')) return Brand(LucideIcons.server, p.muted);
  return Brand(LucideIcons.bot, p.muted);
}

/// Brand mark rendered in a soft tile.
class BrandTile extends StatelessWidget {
  const BrandTile({super.key, required this.id, this.size = 36});
  final String id;
  final double size;

  @override
  Widget build(BuildContext context) {
    final b = providerBrand(context, id);
    return IconTile(icon: b.icon, color: b.color, size: size);
  }
}

IconData toolIcon(String? name) => switch (name) {
  'bash' => LucideIcons.squareTerminal,
  'read' => LucideIcons.fileText,
  'write' => LucideIcons.filePlus2,
  'edit' => LucideIcons.filePen,
  'grep' => LucideIcons.textSearch,
  'find' || 'ls' => LucideIcons.folderSearch,
  'web_search' => LucideIcons.search,
  'web_fetch' => LucideIcons.globe,
  _ => LucideIcons.wrench,
};
