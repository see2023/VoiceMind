import 'package:flutter/material.dart';

class StanceColors {
  static final List<Color> baseColors = [
    Colors.blue[300]!,
    Colors.red[300]!,
    Colors.green[300]!,
    Colors.orange[300]!,
    Colors.purple[300]!,
    Colors.teal[300]!,
  ];

  // 获取派别基础颜色（更淡的颜色）
  static Color getStanceColor(int stanceId) {
    final baseColor = baseColors[stanceId % baseColors.length];
    return baseColor.withAlpha(40); // 使用很淡的颜色作为派别底色
  }

  // 获取成员的变体颜色（在派别颜色基础上稍微变化）
  static Color getMemberBackgroundColor(int stanceId, int userId) {
    final baseColor = baseColors[stanceId % baseColors.length];
    // 使用用户ID来生成细微的亮度变化
    const baseAlpha = 40; // 基础透明度
    final alphaOffset = (userId % 5 - 1) * 50;
    return baseColor.withAlpha((baseAlpha + alphaOffset).clamp(20, 80));
  }

  // 获取文字颜色（保持高对比度）
  static Color getTextColor(Color backgroundColor) {
    return backgroundColor.computeLuminance() > 0.23
        ? Colors.black87
        : Colors.white;
  }
}
