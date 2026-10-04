/// 并发闸门：限制同时在跑的任务数。
///
/// 为什么单独抽出来：v1.0.9 的装载限流用「`while` + `Future.delayed` 轮询」实现，
/// 而等待的任务又卡在一个可能永不返回的调用上时，**名额永远不释放** ——
/// 表现是首页所有分区一直转圈、既没结果也没错误。这类 bug 必须有单测盯着。
///
/// 本实现的要点：**名额直接交接给队首**（`release()` 时若有人在等，就不减计数、
/// 直接唤醒队首），既不轮询也不会丢名额。
library;

import 'dart:async';

class BootGate {
  BootGate(this.maxConcurrent) : assert(maxConcurrent > 0);

  final int maxConcurrent;

  int _active = 0;
  final List<Completer<void>> _waiters = <Completer<void>>[];

  int get active => _active;
  int get waiting => _waiters.length;

  /// 取一个名额；满了就排队等（返回的 Future 完成即表示拿到名额）。
  Future<void> acquire() {
    if (_active < maxConcurrent) {
      _active++;
      return Future<void>.value();
    }
    final waiter = Completer<void>();
    _waiters.add(waiter);
    return waiter.future;
  }

  /// 归还名额：有人在等就**直接把名额交给队首**（在跑总数不变），否则计数减一。
  void release() {
    if (_waiters.isNotEmpty) {
      _waiters.removeAt(0).complete();
      return;
    }
    if (_active > 0) _active--;
  }
}
