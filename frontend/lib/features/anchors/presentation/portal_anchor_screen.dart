import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../navigation_ui/presentation/controllers/live_session_scope.dart';

typedef PortalScannerBuilder = Widget Function(ValueChanged<String> onPayload);

class PortalAnchorUiResult {
  const PortalAnchorUiResult({required this.accepted, required this.message});

  final bool accepted;
  final String message;
}

class LivePortalAnchorScreen extends StatelessWidget {
  const LivePortalAnchorScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final session = LiveSessionScope.of(context);
    return PortalAnchorScreen(
      onPayload: (payload) async {
        final result = session.applyPortalPayload(payload);
        return PortalAnchorUiResult(
          accepted: result.accepted,
          message: result.message,
        );
      },
    );
  }
}

class PortalAnchorScreen extends StatefulWidget {
  const PortalAnchorScreen({
    super.key,
    required this.onPayload,
    this.scannerBuilder,
  });

  final Future<PortalAnchorUiResult> Function(String payload) onPayload;
  final PortalScannerBuilder? scannerBuilder;

  @override
  State<PortalAnchorScreen> createState() => _PortalAnchorScreenState();
}

class _PortalAnchorScreenState extends State<PortalAnchorScreen> {
  bool _busy = false;
  PortalAnchorUiResult? _result;
  late final MobileScannerController _scannerController = MobileScannerController(
    formats: const [BarcodeFormat.qrCode, BarcodeFormat.dataMatrix],
    detectionSpeed: DetectionSpeed.noDuplicates,
  );

  @override
  void dispose() {
    _scannerController.dispose();
    super.dispose();
  }

  Future<void> _handle(String payload) async {
    if (_busy || payload.trim().isEmpty) return;
    setState(() => _busy = true);
    final result = await widget.onPayload(payload.trim());
    if (!mounted) return;
    setState(() {
      _result = result;
      _busy = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final scanner = widget.scannerBuilder?.call(_handle) ??
        MobileScanner(
          controller: _scannerController,
          onDetect: (capture) {
            final payload = capture.barcodes.firstOrNull?.rawValue;
            if (payload != null) unawaited(_handle(payload));
          },
        );
    return Scaffold(
      appBar: AppBar(title: const Text('Trusted portal anchor')),
      body: Column(
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Camera frames are processed on this phone and are not saved or uploaded. '
              'Only markers from the installed local anchor pack can correct navigation.',
            ),
          ),
          Expanded(child: scanner),
          if (_busy) const LinearProgressIndicator(),
          if (_result case final result?)
            Semantics(
              liveRegion: true,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                color: result.accepted
                    ? Colors.green.withValues(alpha: 0.14)
                    : Colors.orange.withValues(alpha: 0.14),
                child: Text(
                  result.message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
