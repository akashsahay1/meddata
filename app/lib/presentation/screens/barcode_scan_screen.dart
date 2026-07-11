import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../theme/app_theme.dart';
import '../widgets/ui_kit.dart';

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
    final bool scanning = _perm == _PermState.granted;
    // While the live camera is up, use a dark green surface so the reticle and
    // controls read clearly over the feed. Otherwise keep the calm app canvas.
    return Scaffold(
      backgroundColor: scanning ? AppColors.greenDarkest : AppColors.canvas,
      appBar: AppBar(
        backgroundColor: scanning ? AppColors.greenDarkest : null,
        foregroundColor: scanning ? Colors.white : null,
        elevation: 0,
        title: const Text('Scan barcode'),
        actions: scanning && _controller != null
            ? <Widget>[
                _ScanAction(
                  icon: Icons.flash_on,
                  onTap: () => _controller!.toggleTorch(),
                ),
                _ScanAction(
                  icon: Icons.cameraswitch_outlined,
                  onTap: () => _controller!.switchCamera(),
                ),
                const SizedBox(width: 4),
              ]
            : null,
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    switch (_perm) {
      case _PermState.checking:
        return const Center(
          child: CircularProgressIndicator(
            color: AppColors.orange,
            strokeWidth: 3,
          ),
        );
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
                  icon: Icons.videocam_off_outlined,
                  title: 'Camera error',
                  body: 'Could not start the camera. Enter the barcode '
                      'manually instead.',
                  primaryLabel: 'Enter manually',
                  onPrimary: () => Navigator.of(context).pop(),
                );
              },
            ),
            const IgnorePointer(child: _ScanReticle()),
            const Positioned(
              left: 32,
              right: 32,
              bottom: 48,
              child: _ScanHint(),
            ),
          ],
        );
      case _PermState.denied:
        return _PermMessage(
          icon: Icons.photo_camera_outlined,
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
          icon: Icons.no_photography_outlined,
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

/// Round, translucent app-bar control used over the live camera feed.
class _ScanAction extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _ScanAction({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      child: Material(
        color: Colors.white.withValues(alpha: 0.14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(11),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            width: 38,
            height: 38,
            child: Icon(icon, size: 20, color: Colors.white),
          ),
        ),
      ),
    );
  }
}

/// The framing box drawn over the camera feed: rounded window with orange
/// corner brackets, matching the brand accent.
class _ScanReticle extends StatelessWidget {
  const _ScanReticle();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 248,
      height: 248,
      child: CustomPaint(painter: _ReticlePainter()),
    );
  }
}

class _ReticlePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const double radius = AppRadii.cardLg;
    final RRect window = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(radius),
    );

    // Faint frame around the whole window.
    final Paint frame = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = Colors.white.withValues(alpha: 0.35);
    canvas.drawRRect(window, frame);

    // Orange corner brackets.
    final Paint corner = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..color = AppColors.orange;

    const double len = 30;
    final double w = size.width;
    final double h = size.height;

    // Top-left.
    canvas.drawPath(
      Path()
        ..moveTo(0, radius + len)
        ..lineTo(0, radius)
        ..arcToPoint(const Offset(radius, 0),
            radius: const Radius.circular(radius))
        ..lineTo(radius + len, 0),
      corner,
    );
    // Top-right.
    canvas.drawPath(
      Path()
        ..moveTo(w - radius - len, 0)
        ..lineTo(w - radius, 0)
        ..arcToPoint(Offset(w, radius),
            radius: const Radius.circular(radius))
        ..lineTo(w, radius + len),
      corner,
    );
    // Bottom-right.
    canvas.drawPath(
      Path()
        ..moveTo(w, h - radius - len)
        ..lineTo(w, h - radius)
        ..arcToPoint(Offset(w - radius, h),
            radius: const Radius.circular(radius))
        ..lineTo(w - radius - len, h),
      corner,
    );
    // Bottom-left.
    canvas.drawPath(
      Path()
        ..moveTo(radius + len, h)
        ..lineTo(radius, h)
        ..arcToPoint(Offset(0, h - radius),
            radius: const Radius.circular(radius))
        ..lineTo(0, h - radius - len),
      corner,
    );
  }

  @override
  bool shouldRepaint(covariant _ReticlePainter oldDelegate) => false;
}

/// Instructional pill shown under the reticle.
class _ScanHint extends StatelessWidget {
  const _ScanHint();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(AppRadii.pill),
        ),
        child: const Text(
          'Point the camera at a barcode',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white,
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _PermMessage extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  final String primaryLabel;
  final VoidCallback onPrimary;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  const _PermMessage({
    required this.icon,
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
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Container(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(AppRadii.cardLg),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: AppColors.green,
                  borderRadius: BorderRadius.circular(AppRadii.card),
                ),
                child: Icon(icon, size: 28, color: Colors.white),
              ),
              const SizedBox(height: 18),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.4,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                body,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14,
                  height: 1.45,
                  fontWeight: FontWeight.w500,
                  color: AppColors.muted,
                ),
              ),
              const SizedBox(height: 22),
              PrimaryButton(label: primaryLabel, onPressed: onPrimary),
              if (secondaryLabel != null) ...<Widget>[
                const SizedBox(height: 10),
                SecondaryButton(
                  label: secondaryLabel!,
                  onPressed: onSecondary,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
