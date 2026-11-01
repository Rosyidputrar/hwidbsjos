import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'agent/agent_client.dart';
import 'agent/agent_controller.dart';
import 'ui/app_lock.dart';
import 'ui/home_shell.dart';
import 'ui/i18n.dart';
import 'ui/onboarding.dart';
import 'ui/kit.dart';
import 'ui/theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // The app's own license, next to the packages' licenses on the licenses page.
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks(const ['Rynex'], await rootBundle.loadString('LICENSE'));
  });
  final agent = AgentController(AgentClient())..boot();
  runApp(RynexApp(agent: agent));
}

class RynexApp extends StatelessWidget {
  const RynexApp({super.key, required this.agent});
  final AgentController agent;

  @override
  Widget build(BuildContext context) {
    final appearance = Appearance.instance;
    return ListenableBuilder(
      listenable: appearance,
      builder: (context, _) => MaterialApp(
        title: 'Rynex AI Agent',
        debugShowCheckedModeBanner: false,
        themeMode: appearance.value,
        theme: buildTheme(Brightness.light),
        darkTheme: buildTheme(Brightness.dark),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(appearance.textScale * MediaQuery.textScalerOf(context).scale(14) / 14),
          ),
          child: AppLockGate(child: child!),
        ),
        home: ListenableBuilder(
          listenable: agent,
          builder: (context, _) => AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: !appearance.onboarded
                ? OnboardingScreen(agent: agent)
                : switch (agent.status) {
                    BootStatus.ready => HomeShell(agent: agent),
                    BootStatus.starting => const _Boot(),
                    BootStatus.failed => _BootFailed(agent: agent),
                  },
          ),
        ),
      ),
    );
  }
}

class _Boot extends StatelessWidget {
  const _Boot();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const LogoMark(size: 64),
            const SizedBox(height: Space.xl),
            Text('Rynex', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: Space.lg),
            SizedBox(width: 140, child: LinearProgressIndicator(minHeight: 3, borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: Space.md),
            Text(tr('Starting agent'), style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _BootFailed extends StatelessWidget {
  const _BootFailed({required this.agent});
  final AgentController agent;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final text = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: Space.xxl),
              IconTile(icon: LucideIcons.triangleAlert, color: p.danger, size: 44),
              const SizedBox(height: Space.lg),
              Text(tr('The agent could not start'), style: text.headlineSmall),
              const SizedBox(height: Space.sm),
              Text(tr('Details from the runtime are below.'), style: text.bodyMedium?.copyWith(color: p.muted)),
              const SizedBox(height: Space.xl),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: p.surface,
                    borderRadius: BorderRadius.circular(Radii.md),
                    border: Border.all(color: p.border),
                  ),
                  child: SingleChildScrollView(
                    child: SelectableText(
                      agent.bootError ?? 'Unknown error',
                      style: TextStyle(fontFamily: mono, fontSize: 12, height: 1.5, color: p.text),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              PrimaryButton(icon: LucideIcons.rotateCcw, label: tr('Try again'), onPressed: agent.boot),
            ],
          ),
        ),
      ),
    );
  }
}
