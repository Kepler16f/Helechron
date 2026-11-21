import 'package:flutter/widgets.dart';

import 'package:celechron/design/components/ael_components.dart';
import 'package:celechron/design/icons/ael_icons.dart';
import 'package:celechron/design/theme/ael_theme.dart';
import 'package:celechron/design/tokens/ael_tokens.dart';
import 'package:celechron/model/semester.dart';

/// 成绩走势模式：五分制 / 四分制
enum GpaTrendScale { fivePoint, fourPoint }

/// 学期 GPA 与学分历年走势折线图卡片
class SemesterGpaTrendCard extends StatefulWidget {
  final List<Semester> semesters;
  final int selectedIndex;
  final ValueChanged<int>? onSemesterSelected;

  const SemesterGpaTrendCard({
    super.key,
    required this.semesters,
    required this.selectedIndex,
    this.onSemesterSelected,
  });

  @override
  State<SemesterGpaTrendCard> createState() => _SemesterGpaTrendCardState();
}

class _SemesterGpaTrendCardState extends State<SemesterGpaTrendCard> {
  GpaTrendScale _scale = GpaTrendScale.fivePoint;

  String _formatSemesterName(String raw) {
    if (raw.length >= 11) {
      final yearShort = '${raw.substring(2, 4)}-${raw.substring(7, 9)}';
      final term = raw.substring(9).trim();
      return '$yearShort $term';
    }
    return raw;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.semesters.isEmpty) return const SizedBox.shrink();

    final colors = AelTheme.colorsOf(context);
    final isFivePoint = _scale == GpaTrendScale.fivePoint;

    double maxGpa = 0.0;
    int peakIndex = 0;
    double totalCredits = 0.0;
    for (int i = 0; i < widget.semesters.length; i++) {
      final s = widget.semesters[i];
      final val = isFivePoint ? s.gpa[0] : s.gpa[1];
      if (val > maxGpa) {
        maxGpa = val;
        peakIndex = i;
      }
      totalCredits += s.credits;
    }

    final peakSemester = widget.semesters[peakIndex];
    final peakName = _formatSemesterName(peakSemester.name);

    return AelSectionCard(
      cornerRadius: AelRadius.tile,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 顶部标题与切换模式栏
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: colors.primaryContainer,
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Icon(
                  AelIcons.activity,
                  size: 16,
                  color: colors.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '学期绩点与学分走势',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: colors.textPrimary,
                      ),
                    ),
                    Text(
                      '峰值学期：$peakName (${maxGpa.toStringAsFixed(2)}) · 累计 ${totalCredits.toStringAsFixed(1)} 学分',
                      style: TextStyle(
                        fontSize: 11,
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              // 五分制 / 四分制滑动切换器
              SizedBox(
                width: 140,
                child: AelSegmented<GpaTrendScale>(
                  value: _scale,
                  stackedIcon: false,
                  gap: 4,
                  onChanged: (val) => setState(() => _scale = val),
                  items: const [
                    AelSegmentItem(
                      value: GpaTrendScale.fivePoint,
                      label: '5分制',
                    ),
                    AelSegmentItem(
                      value: GpaTrendScale.fourPoint,
                      label: '4分制',
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // 折线图绘图区
          SizedBox(
            height: 150,
            child: LayoutBuilder(
              builder: (context, constraints) {
                return GestureDetector(
                  onTapDown: (details) {
                    final boxWidth = constraints.maxWidth;
                    final n = widget.semesters.length;
                    if (n <= 1) return;
                    const padLeft = 32.0;
                    const padRight = 16.0;
                    final chartWidth = boxWidth - padLeft - padRight;
                    final stepX = chartWidth / (n - 1);

                    final tapX = details.localPosition.dx;
                    int nearestIndex = 0;
                    double minDiff = double.infinity;
                    for (int i = 0; i < n; i++) {
                      final ptX = padLeft + i * stepX;
                      final diff = (tapX - ptX).abs();
                      if (diff < minDiff) {
                        minDiff = diff;
                        nearestIndex = i;
                      }
                    }
                    widget.onSemesterSelected?.call(nearestIndex);
                  },
                  child: CustomPaint(
                    size: Size(constraints.maxWidth, 150),
                    painter: _GpaTrendChartPainter(
                      semesters: widget.semesters,
                      selectedIndex: widget.selectedIndex,
                      scale: _scale,
                      lineColor: colors.primary,
                      selectedColor: colors.primary,
                      textColor: colors.textSecondary,
                      labelColor: colors.textPrimary,
                      gridColor: colors.divider,
                      cardBg: colors.cardBg,
                    ),
                  ),
                );
              },
            ),
          ),

          const SizedBox(height: 8),

          // 底部横向学期胶囊列表（联动点击与学分显示）
          SizedBox(
            height: 48,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: widget.semesters.length,
              separatorBuilder: (_, __) => const SizedBox(width: 6),
              itemBuilder: (context, index) {
                final s = widget.semesters[index];
                final isSelected = widget.selectedIndex == index;
                final gpaVal = isFivePoint ? s.gpa[0] : s.gpa[1];

                return GestureDetector(
                  onTap: () => widget.onSemesterSelected?.call(index),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? colors.primaryContainer
                          : colors.tonalTileBg,
                      borderRadius: BorderRadius.circular(8),
                      border: isSelected
                          ? Border.all(color: colors.primary, width: 1.5)
                          : null,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          _formatSemesterName(s.name),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: isSelected
                                ? FontWeight.bold
                                : FontWeight.w500,
                            color: isSelected
                                ? colors.onPrimaryContainer
                                : colors.textPrimary,
                          ),
                        ),
                        Text(
                          '${gpaVal.toStringAsFixed(2)} / ${s.credits.toStringAsFixed(1)}学分',
                          style: TextStyle(
                            fontSize: 10,
                            color: isSelected
                                ? colors.onPrimaryContainer.withValues(
                                    alpha: 0.8,
                                  )
                                : colors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// 折线图自定义画笔
class _GpaTrendChartPainter extends CustomPainter {
  final List<Semester> semesters;
  final int selectedIndex;
  final GpaTrendScale scale;
  final Color lineColor;
  final Color selectedColor;
  final Color textColor;
  final Color labelColor;
  final Color gridColor;
  final Color cardBg;

  _GpaTrendChartPainter({
    required this.semesters,
    required this.selectedIndex,
    required this.scale,
    required this.lineColor,
    required this.selectedColor,
    required this.textColor,
    required this.labelColor,
    required this.gridColor,
    required this.cardBg,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (semesters.isEmpty) return;

    final isFivePoint = scale == GpaTrendScale.fivePoint;
    final maxGpaScale = isFivePoint ? 5.0 : 4.0;
    final minGpaScale = isFivePoint ? 1.5 : 1.0;

    const padLeft = 32.0;
    const padRight = 16.0;
    const padTop = 18.0;
    const padBottom = 22.0;

    final chartWidth = size.width - padLeft - padRight;
    final chartHeight = size.height - padTop - padBottom;

    // 绘制横向网格参考线 (分档: 5.0, 4.0, 3.0, 2.0 等)
    final gridSteps = isFivePoint ? [2.0, 3.0, 4.0, 5.0] : [2.0, 3.0, 4.0];
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 0.8
      ..style = PaintingStyle.stroke;

    for (final step in gridSteps) {
      final y =
          padTop +
          chartHeight *
              (1.0 - (step - minGpaScale) / (maxGpaScale - minGpaScale));
      canvas.drawLine(
        Offset(padLeft, y),
        Offset(size.width - padRight, y),
        gridPaint,
      );

      // 绘制纵坐标标尺数值
      final textSpan = TextSpan(
        text: step.toStringAsFixed(1),
        style: TextStyle(
          color: textColor,
          fontSize: 9,
          fontWeight: FontWeight.w400,
        ),
      );
      final textPainter = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
      )..layout();
      textPainter.paint(
        canvas,
        Offset(padLeft - textPainter.width - 4, y - textPainter.height / 2),
      );
    }

    // 计算各学期数据点的坐标 (x, y)
    final n = semesters.length;
    final stepX = n > 1 ? chartWidth / (n - 1) : 0.0;
    final points = <Offset>[];

    for (int i = 0; i < n; i++) {
      final s = semesters[i];
      final val = (isFivePoint ? s.gpa[0] : s.gpa[1]).clamp(
        minGpaScale,
        maxGpaScale,
      );
      final x = n > 1 ? padLeft + i * stepX : padLeft + chartWidth / 2;
      final y =
          padTop +
          chartHeight *
              (1.0 - (val - minGpaScale) / (maxGpaScale - minGpaScale));
      points.add(Offset(x, y));
    }

    if (points.isEmpty) return;

    // 绘制渐变填充区域
    final path = Path();
    path.moveTo(points.first.dx, size.height - padBottom);
    path.lineTo(points.first.dx, points.first.dy);

    for (int i = 0; i < points.length - 1; i++) {
      final p0 = points[i];
      final p1 = points[i + 1];
      final cx = (p0.dx + p1.dx) / 2;
      path.cubicTo(cx, p0.dy, cx, p1.dy, p1.dx, p1.dy);
    }

    path.lineTo(points.last.dx, size.height - padBottom);
    path.close();

    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          lineColor.withValues(alpha: 0.28),
          lineColor.withValues(alpha: 0.02),
        ],
      ).createShader(Rect.fromLTWH(0, padTop, size.width, chartHeight))
      ..style = PaintingStyle.fill;
    canvas.drawPath(path, fillPaint);

    // 绘制平滑贝塞尔折线
    final strokePath = Path()..moveTo(points.first.dx, points.first.dy);
    for (int i = 0; i < points.length - 1; i++) {
      final p0 = points[i];
      final p1 = points[i + 1];
      final cx = (p0.dx + p1.dx) / 2;
      strokePath.cubicTo(cx, p0.dy, cx, p1.dy, p1.dx, p1.dy);
    }

    final strokePaint = Paint()
      ..color = lineColor
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    canvas.drawPath(strokePath, strokePaint);

    // 绘制每个学期的数据点与高亮选中学期
    for (int i = 0; i < points.length; i++) {
      final pt = points[i];
      final isSelected = selectedIndex == i;
      final val = isFivePoint ? semesters[i].gpa[0] : semesters[i].gpa[1];

      // 选中学期绘制垂直虚线引导线
      if (isSelected) {
        final guidePaint = Paint()
          ..color = selectedColor.withValues(alpha: 0.3)
          ..strokeWidth = 1.2
          ..style = PaintingStyle.stroke;
        canvas.drawLine(
          Offset(pt.dx, padTop),
          Offset(pt.dx, size.height - padBottom),
          guidePaint,
        );

        // 选中外圈光环
        final glowPaint = Paint()
          ..color = selectedColor.withValues(alpha: 0.25)
          ..style = PaintingStyle.fill;
        canvas.drawCircle(pt, 8.0, glowPaint);
      }

      // 实体圆点
      final dotPaint = Paint()
        ..color = isSelected ? selectedColor : lineColor
        ..style = PaintingStyle.fill;
      canvas.drawCircle(pt, isSelected ? 4.5 : 3.5, dotPaint);

      final innerPaint = Paint()
        ..color = cardBg
        ..style = PaintingStyle.fill;
      canvas.drawCircle(pt, isSelected ? 2.0 : 1.5, innerPaint);

      // 节点上方的绩点数字文本 (例如 "4.35")
      final valSpan = TextSpan(
        text: val.toStringAsFixed(2),
        style: TextStyle(
          color: isSelected ? labelColor : textColor,
          fontSize: isSelected ? 11 : 9.5,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
        ),
      );
      final valPainter = TextPainter(
        text: valSpan,
        textDirection: TextDirection.ltr,
      )..layout();
      valPainter.paint(
        canvas,
        Offset(pt.dx - valPainter.width / 2, pt.dy - valPainter.height - 4),
      );

      // 底部学期简写标签 (例如 "22秋", "23春")
      final semName = semesters[i].name;
      String shortName = semName;
      if (semName.length >= 11) {
        shortName = '${semName.substring(2, 4)}${semName.substring(9).trim()}';
      }
      final bottomSpan = TextSpan(
        text: shortName,
        style: TextStyle(
          color: isSelected ? labelColor : textColor,
          fontSize: 9.5,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        ),
      );
      final bottomPainter = TextPainter(
        text: bottomSpan,
        textDirection: TextDirection.ltr,
      )..layout();
      bottomPainter.paint(
        canvas,
        Offset(pt.dx - bottomPainter.width / 2, size.height - padBottom + 4),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _GpaTrendChartPainter oldDelegate) {
    return oldDelegate.selectedIndex != selectedIndex ||
        oldDelegate.scale != scale ||
        oldDelegate.lineColor != lineColor ||
        oldDelegate.selectedColor != selectedColor ||
        oldDelegate.cardBg != cardBg ||
        oldDelegate.semesters != semesters;
  }
}
