import 'dart:math';
import 'package:flutter/cupertino.dart';
import 'package:celechron/design/custom_colors.dart';
import 'package:celechron/design/round_rectangle_card.dart';
import 'package:celechron/model/semester.dart';

/// 成绩走势模式：五分制 / 四分制
enum GpaTrendScale {
  fivePoint,
  fourPoint,
}

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

  String _formatSemesterName(String name) {
    // 例如 "2023-2024学年秋冬" -> "23秋冬"
    final match = RegExp(r'(\d{2})\d{2}-\d{2}(\d{2})学年(.*)').firstMatch(name);
    if (match != null) {
      final endYear = match.group(2) ?? '';
      final season = match.group(3) ?? '';
      return '$endYear$season';
    }
    if (name.length >= 8) {
      return '${name.substring(2, 4)}${name.substring(7)}';
    }
    return name;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.semesters.isEmpty) {
      return const SizedBox.shrink();
    }

    final isFivePoint = _scale == GpaTrendScale.fivePoint;
    final isDark = CupertinoTheme.brightnessOf(context) == Brightness.dark;

    // 寻找最高 GPA 学期
    int peakIndex = 0;
    double maxGpa = -1.0;
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

    return RoundRectangleCard(
      child: Padding(
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
                    color: CupertinoDynamicColor.resolve(
                        CustomCupertinoDynamicColors.sakura, context),
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: const Icon(
                    CupertinoIcons.graph_circle_fill,
                    size: 18,
                    color: CupertinoColors.white,
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
                          color: CupertinoDynamicColor.resolve(
                              CupertinoColors.label, context),
                        ),
                      ),
                      Text(
                        '峰值学期：$peakName (${maxGpa.toStringAsFixed(2)}) · 累计 ${totalCredits.toStringAsFixed(1)} 学分',
                        style: TextStyle(
                          fontSize: 11,
                          color: CupertinoDynamicColor.resolve(
                              CupertinoColors.secondaryLabel, context),
                        ),
                      ),
                    ],
                  ),
                ),
                // 五分制/四分制滑动切换器
                CupertinoSlidingSegmentedControl<GpaTrendScale>(
                  groupValue: _scale,
                  children: const {
                    GpaTrendScale.fivePoint: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      child: Text('5分制', style: TextStyle(fontSize: 11)),
                    ),
                    GpaTrendScale.fourPoint: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      child: Text('4分制', style: TextStyle(fontSize: 11)),
                    ),
                  },
                  onValueChanged: (val) {
                    if (val != null) {
                      setState(() => _scale = val);
                    }
                  },
                ),
              ],
            ),
            const SizedBox(height: 14),

            // 折线图绘制区域
            SizedBox(
              height: 150,
              width: double.infinity,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return GestureDetector(
                    onTapUp: (details) {
                      final width = constraints.maxWidth;
                      final count = widget.semesters.length;
                      if (count <= 0) return;
                      const padding = 28.0;
                      final usableWidth = width - padding * 2;
                      final stepX = count > 1 ? usableWidth / (count - 1) : 0.0;
                      final tapX = details.localPosition.dx;

                      // 计算最近的学期索引
                      int nearestIndex = 0;
                      double minDistance = double.infinity;
                      for (int i = 0; i < count; i++) {
                        final pointX =
                            count > 1 ? padding + i * stepX : width / 2;
                        final dist = (tapX - pointX).abs();
                        if (dist < minDistance) {
                          minDistance = dist;
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
                        isDark: isDark,
                        lineColor: isDark
                            ? const Color(0xFFFF69B4)
                            : const Color(0xFFE91E63),
                        selectedColor: CupertinoDynamicColor.resolve(
                            CustomCupertinoDynamicColors.cyan, context),
                        textColor: CupertinoDynamicColor.resolve(
                            CupertinoColors.secondaryLabel, context),
                        labelColor: CupertinoDynamicColor.resolve(
                            CupertinoColors.label, context),
                        gridColor: isDark
                            ? CupertinoColors.white.withValues(alpha: 0.1)
                            : CupertinoColors.black.withValues(alpha: 0.06),
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
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? CupertinoDynamicColor.resolve(
                                CustomCupertinoDynamicColors.cyan, context)
                            : CupertinoDynamicColor.resolve(
                                CupertinoColors.tertiarySystemFill, context),
                        borderRadius: BorderRadius.circular(8),
                        border: isSelected
                            ? Border.all(
                                color: CupertinoDynamicColor.resolve(
                                    CustomCupertinoDynamicColors.cyan, context),
                                width: 1.5,
                              )
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
                              color: CupertinoDynamicColor.resolve(
                                  CupertinoColors.label, context),
                            ),
                          ),
                          Text(
                            '${gpaVal.toStringAsFixed(2)} / ${s.credits.toStringAsFixed(1)}学分',
                            style: TextStyle(
                              fontSize: 10,
                              color: CupertinoDynamicColor.resolve(
                                  CupertinoColors.secondaryLabel, context),
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
      ),
    );
  }
}

/// 绘制绩点曲线、平滑渐变面积、基准线与数据节点的 CustomPainter
class _GpaTrendChartPainter extends CustomPainter {
  final List<Semester> semesters;
  final int selectedIndex;
  final GpaTrendScale scale;
  final bool isDark;
  final Color lineColor;
  final Color selectedColor;
  final Color textColor;
  final Color labelColor;
  final Color gridColor;

  _GpaTrendChartPainter({
    required this.semesters,
    required this.selectedIndex,
    required this.scale,
    required this.isDark,
    required this.lineColor,
    required this.selectedColor,
    required this.textColor,
    required this.labelColor,
    required this.gridColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (semesters.isEmpty) return;

    final isFivePoint = scale == GpaTrendScale.fivePoint;
    final maxScale = isFivePoint ? 5.0 : 4.0;
    final minScale = isFivePoint ? 2.5 : 1.5;

    const paddingLeft = 28.0;
    const paddingRight = 28.0;
    const paddingTop = 24.0;
    const paddingBottom = 26.0;

    final chartWidth = size.width - paddingLeft - paddingRight;
    final chartHeight = size.height - paddingTop - paddingBottom;

    // 1. 绘制水平参考刻度线（4 条刻度线）
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1.0;

    const gridSteps = 3;
    for (int i = 0; i <= gridSteps; i++) {
      final ratio = i / gridSteps;
      final y = paddingTop + chartHeight * (1.0 - ratio);
      final value = minScale + (maxScale - minScale) * ratio;

      canvas.drawLine(
        Offset(paddingLeft - 8, y),
        Offset(size.width - paddingRight + 8, y),
        gridPaint,
      );

      // 左侧刻度文本
      final textSpan = TextSpan(
        text: value.toStringAsFixed(1),
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
        Offset(
            paddingLeft - 12 - textPainter.width, y - textPainter.height / 2),
      );
    }

    // 2. 计算各学期数据点的坐标
    final count = semesters.length;
    final points = <Offset>[];
    final stepX = count > 1 ? chartWidth / (count - 1) : 0.0;

    for (int i = 0; i < count; i++) {
      final s = semesters[i];
      final gpa = (isFivePoint ? s.gpa[0] : s.gpa[1]).clamp(minScale, maxScale);
      final ratioY = (gpa - minScale) / (maxScale - minScale);
      final x = count > 1 ? paddingLeft + i * stepX : size.width / 2;
      final y = paddingTop + chartHeight * (1.0 - ratioY);
      points.add(Offset(x, y));
    }

    // 3. 绘制平滑曲线与阴影渐变面积
    if (points.isNotEmpty) {
      final path = Path();
      path.moveTo(points.first.dx, points.first.dy);

      for (int i = 0; i < points.length - 1; i++) {
        final p0 = points[i];
        final p1 = points[i + 1];
        final controlX1 = p0.dx + (p1.dx - p0.dx) / 2;
        final controlY1 = p0.dy;
        final controlX2 = p0.dx + (p1.dx - p0.dx) / 2;
        final controlY2 = p1.dy;
        path.cubicTo(controlX1, controlY1, controlX2, controlY2, p1.dx, p1.dy);
      }

      // 面积阴影
      final fillPath = Path.from(path)
        ..lineTo(points.last.dx, paddingTop + chartHeight)
        ..lineTo(points.first.dx, paddingTop + chartHeight)
        ..close();

      final fillPaint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            lineColor.withValues(alpha: isDark ? 0.35 : 0.22),
            lineColor.withValues(alpha: 0.0),
          ],
        ).createShader(Rect.fromLTWH(
          paddingLeft,
          paddingTop,
          chartWidth,
          chartHeight,
        ))
        ..style = PaintingStyle.fill;

      canvas.drawPath(fillPath, fillPaint);

      // 主折线
      final linePaint = Paint()
        ..color = lineColor
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;

      canvas.drawPath(path, linePaint);
    }

    // 4. 绘制数据节点圆圈与数值标签
    for (int i = 0; i < points.length; i++) {
      final pt = points[i];
      final isSelected = selectedIndex == i;
      final s = semesters[i];
      final val = isFivePoint ? s.gpa[0] : s.gpa[1];

      // 选中的外圈高亮光晕
      if (isSelected) {
        final haloPaint = Paint()
          ..color = selectedColor.withValues(alpha: 0.3)
          ..style = PaintingStyle.fill;
        canvas.drawCircle(pt, 10.0, haloPaint);

        final ringPaint = Paint()
          ..color = selectedColor
          ..strokeWidth = 2.0
          ..style = PaintingStyle.stroke;
        canvas.drawCircle(pt, 7.0, ringPaint);
      }

      // 实体圆点
      final dotPaint = Paint()
        ..color = isSelected ? selectedColor : lineColor
        ..style = PaintingStyle.fill;
      canvas.drawCircle(pt, isSelected ? 4.5 : 3.5, dotPaint);

      final innerPaint = Paint()
        ..color = CupertinoColors.white
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

      // 避免文字顶出 paddingTop
      final textY = max(2.0, pt.dy - valPainter.height - 4);
      valPainter.paint(
        canvas,
        Offset(pt.dx - valPainter.width / 2, textY),
      );

      // 节点下方的学期简写标签 (例如 "23秋冬")
      final nameSpan = TextSpan(
        text: _formatShortName(s.name),
        style: TextStyle(
          color: isSelected ? labelColor : textColor,
          fontSize: 9.5,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        ),
      );
      final namePainter = TextPainter(
        text: nameSpan,
        textDirection: TextDirection.ltr,
      )..layout();

      namePainter.paint(
        canvas,
        Offset(pt.dx - namePainter.width / 2, paddingTop + chartHeight + 6),
      );
    }
  }

  String _formatShortName(String name) {
    final match = RegExp(r'(\d{2})\d{2}-\d{2}(\d{2})学年(.*)').firstMatch(name);
    if (match != null) {
      final endYear = match.group(2) ?? '';
      final season = match.group(3) ?? '';
      return '$endYear$season';
    }
    if (name.length >= 8) {
      return '${name.substring(2, 4)}${name.substring(7)}';
    }
    return name;
  }

  @override
  bool shouldRepaint(covariant _GpaTrendChartPainter oldDelegate) {
    return oldDelegate.selectedIndex != selectedIndex ||
        oldDelegate.scale != scale ||
        oldDelegate.isDark != isDark ||
        oldDelegate.semesters != semesters;
  }
}
