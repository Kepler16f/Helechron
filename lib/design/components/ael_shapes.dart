import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_miuix/miuix.dart' show MiuixSquircleBorder;

/// Aelechron / Helechron 统一形状语言（HyperOS Squircle + M3 Expressive 起伏花瓣/波浪装饰）。
final class AelShapes {
  const AelShapes._();

  /// HyperOS 连续曲率超椭圆圆角边框。
  static ShapeBorder squircle(
    double radius, {
    BorderSide side = BorderSide.none,
  }) {
    return MiuixSquircleBorder(
      cornerRadius: radius,
      enabled: radius > 0,
      side: side,
    );
  }

  /// 参考图「VPN / 状态」图标用的连续起伏花瓣轮廓（Cookie / Scallop 形状）。
  static ShapeBorder cookie({int lobes = 8, double depthRatio = 0.085}) {
    return AelCookieShapeBorder(lobes: lobes, depthRatio: depthRatio);
  }
}

/// 连续正弦起伏花瓣形状（类似 Material 3 Expressive Scallop / Cookie 轮廓）。
class AelCookieShapeBorder extends OutlinedBorder {
  const AelCookieShapeBorder({
    this.lobes = 8,
    this.depthRatio = 0.085,
    super.side,
  });

  final int lobes;
  final double depthRatio;

  @override
  OutlinedBorder copyWith({BorderSide? side}) {
    return AelCookieShapeBorder(
      lobes: lobes,
      depthRatio: depthRatio,
      side: side ?? this.side,
    );
  }

  @override
  ShapeBorder scale(double t) {
    return AelCookieShapeBorder(
      lobes: lobes,
      depthRatio: depthRatio,
      side: side.scale(t),
    );
  }

  Path _buildPath(Rect rect) {
    final center = rect.center;
    final baseRadius = math.min(rect.width, rect.height) * 0.5;
    final amp = baseRadius * depthRatio;
    final midR = baseRadius - amp;
    const steps = 128;
    final path = Path();
    for (int i = 0; i <= steps; i++) {
      final theta = (i / steps) * math.pi * 2.0;
      final r = midR + amp * math.cos(lobes * theta);
      final x = center.dx + r * math.cos(theta);
      final y = center.dy + r * math.sin(theta);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();
    return path;
  }

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) {
    return _buildPath(rect.deflate(side.strokeInset));
  }

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) {
    return _buildPath(rect);
  }

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    if (side.style == BorderStyle.none) return;
    canvas.drawPath(getOuterPath(rect), side.toPaint());
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is AelCookieShapeBorder &&
        other.lobes == lobes &&
        other.depthRatio == depthRatio &&
        other.side == side;
  }

  @override
  int get hashCode => Object.hash(lobes, depthRatio, side);
}

/// 参考图顶部主状态卡片右侧的柔和波浪边缘装饰绘制器。
class AelWavyEdgePainter extends CustomPainter {
  const AelWavyEdgePainter({
    required this.color,
    this.waves = 4,
    this.amplitude = 10,
    this.widthFraction = 0.34,
  });

  final Color color;
  final int waves;
  final double amplitude;
  final double widthFraction;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final baseWidth = size.width * widthFraction;
    final startX = size.width - baseWidth;
    final path = Path()..moveTo(size.width, 0);
    path.lineTo(startX, 0);

    const steps = 64;
    for (int i = 0; i <= steps; i++) {
      final t = i / steps;
      final y = t * size.height;
      final x = startX + math.sin(t * math.pi * 2 * waves) * amplitude;
      path.lineTo(x, y);
    }

    path
      ..lineTo(size.width, size.height)
      ..close();

    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.fill,
    );
  }

  @override
  bool shouldRepaint(covariant AelWavyEdgePainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.waves != waves ||
        oldDelegate.amplitude != amplitude ||
        oldDelegate.widthFraction != widthFraction;
  }
}
