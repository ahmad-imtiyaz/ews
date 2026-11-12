import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../data/monitoring.dart';

/// Bentuk berbeda per status, supaya status tetap terbaca tanpa melihat warna.
class StatusShape extends StatelessWidget {
  const StatusShape({super.key, required this.status, this.size = 32});

  final MonitoringStatus status;
  final double size;

  @override
  Widget build(BuildContext context) {
    final symbol = switch (status) {
      MonitoringStatus.normal => '',
      MonitoringStatus.waspada || MonitoringStatus.awas => '!',
      MonitoringStatus.noData => '?',
    };

    return SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: _StatusShapePainter(status),
        child: Center(
          child: Padding(
            padding: EdgeInsets.only(
              top: status == MonitoringStatus.waspada ? size * 0.22 : 0,
            ),
            child: Text(
              symbol,
              textScaler: TextScaler.noScaling,
              style: TextStyle(
                color: status == MonitoringStatus.noData
                    ? AppColors.ink
                    : status.foreground,
                fontSize: size * 0.5,
                fontWeight: FontWeight.w700,
                height: 1,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusShapePainter extends CustomPainter {
  const _StatusShapePainter(this.status);

  final MonitoringStatus status;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final strokeWidth = w * 0.08;
    final inset = strokeWidth / 2;

    final path = switch (status) {
      MonitoringStatus.normal || MonitoringStatus.noData =>
        Path()
          ..addOval(Rect.fromLTWH(inset, inset, w - inset * 2, h - inset * 2)),
      MonitoringStatus.waspada =>
        Path()
          ..moveTo(w / 2, inset)
          ..lineTo(w - inset, h - inset)
          ..lineTo(inset, h - inset)
          ..close(),
      MonitoringStatus.awas =>
        Path()
          ..moveTo(w / 2, inset)
          ..lineTo(w - inset, h / 2)
          ..lineTo(w / 2, h - inset)
          ..lineTo(inset, h / 2)
          ..close(),
    };

    if (status == MonitoringStatus.noData) {
      canvas.drawPath(path, Paint()..color = Colors.white);
      _drawDashedCircle(canvas, size, strokeWidth);
      return;
    }

    canvas.drawPath(path, Paint()..color = status.background);
    canvas.drawPath(
      path,
      Paint()
        ..color = status == MonitoringStatus.waspada
            ? AppColors.ink
            : Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeJoin = StrokeJoin.round,
    );
  }

  void _drawDashedCircle(Canvas canvas, Size size, double strokeWidth) {
    const dashes = 8;
    final sweep = math.pi * 2 / dashes;
    final rect = Rect.fromLTWH(
      strokeWidth / 2,
      strokeWidth / 2,
      size.width - strokeWidth,
      size.height - strokeWidth,
    );
    final paint = Paint()
      ..color = AppColors.stale
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    for (var i = 0; i < dashes; i++) {
      canvas.drawArc(rect, i * sweep, sweep * 0.6, false, paint);
    }
  }

  @override
  bool shouldRepaint(_StatusShapePainter oldDelegate) =>
      oldDelegate.status != status;
}

class SensorMarkerButton extends StatelessWidget {
  const SensorMarkerButton({
    super.key,
    required this.sensor,
    required this.onTap,
  });

  final SensorPoint sensor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _MarkerButton(
      semanticLabel: '${sensor.id}, ${sensor.status.label}. Buka detail.',
      label: sensor.id,
      onTap: onTap,
      icon: StatusShape(status: sensor.status, size: 28),
    );
  }
}

class _MarkerButton extends StatelessWidget {
  const _MarkerButton({
    required this.semanticLabel,
    required this.label,
    required this.onTap,
    required this.icon,
  });

  final String semanticLabel;
  final String label;
  final VoidCallback onTap;
  final Widget icon;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticLabel,
      excludeSemantics: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              icon,
              const SizedBox(height: 2),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.ink,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  label,
                  textScaler: TextScaler.noScaling,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
