/// 并发闸门测试 —— 直接盯住 v1.0.9 导致首页全部卡死的那个 bug。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:splayer_mobile/runtime/boot_gate.dart';

/// 让微任务队列跑完。
Future<void> flush() => Future<void>.delayed(Duration.zero);

void main() {
  test('并发不超过上限，超出的排队等待', () async {
    final gate = BootGate(2);
    final started = <int>[];
    final futures = <Future<void>>[];

    for (var i = 0; i < 5; i++) {
      futures.add(gate.acquire().then((_) => started.add(i)));
    }
    await flush();

    expect(started, <int>[0, 1]);
    expect(gate.active, 2);
    expect(gate.waiting, 3);
    expect(gate.active + gate.waiting, 5);
  });

  test('release 把名额直接交接给队首（不丢名额、不超上限）', () async {
    final gate = BootGate(2);
    final started = <int>[];
    final futures = <Future<void>>[];
    for (var i = 0; i < 5; i++) {
      futures.add(gate.acquire().then((_) => started.add(i)));
    }
    await flush();

    for (var released = 0; released < 5; released++) {
      gate.release();
      await flush();
      // 任何时刻在跑的都不能超过上限
      expect(gate.active, lessThanOrEqualTo(2));
    }

    expect(started, <int>[0, 1, 2, 3, 4], reason: '每个排队者最终都要拿到名额');
    expect(gate.active, 0);
    expect(gate.waiting, 0);
    await Future.wait(futures);
  });

  test('空闲时释放不会把计数压成负数', () async {
    final gate = BootGate(1);
    gate.release();
    gate.release();
    expect(gate.active, 0);

    // 之后仍能正常取名额
    await gate.acquire();
    expect(gate.active, 1);
  });

  test('全部释放后新任务可以立刻执行（名额没有泄漏）', () async {
    final gate = BootGate(1);
    final futures = <Future<void>>[];
    for (var i = 0; i < 4; i++) {
      futures.add(gate.acquire());
    }
    await flush();
    for (var i = 0; i < 4; i++) {
      gate.release();
      await flush();
    }
    await Future.wait(futures);
    expect(gate.active, 0);
    expect(gate.waiting, 0);

    // 队列清空后再来一个：应立刻拿到
    var acquired = false;
    await gate.acquire().then((_) => acquired = true);
    expect(acquired, isTrue);
    expect(gate.active, 1);
  });
}
