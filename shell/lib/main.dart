import 'package:flutter/material.dart';
import 'package:halo_sdk/halo_sdk.dart';
import 'package:halo_ui/halo_ui.dart';

import 'lock/lock_screen.dart';

/// Only the mock backend exists so far (`--dart-define=HALO_BACKEND=mock`).
const _backendName = String.fromEnvironment(
  'HALO_BACKEND',
  defaultValue: 'mock',
);

HaloBackend createBackend() => switch (_backendName) {
  'mock' => MockBackend(),
  final other => throw StateError('Unknown HALO_BACKEND "$other"'),
};

void main() => runApp(HaloShell(backend: createBackend()));

class HaloShell extends StatefulWidget {
  const HaloShell({super.key, required this.backend});

  final HaloBackend backend;

  @override
  State<HaloShell> createState() => _HaloShellState();
}

class _HaloShellState extends State<HaloShell> {
  bool _locked = true;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: HaloTheme.dark(),
      home: Scaffold(
        body: _locked
            ? LockScreen(
                backend: widget.backend,
                onUnlock: () => setState(() => _locked = false),
              )
            : _HomePlaceholder(onLock: () => setState(() => _locked = true)),
      ),
    );
  }
}

/// Stand-in until the Home arc is built.
class _HomePlaceholder extends StatelessWidget {
  const _HomePlaceholder({required this.onLock});

  final VoidCallback onLock;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const HaloKicker('Home · next'),
        const SizedBox(height: HaloSpace.g18),
        HaloButton(
          label: 'Lock',
          variant: HaloButtonVariant.secondary,
          onPressed: onLock,
        ),
      ],
    ),
  );
}
