/// 分页相关回归测试。
///
/// 背景（真机 bug）：`_ModuleList` 建了 `ScrollController` 并 `addListener`，
/// 但 `PosterGrid` 当时**没有 controller 参数**，控制器从未挂到内部滚动组件上，
/// 「滚到底加载下一页」的监听永远不触发 —— 现象是「每个组件只有 1 页、
/// 下滑不加载后续资源」。这里用真实 widget 断言控制器确实被挂上了。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:splayer_mobile/models/capy_models.dart';
import 'package:splayer_mobile/models/paging.dart';
import 'package:splayer_mobile/ui/common.dart';

MediaItem _item(String id) => MediaItem(id: id, title: 'item-$id');

void main() {
  group('mergePage 分页合并', () {
    test('无重叠时整页追加', () {
      final r = mergePage(<MediaItem>[_item('1')], <MediaItem>[_item('2'), _item('3')], (e) => e.id);
      expect(r.added, 2);
      expect(r.items.map((e) => e.id), <String>['1', '2', '3']);
    });

    test('重复页（后端忽略 page）added 为 0 —— 触发「到底」判断', () {
      final current = <MediaItem>[_item('1'), _item('2')];
      final r = mergePage(current, <MediaItem>[_item('1'), _item('2')], (e) => e.id);
      expect(r.added, 0);
      expect(r.items.length, 2);
    });

    test('部分重叠只算新增', () {
      final r = mergePage(<MediaItem>[_item('1'), _item('2')], <MediaItem>[_item('2'), _item('3')], (e) => e.id);
      expect(r.added, 1);
      expect(r.items.map((e) => e.id), <String>['1', '2', '3']);
    });

    test('空页不改变列表', () {
      final current = <MediaItem>[_item('1')];
      final r = mergePage(current, const <MediaItem>[], (e) => e.id);
      expect(r.added, 0);
      expect(r.items, same(current));
    });
  });

  testWidgets('PosterGrid 把 controller 挂到内部滚动组件（防「漏接控制器」回归）', (WidgetTester tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    final items = List<MediaItem>.generate(60, (i) => _item('$i'));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PosterGrid(
            controller: controller,
            items: items,
            onTapItem: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(controller.hasClients, isTrue, reason: '控制器必须挂到可滚动组件上，否则分页监听永不触发');
    expect(controller.position.maxScrollExtent, greaterThan(0));

    // 滚到底部应能触发监听（模拟「下滑加载后续资源」）。
    var fired = false;
    controller.addListener(() => fired = true);
    controller.jumpTo(controller.position.maxScrollExtent);
    await tester.pump();
    expect(fired, isTrue);
  });

  testWidgets('PosterGrid 未传 controller 时也能正常渲染', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PosterGrid(items: <MediaItem>[_item('1')], onTapItem: (_) {}),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
