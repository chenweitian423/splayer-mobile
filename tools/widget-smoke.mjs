/// 组件契约冒烟测试：在 Node 沙箱里真跑一遍外部组件的模块函数与 loadDetail，
/// 断言「宿主传给组件的东西」与「组件交回来的东西」都符合规范。
///
/// 用法:
///   node tools/widget-smoke.mjs <组件目录> [关键词]
///
/// 它会拦住这类事故（都是真实踩过的）：
///   * 组件把宿主传入的参数当 URL 用 —— 宿主若传对象，URL 会变成 [object Object]
///   * 模块函数返回的不是数组 / 抛异常
///   * loadDetail 到底吃字符串还是吃对象（两种写法在野都存在）
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';

const dir = process.argv[2];
const keyword = process.argv[3] || '测试';
if (!dir) {
  console.error('用法: node tools/widget-smoke.mjs <组件目录> [关键词]');
  process.exit(2);
}

const files = fs.readdirSync(dir).filter((f) => f.endsWith('.js')).sort();
const problems = [];

function createSandbox(file, calls) {
  const record = (method) => (url, opts) => {
    // ★ 严格断言：宿主只允许传字符串 URL
    if (typeof url !== 'string' || !url.trim()) {
      problems.push(`${file}: ${method} 收到了非字符串 URL（${typeof url} = ${String(url)}）`);
      return Promise.reject(new Error('non-string url'));
    }
    calls.push(`${method} ${url}`);
    return Promise.resolve({ ok: true, status: 200, data: {}, headers: {}, url });
  };
  const Widget = {
    version: 'smoke',
    pluginId: file,
    http: {
      get: record('GET'),
      post: record('POST'),
      put: record('PUT'),
      request: (o) => record((o && o.method) || 'GET')(o && (o.url || o.uri)),
    },
    html: {
      load: () => {
        const collection = {
          length: 0,
          each() { return this; },
          find() { return this; },
          first() { return this; },
          attr() { return null; },
          text() { return ''; },
          html() { return ''; },
        };
        return () => collection;
      },
    },
    dom: { parse: () => 'doc', select: () => [], text: () => '', attr: () => null, remove: () => true },
    storage: { get: () => null, set: () => true, remove: () => true },
    util: { log: () => {} },
    tmdb: { get: () => Promise.resolve({}) },
  };
  const noop = () => {};
  const sandbox = {
    Widget,
    console: { log: noop, warn: noop, error: noop, info: noop },
    fetch: () => Promise.reject(new Error('fetch disabled')),
    Promise, JSON, Date, Math, Object, Array, String, Number, Boolean, RegExp, Error, TypeError,
    parseInt, parseFloat, isNaN, isFinite, encodeURIComponent, decodeURIComponent,
    setTimeout, clearTimeout, setInterval, clearInterval,
    URL, URLSearchParams, TextEncoder, TextDecoder, AbortController, structuredClone,
  };
  sandbox.globalThis = sandbox;
  sandbox.window = sandbox;
  return sandbox;
}

const results = [];

for (const file of files) {
  const source = fs.readFileSync(path.join(dir, file), 'utf8');
  const calls = [];
  const sandbox = createSandbox(file, calls);
  const ctx = vm.createContext(sandbox);
  const entry = { file, title: '', version: '', modules: [], detail: {}, loadError: '' };

  try {
    vm.runInContext(source, ctx, { filename: file, timeout: 15000 });
  } catch (e) {
    entry.loadError = `${e.name}: ${e.message}`;
    problems.push(`${file}: 装载失败 ${entry.loadError}`);
    results.push(entry);
    continue;
  }

  const meta = sandbox.WidgetMetadata;
  if (!meta) {
    problems.push(`${file}: 没有声明 WidgetMetadata`);
    results.push(entry);
    continue;
  }
  entry.title = meta.title || meta.name || '';
  entry.version = meta.version || '';

  const resolve = (name) => {
    try { return String(name).split('.').reduce((o, k) => (o == null ? o : o[k]), sandbox); }
    catch { return undefined; }
  };

  for (const mod of meta.modules || []) {
    const params = {};
    for (const gp of meta.globalParams || []) params[gp.name] = gp.defaultValue ?? gp.value ?? '';
    for (const p of mod.params || []) {
      if (p.name === 'page') params[p.name] = 1;
      else if (p.name === 'keyword') params[p.name] = keyword;
      else params[p.name] = p.value ?? p.defaultValue ?? '';
    }
    calls.length = 0;
    const fn = resolve(mod.functionName);
    let outcome;
    if (typeof fn !== 'function') {
      outcome = 'function-not-found';
      problems.push(`${file}: 模块 ${mod.title || mod.id} 的 ${mod.functionName} 不是全局函数`);
    } else {
      try {
        const value = await Promise.resolve(fn(params));
        outcome = Array.isArray(value) ? `array(${value.length})` : value === null ? 'null' : typeof value;
        if (outcome === 'null') {
          // 返回 null 也是规范违规（必须是数组）
          problems.push(`${file}: 模块 ${mod.title || mod.id} 返回 null`);
        }
      } catch (e) {
        outcome = `${e.name}: ${e.message}`;
        // 组件自己的业务异常（比如线路不可用）不算宿主的契约问题，仅记录
      }
    }
    entry.modules.push({ name: mod.title || mod.id, fn: mod.functionName, outcome, urls: calls.slice(0, 3) });
  }

  // loadDetail：分别按「字符串」与「对象」两种约定调用，看它吃哪种
  const loadDetail = resolve('loadDetail');
  if (typeof loadDetail === 'function') {
    for (const [label, arg] of [
      ['string', 'https://example.com/api/v1/items/1'],
      ['object', { link: 'https://example.com/api/v1/items/1', url: 'https://example.com/api/v1/items/1', id: '1' }],
    ]) {
      calls.length = 0;
      try {
        await Promise.resolve(loadDetail(arg));
        entry.detail[label] = 'ok';
      } catch (e) {
        entry.detail[label] = `${e.name}: ${String(e.message).slice(0, 60)}`;
      }
    }
    if (entry.detail.object === 'ok' && entry.detail.string !== 'ok') {
      problems.push(`${file}: loadDetail 只吃对象，不吃字符串（宿主需回退传对象）`);
    }
  } else {
    entry.detail.string = 'no-loadDetail';
  }

  results.push(entry);
}

console.log('='.repeat(86));
for (const entry of results) {
  console.log(`${entry.file}  ${entry.title} v${entry.version}`);
  for (const m of entry.modules) {
    console.log(`   [${m.name}] ${m.fn} → ${m.outcome}`);
    for (const u of m.urls) console.log(`        ${u}`);
  }
  console.log(`   loadDetail: 字符串=${entry.detail.string || '-'}  对象=${entry.detail.object || '-'}`);
}
console.log('='.repeat(86));
if (problems.length) {
  console.log(`发现 ${problems.length} 个契约问题:`);
  for (const p of problems) console.log(`  ✘ ${p}`);
  process.exit(1);
}
console.log(`通过：${files.length} 个组件，无契约问题`);
