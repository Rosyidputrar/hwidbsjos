import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'predictive_back.dart';

/// Design tokens. Clean and light by default: white canvas, soft grey
/// surfaces, near-black for primary actions, and colour only in accents and
/// the mesh artwork on cards.
@immutable
class Palette extends ThemeExtension<Palette> {
  const Palette({
    required this.bg,
    required this.surface,
    required this.raised,
    required this.border,
    required this.text,
    required this.muted,
    required this.faint,
    required this.inverse,
    required this.danger,
    required this.success,
    required this.warning,
    required this.accent,
    required this.accentAlt,
    required this.glass,
    required this.nav,
  });

  final Color bg;
  final Color surface;
  final Color raised;
  final Color border;
  final Color text;
  final Color muted;
  final Color faint;
  final Color inverse;
  final Color danger;
  final Color success;
  final Color warning;
  final Color accent;
  final Color accentAlt;

  /// Translucent fill for floating bars over content.
  final Color glass;

  /// The floating bottom navigation bar.
  final Color nav;

  /// Text and icons on an accent fill: white or near-black, whichever reads better on the chosen
  /// accent. White only works on the darker light-mode purple and blue; on the others it is 1.9-3:1.
  Color get onAccent {
    final l = accent.computeLuminance();
    const ink = Color(0xFF111113);
    return 1.05 / (l + 0.05) >= (l + 0.05) / (ink.computeLuminance() + 0.05) ? Colors.white : ink;
  }

  /// The accent as a colour for text (a link, "See all", a section's action): the accent itself where it reads at 4.5:1
  /// on both the page and a card, and otherwise made darker (lighter in the dark theme) until it does. In the light theme
  /// green, orange, pink and teal were 2.7 to 4.1:1 as text; their fills stay as chosen.
  Color get accentText {
    double worst(Color c) {
      double ratio(Color b) {
        final a = c.computeLuminance(), l = b.computeLuminance();
        return (a > l ? a + 0.05 : l + 0.05) / (a > l ? l + 0.05 : a + 0.05);
      }

      final x = ratio(bg), y = ratio(surface);
      return x < y ? x : y;
    }

    final darken = bg.computeLuminance() > 0.5;
    var hsl = HSLColor.fromColor(accent);
    var c = accent;
    for (var i = 0; i < 60 && worst(c) < 4.5; i++) {
      hsl = hsl.withLightness((hsl.lightness + (darken ? -0.01 : 0.01)).clamp(0.0, 1.0));
      c = hsl.toColor();
    }
    return c;
  }

  /// Text and icons on a danger fill, chosen the same way: white was 2.9:1 on the dark theme's light red.
  Color get onDanger {
    final l = danger.computeLuminance();
    const ink = Color(0xFF111113);
    return 1.05 / (l + 0.05) >= (l + 0.05) / (ink.computeLuminance() + 0.05) ? Colors.white : ink;
  }

  static const light = Palette(
    bg: Color(0xFFF6F6F8),
    surface: Color(0xFFFFFFFF),
    raised: Color(0xFFEFEFF2),
    border: Color(0xFFE4E4E9),
    text: Color(0xFF0F0F12),
    muted: Color(0xFF64646E),
    faint: Color(0xFFA1A1AA),
    inverse: Color(0xFFFFFFFF),
    // Rynex's light red/green/orange, darkened one step: as shipped they read
    // 2.9-3.6:1 on the page, under the 4.5:1 small-text bar the app holds.
    danger: Color(0xFFC03C41),
    success: Color(0xFF247A52),
    warning: Color(0xFFA9530B),
    accent: Color(0xFF3F8F1C),
    accentAlt: Color(0xFF3E63DD),
    glass: Color(0xEBFFFFFF),
    nav: Color(0xFFFFFFFF),
  );

  static const dark = Palette(
    bg: Color(0xFF09090B),
    surface: Color(0xFF131316),
    raised: Color(0xFF1C1C21),
    border: Color(0xFF27272D),
    text: Color(0xFFF4F4F6),
    muted: Color(0xFFA0A0AB),
    faint: Color(0xFF63636D),
    inverse: Color(0xFF09090B),
    danger: Color(0xFFFF6369),
    success: Color(0xFF3DD68C),
    warning: Color(0xFFFF8B3E),
    accent: Color(0xFFA3E635),
    accentAlt: Color(0xFF7B93FF),
    glass: Color(0xE6131316),
    nav: Color(0xFF131316),
  );

  @override
  Palette copyWith({Color? accent}) => accent == null
      ? this
      : Palette(
          bg: bg,
          surface: surface,
          raised: raised,
          border: border,
          text: text,
          muted: muted,
          faint: faint,
          inverse: inverse,
          danger: danger,
          success: success,
          warning: warning,
          accent: accent,
          accentAlt: accentAlt,
          glass: glass,
          nav: nav,
        );

  @override
  Palette lerp(Palette? other, double t) => t < 0.5 ? this : (other ?? this);
}

extension PaletteX on BuildContext {
  Palette get palette => Theme.of(this).extension<Palette>()!;
}

const mono = 'GeistMono';

/// Accent colours the user can pick, as (light, dark) pairs. The first is the default Rynex lime.
/// What each accent is called, in [accentChoices]' order (read out by a screen reader).
const accentNames = ['Lime', 'Blue', 'Green', 'Orange', 'Pink', 'Teal', 'Violet', 'Indigo'];

const accentChoices = <(Color, Color)>[
  (Color(0xFF3F8F1C), Color(0xFFA3E635)),
  (Color(0xFF3E63DD), Color(0xFF7B93FF)),
  (Color(0xFF30A46C), Color(0xFF3DD68C)),
  (Color(0xFFF76B15), Color(0xFFFF8B3E)),
  (Color(0xFFD6409F), Color(0xFFF07CC0)),
  (Color(0xFF12A594), Color(0xFF3BD3C0)),
  // Appended, so saved indexes keep pointing at the same colours.
  (Color(0xFF7656F2), Color(0xFFA48CFF)),
  (Color(0xFF5B5BD6), Color(0xFF8B8DFF)),
];

/// UI preferences remembered on the device: theme, text size, density, accent, language, app lock, and
/// whether the welcome screen was seen.
class Appearance extends ValueNotifier<ThemeMode> {
  Appearance._() : super(ThemeMode.system) {
    try {
      final saved = jsonDecode(_file.readAsStringSync()) as Map<String, dynamic>;
      value = ThemeMode.values.firstWhere((m) => m.name == saved['theme'], orElse: () => ThemeMode.system);
      onboarded = saved['onboarded'] == true;
      textScale = (saved['textScale'] as num?)?.toDouble() ?? 1;
      compact = saved['compact'] == true;
      accent = ((saved['accent'] as num?)?.toInt() ?? 0).clamp(0, accentChoices.length - 1);
      language = saved['language'] as String? ?? 'en';
      appLock = saved['appLock'] == true;
      terminalFontSize = (saved['terminalFontSize'] as num?)?.toDouble() ?? terminalFontSize;
      // A modifiable copy: older ui.json files have no entry, and a const map can't be written to.
      deployTargets = {
        for (final e in (saved['deployTargets'] as Map? ?? {}).entries)
          if (e.key is String && e.value is String) e.key as String: e.value as String,
      };
      favoriteModels = [
        for (final e in (saved['favoriteModels'] as List? ?? []))
          if (e is String) e,
      ];
      trustedDomains = [
        for (final e in (saved['trustedDomains'] as List? ?? []))
          if (e is String && e.isNotEmpty) e,
      ];
    } catch (_) {}
  }

  static final instance = Appearance._();
  static final _file = File('/data/data/com.airynex.agent/files/ui.json');

  bool onboarded = false;
  double textScale = 1;
  bool compact = false;
  int accent = 0;
  String language = 'en';
  bool appLock = false;

  /// Pinch or A−/A+ in the terminal.
  double terminalFontSize = 12.5;

  void set(ThemeMode mode) {
    value = mode;
    _save();
  }

  void update({
    double? textScale,
    bool? compact,
    int? accent,
    String? language,
    bool? appLock,
    double? terminalFontSize,
  }) {
    this.terminalFontSize = terminalFontSize ?? this.terminalFontSize;
    this.textScale = textScale ?? this.textScale;
    this.compact = compact ?? this.compact;
    this.accent = accent ?? this.accent;
    this.language = language ?? this.language;
    this.appLock = appLock ?? this.appLock;
    _save();
    notifyListeners();
  }

  /// Saved without notifying: only the terminal reads it, so the rest of the app needn't rebuild.
  void setTerminalFontSize(double size) {
    terminalFontSize = size;
    _save();
  }

  /// Model keys ('provider/id') starred in the model picker, in starring order.
  /// Keys whose model left the catalog stay stored, so they reappear if it returns.
  List<String> favoriteModels = [];

  bool isFavorite(String key) => favoriteModels.contains(key);

  /// Hosts whose links open without asking first ("Always trust this domain").
  List<String> trustedDomains = [];

  bool isTrusted(String host) => trustedDomains.contains(host.toLowerCase());

  void trustDomain(String host) {
    final h = host.toLowerCase();
    if (h.isEmpty || trustedDomains.contains(h)) return;
    trustedDomains = [...trustedDomains, h]..sort();
    _save();
    notifyListeners();
  }

  void untrustDomain(String host) {
    trustedDomains = trustedDomains.where((d) => d != host.toLowerCase()).toList();
    _save();
    notifyListeners();
  }

  void toggleFavorite(String key) {
    favoriteModels = List.of(favoriteModels);
    if (!favoriteModels.remove(key)) favoriteModels.add(key);
    _save();
    notifyListeners();
  }

  /// The deploy target last used per project folder, so the deploy sheet opens on it.
  Map<String, String> deployTargets = {};

  void setDeployTarget(String project, String target) {
    deployTargets = Map.of(deployTargets);
    deployTargets
      ..remove(project)
      ..[project] = target;
    while (deployTargets.length > 50) {
      deployTargets.remove(deployTargets.keys.first);
    }
    _save();
  }

  void finishOnboarding() {
    onboarded = true;
    _save();
    notifyListeners();
  }

  void _save() {
    try {
      _file.writeAsStringSync(
        jsonEncode({
          'theme': value.name,
          'onboarded': onboarded,
          'textScale': textScale,
          'compact': compact,
          'accent': accent,
          'language': language,
          'appLock': appLock,
          'terminalFontSize': terminalFontSize,
          'deployTargets': deployTargets,
          'favoriteModels': favoriteModels,
          'trustedDomains': trustedDomains,
        }),
      );
    } catch (_) {}
  }
}

/// Corner-radius scale. Pick by what the shape is, not by a pixel value:
/// [xs] hairline bars and code chips, [sm] small controls and tags, [md]
/// tiles, bubbles and list highlights, [lg] buttons and fields, [xl] cards,
/// [sheet] bottom sheets and dialogs, [pill] anything fully rounded.
class Radii {
  const Radii._();

  static const double xs = 6;
  static const double sm = 10;
  static const double md = 14;
  static const double lg = 20;
  static const double xl = 28;
  static const double sheet = 28;
  static const double pill = 99;
}

/// Spacing scale. Every padding and gap in the UI is one of these.
abstract final class Space {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 28;

  /// Horizontal padding of every page.
  static const double page = 20;
}

/// Motion shared by the app's animations, so they feel like one family: short, easing out.
/// [of] honours Android's "Remove animations" setting.
class Motion {
  const Motion._();

  /// State changes on one control (a chevron turning, a pill changing colour).
  static const fast = Duration(milliseconds: 150);

  /// Things appearing, resizing or swapping (a card sliding in, a section opening).
  static const normal = Duration(milliseconds: 240);

  static const curve = Curves.easeOutCubic;

  /// True when the user asked the system to remove animations.
  static bool reduced(BuildContext context) => MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  /// [d], or no time at all when animations are off.
  static Duration of(BuildContext context, Duration d) => reduced(context) ? Duration.zero : d;
}

ThemeData buildTheme(Brightness brightness) {
  final look = Appearance.instance;
  final light = brightness == Brightness.light;
  final pick = accentChoices[look.accent];
  final p = (light ? Palette.light : Palette.dark).copyWith(
    accent: look.accent == 0 ? null : (light ? pick.$1 : pick.$2),
  );
  final base = ThemeData(
    brightness: brightness,
    useMaterial3: true,
    fontFamily: 'Geist',
    splashFactory: InkSparkle.splashFactory,
    visualDensity: look.compact ? VisualDensity.compact : VisualDensity.standard,
  );

  TextStyle t(double size, FontWeight w, Color c, {double height = 1.4, double spacing = 0}) =>
      TextStyle(fontFamily: 'Geist', fontSize: size, fontWeight: w, color: c, height: height, letterSpacing: spacing);

  final text = TextTheme(
    displayMedium: t(32, FontWeight.w600, p.text, height: 1.1, spacing: -1.2),
    displaySmall: t(28, FontWeight.w600, p.text, height: 1.12, spacing: -1),
    headlineSmall: t(23, FontWeight.w600, p.text, height: 1.2, spacing: -0.6),
    titleLarge: t(18, FontWeight.w600, p.text, height: 1.3, spacing: -0.3),
    titleMedium: t(16, FontWeight.w600, p.text, spacing: -0.2),
    titleSmall: t(14.5, FontWeight.w600, p.text, spacing: -0.1),
    bodyLarge: t(15.5, FontWeight.w400, p.text, height: 1.6),
    bodyMedium: t(14, FontWeight.w400, p.text, height: 1.5),
    bodySmall: t(12.5, FontWeight.w400, p.muted, height: 1.45),
    labelLarge: t(14.5, FontWeight.w600, p.text),
    labelMedium: t(12.5, FontWeight.w500, p.muted),
    labelSmall: t(11, FontWeight.w600, p.faint, spacing: 0.8),
  );

  final scheme = ColorScheme(
    brightness: brightness,
    primary: p.accent,
    onPrimary: p.onAccent,
    secondary: p.accent,
    onSecondary: p.onAccent,
    error: p.danger,
    onError: Colors.white,
    surface: p.bg,
    onSurface: p.text,
    onSurfaceVariant: p.muted,
    surfaceContainerLowest: p.bg,
    surfaceContainerLow: p.surface,
    surfaceContainer: p.surface,
    surfaceContainerHigh: p.raised,
    surfaceContainerHighest: p.raised,
    outline: p.border,
    outlineVariant: p.border,
    surfaceTint: Colors.transparent,
    secondaryContainer: p.raised,
    onSecondaryContainer: p.text,
  );

  final overlay = systemOverlayFor(brightness, p);
  final radius = BorderRadius.circular(Radii.md);
  final ink = light ? const Color(0xFF18181B) : p.raised;

  OutlineInputBorder field(Color c, [double w = 1]) => OutlineInputBorder(
    borderRadius: radius,
    borderSide: BorderSide(color: c, width: w),
  );

  return base.copyWith(
    colorScheme: scheme,
    scaffoldBackgroundColor: p.bg,
    canvasColor: p.bg,
    dividerColor: p.border,
    textTheme: text,
    extensions: [p],
    appBarTheme: AppBarTheme(
      backgroundColor: p.bg,
      foregroundColor: p.text,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleSpacing: 4,
      titleTextStyle: text.titleMedium,
      iconTheme: IconThemeData(color: p.text, size: 20),
      actionsIconTheme: IconThemeData(color: p.text, size: 20),
      systemOverlayStyle: overlay,
    ),
    dividerTheme: DividerThemeData(color: p.border, thickness: 1, space: 1),
    iconTheme: IconThemeData(color: p.text, size: 20),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(foregroundColor: p.text, highlightColor: p.raised, shape: const CircleBorder()),
    ),
    drawerTheme: DrawerThemeData(
      backgroundColor: p.bg,
      width: 320,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.horizontal(right: Radius.circular(Radii.xl))),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: p.bg,
      modalBackgroundColor: p.bg,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      dragHandleColor: p.border,
      dragHandleSize: const Size(36, 4),
      modalBarrierColor: Colors.black.withValues(alpha: 0.45),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.xl))),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: p.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.lg),
        side: BorderSide(color: p.border),
      ),
      titleTextStyle: text.titleLarge,
      contentTextStyle: text.bodyMedium,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: ink,
      contentTextStyle: text.bodyMedium!.copyWith(color: Colors.white),
      actionTextColor: light ? accentChoices[look.accent].$2 : p.accent,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.md),
        side: light ? BorderSide.none : BorderSide(color: p.border),
      ),
      elevation: 0,
      insetPadding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.lg),
    ),
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      filled: true,
      fillColor: p.surface,
      hintStyle: text.bodyMedium!.copyWith(color: p.faint),
      labelStyle: text.bodyMedium!.copyWith(color: p.muted),
      floatingLabelStyle: text.bodyMedium!.copyWith(color: p.accentText),
      helperStyle: text.bodySmall,
      prefixIconColor: p.faint,
      contentPadding: const EdgeInsets.symmetric(horizontal: Space.lg, vertical: 14),
      border: field(p.border),
      enabledBorder: field(p.border),
      focusedBorder: field(p.accent, 1.4),
      errorBorder: field(p.danger),
      focusedErrorBorder: field(p.danger, 1.4),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: p.accent,
        foregroundColor: p.onAccent,
        disabledBackgroundColor: p.raised,
        disabledForegroundColor: p.faint,
        minimumSize: const Size(0, 48),
        padding: const EdgeInsets.symmetric(horizontal: Space.xl),
        textStyle: text.labelLarge,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: radius),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: p.text,
        backgroundColor: p.surface,
        minimumSize: const Size(0, 48),
        padding: const EdgeInsets.symmetric(horizontal: Space.lg),
        textStyle: text.labelLarge,
        side: BorderSide(color: p.border),
        shape: RoundedRectangleBorder(borderRadius: radius),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: p.accentText,
        textStyle: text.labelLarge,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.sm)),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: p.surface,
      selectedColor: p.accent.withValues(alpha: 0.14),
      side: BorderSide(color: p.border),
      shape: const StadiumBorder(),
      labelStyle: text.labelMedium!.copyWith(color: p.text),
      secondaryLabelStyle: text.labelMedium!.copyWith(color: p.accentText),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      showCheckmark: false,
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        side: WidgetStatePropertyAll(BorderSide(color: p.border)),
        shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.md))),
        backgroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? p.accent.withValues(alpha: 0.14) : p.surface,
        ),
        foregroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? p.accent : p.muted),
        textStyle: WidgetStatePropertyAll(text.labelMedium!.copyWith(fontWeight: FontWeight.w600)),
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Colors.white : p.faint),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? p.accent : p.raised),
      trackOutlineColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? Colors.transparent : p.border,
      ),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? p.accent : null),
      side: BorderSide(color: p.faint, width: 1.5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
    ),
    listTileTheme: ListTileThemeData(
      iconColor: p.muted,
      textColor: p.text,
      titleTextStyle: text.bodyLarge,
      subtitleTextStyle: text.bodySmall,
      selectedColor: p.accent,
      selectedTileColor: p.accent.withValues(alpha: 0.08),
      contentPadding: const EdgeInsets.symmetric(horizontal: Space.xl),
      minVerticalPadding: 10,
      shape: RoundedRectangleBorder(borderRadius: radius),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: p.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 10,
      shadowColor: Colors.black.withValues(alpha: 0.18),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.md),
        side: BorderSide(color: p.border),
      ),
      textStyle: text.bodyMedium,
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(color: ink, borderRadius: BorderRadius.circular(Radii.sm)),
      textStyle: text.labelMedium!.copyWith(color: Colors.white),
    ),
    tabBarTheme: TabBarThemeData(
      labelColor: p.text,
      unselectedLabelColor: p.muted,
      indicatorColor: p.accent,
      dividerColor: p.border,
      labelStyle: text.labelLarge,
      unselectedLabelStyle: text.labelLarge,
    ),
    badgeTheme: BadgeThemeData(backgroundColor: p.accent, textColor: p.onAccent),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: p.accent, linearTrackColor: p.raised),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: p.accent,
      selectionColor: p.accent.withValues(alpha: 0.25),
      selectionHandleColor: p.accent,
    ),
    pageTransitionsTheme: const PageTransitionsTheme(builders: {TargetPlatform.android: SmoothPageTransitions()}),
  );
}

/// The status and navigation bars for a theme: dark icons on the light theme, light ones on the dark, over the app's own
/// background. Set for every screen (main.dart), not only those with an AppBar: Home, onboarding and the boot screens
/// have none, so a phone in dark mode could show white icons on the light Home.
SystemUiOverlayStyle systemOverlayFor(Brightness brightness, Palette p) =>
    (brightness == Brightness.light ? SystemUiOverlayStyle.dark : SystemUiOverlayStyle.light).copyWith(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: p.bg,
    );

/// The contrast ratio of two colours (WCAG): 1 to 21.
double contrastRatio(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  return (la > lb ? la + 0.05 : lb + 0.05) / (la > lb ? lb + 0.05 : la + 0.05);
}

/// Icons and text on a fill of [fill]: white or near-black, whichever reads better (white on amber, teal, orange or sky
/// was 2.2 to 2.8:1).
Color onFill(Color fill) {
  const ink = Color(0xFF111113);
  return contrastRatio(Colors.white, fill) >= contrastRatio(ink, fill) ? Colors.white : ink;
}

/// [fg] as a colour for text on [bg]: itself when it reads at [target]:1, otherwise darkened (or lightened on a dark
/// background), same hue, until it does.
Color readableOn(Color fg, Color bg, {double target = 4.5}) {
  final darken = bg.computeLuminance() > 0.5;
  var hsl = HSLColor.fromColor(fg);
  var c = fg;
  for (var i = 0; i < 60 && contrastRatio(c, bg) < target; i++) {
    hsl = hsl.withLightness((hsl.lightness + (darken ? -0.01 : 0.01)).clamp(0.0, 1.0));
    c = hsl.toColor();
  }
  return c;
}
