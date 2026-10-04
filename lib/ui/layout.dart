/// 屏幕自适应的度量与断点（纯函数，便于单测）。
///
/// 目标：
///   * 窄屏/竖屏用底部导航栏；宽屏/横屏/平板改成左侧导航栏（不浪费竖向空间）。
///   * 首页海报行的高度随可用高度收缩 —— 横屏时若还固定 208，会占掉大半个屏幕。
library;

import 'dart:ui' show Size;

/// 宽度达到它就从「底部导航栏」切到「左侧导航栏」。
const double kRailBreakpoint = 600;

/// 超宽屏（平板横屏）时给内容加一个最大宽度，避免海报被拉得巨大。
const double kContentMaxWidth = 1100;

/// 是否用左侧导航栏（横屏 / 平板 / 桌面）。
bool useNavigationRail(double width) => width >= kRailBreakpoint;

/// 手机横屏时底部导航栏会挤掉视频区，也跟着切 rail。
bool isLandscape(Size size) => size.width > size.height;

/// 一行海报的高度：按可用高度自适应，并夹在合理区间。
double posterRowHeight(double availableHeight) =>
    (availableHeight * 0.34).clamp(150.0, 210.0);

/// 海报卡宽度：按「2:3 海报 + 6 间距 + 两行标题」从行高反推。
double posterCardWidth(double rowHeight) => ((rowHeight - 28) / 1.5).clamp(88.0, 140.0);

/// 网格里单张海报的期望宽度（大屏给大一点，别密密麻麻）。
double posterGridExtent(double width) => width >= 900 ? 168 : 140;
