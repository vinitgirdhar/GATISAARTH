import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../core/nav/anchors/visual_landmark_matcher.dart';
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
      onVisualDescriptor: (descriptor) async {
        final result = session.applyVisualDescriptor(descriptor);
        return PortalAnchorUiResult(
          accepted: result.accepted,
          message: result.message,
        );
      },
      onRadioRange: () async {
        final result = await session.rangeRadioAnchor();
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
    this.onVisualDescriptor,
    this.onRadioRange,
  });

  final Future<PortalAnchorUiResult> Function(String payload) onPayload;
  final PortalScannerBuilder? scannerBuilder;
  final Future<PortalAnchorUiResult> Function(String descriptor)?
      onVisualDescriptor;
  final Future<PortalAnchorUiResult> Function()? onRadioRange;

  @override
  State<PortalAnchorScreen> createState() => _PortalAnchorScreenState();
}

class _PortalAnchorScreenState extends State<PortalAnchorScreen> {
  bool _busy = false;
  PortalAnchorUiResult? _result;
  late final MobileScannerController _scannerController =
      MobileScannerController(
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
    try {
      final result = await widget.onPayload(payload.trim());
      if (mounted) setState(() => _result = result);
    } catch (_) {
      if (mounted) {
        setState(() => _result = const PortalAnchorUiResult(
              accepted: false,
              message: 'Marker processing failed; no correction applied',
            ));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _captureLandmark() async {
    if (_busy || widget.onVisualDescriptor == null) return;
    setState(() => _busy = true);
    XFile? photo;
    try {
      await _scannerController.stop();
      photo = await ImagePicker().pickImage(
        source: ImageSource.camera,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 80,
        requestFullMetadata: false,
      );
      if (photo == null) return;
      final bytes = await photo.readAsBytes();
      final descriptor = await compute(VisualLandmarkMatcher.describe, bytes);
      if (!mounted) return;
      final result = descriptor == null
          ? const PortalAnchorUiResult(
              accepted: false,
              message:
                  'Image has insufficient detail for a safe landmark match',
            )
          : await widget.onVisualDescriptor!(descriptor);
      if (mounted) setState(() => _result = result);
    } catch (_) {
      if (mounted) {
        setState(() => _result = const PortalAnchorUiResult(
              accepted: false,
              message: 'Camera unavailable; no landmark correction applied',
            ));
      }
    } finally {
      if (photo != null) {
        try {
          await File(photo.path).delete();
        } catch (_) {
          // Camera-owned cache may already have been removed.
        }
      }
      if (mounted) {
        try {
          await _scannerController.start();
        } catch (_) {
          // Camera permission may have been revoked while the picker was open.
        }
        if (mounted) setState(() => _busy = false);
      }
    }
  }

  Future<void> _rangeRadio() async {
    if (_busy || widget.onRadioRange == null) return;
    setState(() => _busy = true);
    try {
      final result = await widget.onRadioRange!();
      if (mounted) setState(() => _result = result);
    } catch (_) {
      if (mounted) {
        setState(() => _result = const PortalAnchorUiResult(
              accepted: false,
              message: 'Wi-Fi RTT is unavailable; no correction applied',
            ));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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
              'Camera frames are processed on this phone and are not uploaded. '
              'A captured landmark photo is deleted from temporary storage after matching. '
              'Only markers from the installed local anchor pack can correct navigation.',
            ),
          ),
          Expanded(child: scanner),
          if (widget.onVisualDescriptor != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: FilledButton.icon(
                onPressed: _busy ? null : _captureLandmark,
                icon: const Icon(Icons.camera_alt_outlined),
                label: const Text('Match offline landmark'),
              ),
            ),
          if (widget.onRadioRange != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: OutlinedButton.icon(
                onPressed: _busy ? null : _rangeRadio,
                icon: const Icon(Icons.wifi_tethering_rounded),
                label: const Text('Try nearby Wi-Fi RTT anchor'),
              ),
            ),
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
