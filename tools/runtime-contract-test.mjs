/// 桥接层契约测试：把真实运行时（assets/runtime/capy_runtime.js）装进 Node 沙箱，
/// 用 Dart 侧生成的同一种表达式去调用，验证「组件实际收到了什么」。
///
/// 用法: node tools/runtime-contract-test.mjs
/// 这一步挡的是真机上那一类事故：
///   URL 非法：组件传入的是 null —— 参数编码少了一层，JSON.parse 抛错 → 组件收到 null。
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const runtimeSource = fs.readFileSync(path.join(root, 'assets/runtime/capy_runtime.js'), 'utf8');

const failures = [];
function check(name, condition, detail = '') {
  if (condition) {
    console.log(`  ✓ ${name}`);
  } else {
    console.log(`  ✘ ${name}${detail ? `  → ${detail}` : ''}`);
    failures.push(name);
  }
}

/// 与 Dart 侧 buildInvokeExpression 完全一致的组装方式：
/// 三个实参都是 JS 字符串字面量（第三个承载 JSON 文本）。
function buildExpression(entry, callbackId, functionName, argumentJson) {
  return `${entry}(${JSON.stringify(callbackId)}, ${JSON.stringify(functionName)}, ${JSON.stringify(argumentJson)});`;
}

/// 造一个最小浏览器环境 + 收桥消息
function createSandbox(sent) {
  const sandbox = {
    console: { log: () => {}, warn: () => {}, error: () => {} },
    JSON, Promise, Object, Array, String, Number, Boolean, RegExp, Error, TypeError,
    Date, Math, parseInt, parseFloat, isNaN, isFinite,
    encodeURIComponent, decodeURIComponent,
    setTimeout, clearTimeout, setInterval, clearInterval,
    document: { implementation: { createHTMLDocument: () => ({ open() {}, write() {}, close() {}, documentElement: {}, body: {} }) } },
    DOMParser: class { parseFromString() { return {}; } },
    localStorage: { getItem: () => null, setItem: () => {}, removeItem: () => {} },
    CapyBridge: { postMessage: (text) => sent.push(JSON.parse(text)) },
    fetch: () => Promise.reject(new Error('no network in test')),
  };
  sandbox.window = sandbox;
  sandbox.globalThis = sandbox;
  return sandbox;
}

async function withRuntime(fn) {
  const sent = [];
  const sandbox = createSandbox(sent);
  vm.createContext(sandbox);
  vm.runInContext(runtimeSource, sandbox, { filename: 'capy_runtime.js' });
  sandbox.jQuery = null; // Widget.html 在测试里用不到
  return fn(sandbox, sent);
}

console.log('== 1. 模块调用：params 必须是对象 ==');
await withRuntime(async (sandbox, sent) => {
  let received = null;
  sandbox.getProviderHome = (params) => {
    received = params;
    return [{ id: '1', title: 'ok' }];
  };
  const params = { page: 1, serverUrl: 'https://happy-capy.garland.indevs.in' };
  // eslint-disable-next-line no-eval
  vm.runInContext(
    buildExpression('__capyInvoke', 'c1', 'getProviderHome', JSON.stringify(params)),
    sandbox,
  );
  await new Promise((r) => setTimeout(r, 20));
  check('组件拿到的是对象（不是 null / 不是字符串）', received !== null && typeof received === 'object',
    `收到 ${JSON.stringify(received)}`);
  check('参数内容完整（page / serverUrl 都在）',
    received && received.page === 1 && received.serverUrl === params.serverUrl,
    `收到 ${JSON.stringify(received)}`);
  const result = sent.find((m) => m.type === 'result');
  check('结果回传 ok', !!result && JSON.parse(result.payload).ok === true);
});

console.log('== 1b. 旧写法（只编码一层）会坏掉，用于确认这次修的是真问题 ==');
await withRuntime(async (sandbox) => {
  let received = 'NOT_CALLED';
  sandbox.probe = (params) => { received = params; return []; };
  const params = { page: 1 };
  // 错误写法：JSON 文本直接当 JS 字面量塞进去（对象字面量）
  vm.runInContext(`__capyInvoke("c1", "probe", ${JSON.stringify(params)});`, sandbox);
  await new Promise((r) => setTimeout(r, 20));
  check('错误写法下组件拿到的是 {}（参数被丢掉）', received && typeof received === 'object' && Object.keys(received).length === 0,
    `收到 ${JSON.stringify(received)}`);
});

console.log('== 2. loadDetail：字符串参数必须原样送达 ==');
await withRuntime(async (sandbox) => {
  let received = 'NOT_CALLED';
  sandbox.loadDetail = (link) => {
    received = link;
    return { title: 'x', videoUrl: 'https://cdn/1.m3u8' };
  };
  const url = 'https://happy-capy.garland.indevs.in/api/v1/providers/hongguo/items/abc?x=1';
  vm.runInContext(buildExpression('__capyInvokeArg', 'c2', 'loadDetail', JSON.stringify(url)), sandbox);
  await new Promise((r) => setTimeout(r, 20));
  check('组件拿到的 link 是字符串', typeof received === 'string', `收到 ${typeof received} / ${String(received)}`);
  check('link 内容逐字一致', received === url, `收到 ${String(received)}`);
});

console.log('== 3. loadDetail：对象写法（容错组件）也要能送达 ==');
await withRuntime(async (sandbox) => {
  let received = null;
  sandbox.loadDetail = (link) => {
    received = link;
    return { title: 'x', seasons: [] };
  };
  const item = { link: 'https://x/items/1', detailUrl: 'https://x/items/1', id: '1', title: 't' };
  vm.runInContext(buildExpression('__capyInvokeArg', 'c3', 'loadDetail', JSON.stringify(item)), sandbox);
  await new Promise((r) => setTimeout(r, 20));
  check('组件拿到的是对象且字段在', received && received.detailUrl === item.detailUrl && received.id === '1',
    `收到 ${JSON.stringify(received)}`);
});

console.log('== 4. 非字符串 URL 必须被守卫拦住 ==');
await withRuntime(async (sandbox, sent) => {
  let rejected = null;
  vm.runInContext('window.__probeResult = null;', sandbox);
  sandbox.probe = () => sandbox.Widget.http.get(null).catch((e) => { rejected = e; });
  vm.runInContext('__capyInvoke("c4", "probe", "{}");', sandbox);
  await new Promise((r) => setTimeout(r, 30));
  check('抛出的错误信息指出是 null', !!rejected && String(rejected.message).includes('组件传入的是 null'),
    rejected ? rejected.message : '没有抛出');
  const netEvent = sent.find((m) => m.type === 'net' && m.error && String(m.error).includes('组件传入的是 null'));
  check('同时写进网络日志', !!netEvent);
});

console.log('== 5. fetch 必须被桥到原生通道（消 CORS） ==');
await withRuntime(async (sandbox, sent) => {
  let bridged = false;
  sent.length = 0;
  sandbox.fetch('https://example.com/api', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: '{}' })
    .then(() => { bridged = true; })
    .catch(() => {});
  await new Promise((r) => setTimeout(r, 30));
  const httpEvent = sent.find((m) => m.type === 'http' && m.method === 'POST');
  check('fetch 走了原生 http 通道', !!httpEvent && httpEvent.url === 'https://example.com/api',
    httpEvent ? httpEvent.url : '没有 http 事件');
  check('fetch 被标记为已桥接', sandbox.fetch.__capyBridged === true);
  void bridged;
});

console.log('== 6. 宿主播放内核声明：写死 mpv 的组件要被掰成 hls ==');
await withRuntime(async (sandbox) => {
  // 模拟 MissAV：组件顶部 var MISSAV_PLAYER_MODE = "mpv"
  sandbox.MISSAV_PLAYER_MODE = 'mpv';
  sandbox.PLAYER_MODE = 'mpv';
  sandbox.SOMETHING_ELSE = 'keep-me';
  const changed = sandbox.__capyApplyHostPlayerMode('hls');
  check('MISSAV_PLAYER_MODE 被改成 hls', sandbox.MISSAV_PLAYER_MODE === 'hls', sandbox.MISSAV_PLAYER_MODE);
  check('通用 PLAYER_MODE 也被改', sandbox.PLAYER_MODE === 'hls', sandbox.PLAYER_MODE);
  check('返回被改动的全局名', String(changed).includes('MISSAV_PLAYER_MODE'), String(changed));
  check('不误伤其它全局量', sandbox.SOMETHING_ELSE === 'keep-me');
  check('已是 hls 时不重复写', sandbox.__capyApplyHostPlayerMode('hls') === '', '仍返回了改动');
});

console.log('');
if (failures.length) {
  console.log(`失败 ${failures.length} 项：${failures.join(' / ')}`);
  process.exit(1);
}
console.log('全部通过：桥接层的参数编码与 URL 守卫符合预期');
// 运行时里有未完成的 30s 超时定时器（测试桩不会回消息），直接退出不留悬挂
process.exit(0);
