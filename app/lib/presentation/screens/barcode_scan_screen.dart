import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';

/// Camera barcode scanner. Requests camera permission first and handles the
/// denied / permanently-denied cases gracefully so the feature never "just
/// silently fails". Returns the scanned string via Navigator.pop.
class BarcodeScanScreen extends StatefulWidget {
  const BarcodeScanScreen({super.key});

  @override
  State<BarcodeScanScreen> createState() => _BarcodeScanScreenState();
}

enum _PermState { checking, granted, denied, permanentlyDenied }

class _BarcodeScanScreenState extends State<BarcodeScanScreen> {
  MobileScannerController? _controller;
  bool _handled = false;
  _PermState _perm = _PermState.checking;

  @override
  void initState() {
    super.initState();
    _requestPermission();
  }

  Future<void> _requestPermission() async {
    setState(() => _perm = _PermState.checking);
    PermissionStatus status = await Permission.camera.status;
    if (!status.isGranted) {
      status = await Permission.camera.request();
    }
    if (!mounted) return;
    if (status.isGranted) {
      setState(() {
        _perm = _PermState.granted;
        _controller = MobileScannerController(
          detectionSpeed: DetectionSpeed.noDuplicates,
        );
      });
    } else if (status.isPermanentlyDenied) {
      setState(() => _perm = _PermState.permanentlyDenied);
    } else {
      setState(() => _perm = _PermState.denied);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    final List<Barcode> codes = capture.barcodes;
    if (codes.isEmpty) return;
    final String? value = codes.first.rawValue;
    if (value == null || value.isEmpty) return;
    _handled = true;
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan barcode'),
        actions: _perm == _PermState.granted && _controller != null
            ? <Widget>[
                IconButton(
                  icon: const Icon(Icons.flash_on),
                  onPressed: () => _controller!.toggleTorch(),
                ),
                IconButton(
                  icon: const Icon(Icons.cameraswitch_outlined),
                  onPressed: () => _controller!.switchCamera(),
                ),
              ]
            : null,
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    switch (_perm) {
      case _PermState.checking:
        return const Center(child: CircularProgressIndicator());
      case _PermState.granted:
        return Stack(
          alignment: Alignment.center,
          children: <Widget>[
            MobileScanner(
              controller: _controller!,
              onDetect: _onDetect,
              errorBuilder: (BuildContext context, MobileScannerException error,
                  Widget? child) {
                return _PermMessage(
                  title: 'Camera error',
                  body: 'Could not start the camera. Enter the barcode '
                      'manually instead.',
                  primaryLabel: 'Enter manually',
                  onPrimary: () => Navigator.of(context).pop(),
                );
              },
            ),
            IgnorePointer(
              child: Container(
                width: 240,
                height: 240,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white, width: 2),
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ],
        );
      case _PermState.denied:
        return _PermMessage(
          title: 'Camera permission needed',
          body: 'Allow camera access to scan barcodes, or enter the barcode '
              'manually.',
          primaryLabel: 'Grant permission',
          onPrimary: _requestPermission,
          secondaryLabel: 'Enter manually',
          onSecondary: () => Navigator.of(context).pop(),
        );
      case _PermState.permanentlyDenied:
        return _PermMessage(
          title: 'Camera blocked',
          body: 'Camera permission is turned off for this app. Open Settings '
              'to enable it, or enter the barcode manually.',
          primaryLabel: 'Open settings',
          onPrimary: openAppSettings,
          secondaryLabel: 'Enter manually',
          onSecondary: () => Navigator.of(context).pop(),
        );
    }
  }
}

class _PermMessage extends StatelessWidget {
  final String title;
  final String body;
  final String primaryLabel;
  final VoidCallback onPrimary;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  const _PermMessage({
    required this.title,
    required this.body,
    required this.primaryLabel,
    required this.onPrimary,
    this.secondaryLabel,
    this.onSecondary,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.photo_camera_outlined, size: 56),
            const SizedBox(height: 16),
            Text(title,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(body, textAlign: TextAlign.center),
            const SizedBox(height: 20),
            ElevatedButton(onPressed: onPrimary, child: Text(primaryLabel)),
            if (secondaryLabel != null) ...<Widget>[
              const SizedBox(height: 10),
              OutlinedButton(
                onPressed: onSecondary,
                child: Text(secondaryLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
