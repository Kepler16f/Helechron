import 'package:flutter/cupertino.dart';

class SubtitleRow extends StatelessWidget {
  final String subtitle;
  final Widget? right;
  final double padHorizontal;
  final double padVertical;
  final double fontSize;

  const SubtitleRow({
    super.key,
    required this.subtitle,
    this.right,
    this.padHorizontal = 2,
    this.fontSize = 20,
    this.padVertical = 12,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: padHorizontal),
      child: Row(
        children: [
          Container(
            alignment: Alignment.centerLeft,
            padding: EdgeInsets.symmetric(vertical: padVertical),
            child: Text(
              subtitle,
              style: CupertinoTheme.of(
                context,
              ).textTheme.navLargeTitleTextStyle.copyWith(fontSize: fontSize),
            ),
          ),
          const Spacer(),
          right ?? const SizedBox(height: 0),
        ],
      ),
    );
  }
}

class SubSubtitleRow extends StatelessWidget {
  final String subtitle;
  final Widget? right;
  final double padHorizontal;

  const SubSubtitleRow({
    super.key,
    required this.subtitle,
    this.right,
    this.padHorizontal = 2,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: padHorizontal),
      child: Row(
        children: [
          Container(
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Text(
              subtitle,
              style: CupertinoTheme.of(
                context,
              ).textTheme.navLargeTitleTextStyle.copyWith(fontSize: 18),
            ),
          ),
          const Spacer(),
          right ?? const SizedBox(height: 0),
        ],
      ),
    );
  }
}
