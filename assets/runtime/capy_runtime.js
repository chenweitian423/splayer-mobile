/*
 * capy_runtime.js —— CapyPlayer / Forward Widget 兼容运行时（宿主侧 JS 部分）
 *
 * 在 WebView 里注入 window.Widget，把全部能力桥回原生：
 *   Widget.http.get/post/request   -> 原生 HTTP（绕开 WebView 的 CORS / UA 限制）
 *   Widget.html.load(html)         -> 基于 jQuery 的 cheerio 等价物
 *   Widget.dom.parse/select/...    -> CapyPlayer 的 DOM API
 *   Widget.storage.*               -> localStorage 命名空间隔离
 *   Widget.util.log / console
 *
 * 调用约定（与 SPlayer 的 cbId + Promise 双通道一致）：
 *   JS -> 原生:  CapyBridge.postMessage(JSON.stringify({type, cbId, ...}))
 *   原生 -> JS:  window.__capyHttpResult(cbId, json) / window.__capyReject(cbId, msg)
 */
(function () {
  'use strict';

  var PLUGIN_ID = String(window.__CAPY_PLUGIN_ID__ || 'default');
  var STORE_PREFIX = 'capy.store.' + PLUGIN_ID + '.';
  var httpPending = Object.create(null);
  var cbSeq = 0;
  var DEFAULT_TIMEOUT = Number(window.__CAPY_HTTP_TIMEOUT__ || 30000);

  function post(payload) {
    var text;
    try { text = JSON.stringify(payload); } catch (e) { return; }
    try {
      if (window.CapyBridge && typeof window.CapyBridge.postMessage === 'function') {
        window.CapyBridge.postMessage(text);
        return;
      }
    } catch (e) {}
    try {
      if (typeof window.__capyNativePost === 'function') { window.__capyNativePost(text); }
    } catch (e) {}
  }

  function log(level, args) {
    var parts = [];
    for (var i = 0; i < args.length; i++) {
      var a = args[i];
      try { parts.push(typeof a === 'string' ? a : JSON.stringify(a)); }
      catch (e) { parts.push(String(a)); }
    }
    post({ type: 'log', pluginId: PLUGIN_ID, level: level, message: parts.join(' ') });
  }

  function makeError(message, status, data, headers) {
    var err = new Error(String(message == null ? 'request failed' : message));
    err.ok = false;
    err.status = Number(status) || 0;
    err.response = { ok: false, status: err.status, data: data === undefined ? '' : data, headers: headers || {} };
    return err;
  }

  /* ------------------------------------------------------------------ http */
  function normalizeOptions(opts) {
    opts = opts || {};
    var out = {
      headers: {},
      timeout: Number(opts.timeout || opts.timeoutMs || DEFAULT_TIMEOUT) || DEFAULT_TIMEOUT,
      body: null,
      params: opts.params || null,
      allowRedirects: opts.allow_redirects !== false,
      dataType: opts.dataType || null
    };
    var src = opts.headers || {};
    for (var k in src) { if (Object.prototype.hasOwnProperty.call(src, k)) { out.headers[k] = String(src[k]); } }
    if (opts.body !== undefined && opts.body !== null) {
      out.body = typeof opts.body === 'string' ? opts.body : JSON.stringify(opts.body);
    } else if (opts.data !== undefined && opts.data !== null) {
      out.body = typeof opts.data === 'string' ? opts.data : JSON.stringify(opts.data);
    }
    return out;
  }

  function buildResponse(raw) {
    var data = raw && raw.data;
    if (typeof data === 'string') {
      var trimmed = data.replace(/^\s+/, '');
      if (trimmed.charAt(0) === '{' || trimmed.charAt(0) === '[') {
        try { data = JSON.parse(trimmed); } catch (e) { /* keep string */ }
      }
    }
    var res = {
      ok: !(raw && raw.ok === false),
      status: Number(raw && raw.status) || 0,
      data: data,
      headers: (raw && raw.headers) || {},
      url: (raw && raw.url) || ''
    };
    res.text = function () {
      return Promise.resolve(typeof res.data === 'string' ? res.data : JSON.stringify(res.data));
    };
    res.json = function () {
      try { return Promise.resolve(typeof res.data === 'string' ? JSON.parse(res.data) : res.data); }
      catch (e) { return Promise.reject(e); }
    };
    return res;
  }

  function request(method, url, opts) {
    var options = normalizeOptions(opts);
    return new Promise(function (resolve, reject) {
      // 组件把对象当 URL 传是常见事故（多数组件 loadDetail(link) 会直接把 link
      // 丢给 Widget.http.get）。这里立刻拦下并报出真实类型，避免变成
      // 「No host specified in URI [object Object]」这种看不出源头的错。
      if (typeof url !== 'string' || !url.trim()) {
        var detail = url === null ? 'null' : typeof url;
        var stack = '';
        try { stack = String(new Error('bad url').stack || ''); } catch (e) {}
        var badError = makeError(
          'URL 非法：组件传入的是 ' + detail + '（' + String(url) + '）',
          0, '', {}
        );
        post({
          type: 'net', pluginId: PLUGIN_ID, method: method, url: String(url),
          status: 0, ms: 0, ok: false, bytes: 0, error: badError.message, stack: stack
        });
        reject(badError);
        return;
      }
      var cbId = 'h' + (++cbSeq);
      var startedAt = Date.now();
      var timer = setTimeout(function () {
        var pending = httpPending[cbId];
        if (!pending) { return; }
        delete httpPending[cbId];
        reportNet(pending, 0, 0, 'timeout after ' + options.timeout + 'ms');
        pending.reject(makeError('request timeout after ' + options.timeout + 'ms', 0, '', {}));
      }, options.timeout + 4000);
      httpPending[cbId] = {
        resolve: resolve, reject: reject, timer: timer,
        method: String(method || 'GET').toUpperCase(), url: url, startedAt: startedAt
      };
      post({
        type: 'http',
        pluginId: PLUGIN_ID,
        cbId: cbId,
        method: String(method || 'GET').toUpperCase(),
        url: String(url || ''),
        options: options
      });
    });
  }

  function reportNet(pending, status, bytes, error) {
    post({
      type: 'net', pluginId: PLUGIN_ID, method: pending.method, url: pending.url,
      status: status, ms: Date.now() - pending.startedAt, ok: !error && status > 0 && status < 400,
      bytes: bytes, error: error || ''
    });
  }

  window.__capyHttpResult = function (cbId, payload) {
    var pending = httpPending[cbId];
    if (!pending) { return; }
    clearTimeout(pending.timer);
    delete httpPending[cbId];
    var raw;
    try { raw = typeof payload === 'string' ? JSON.parse(payload) : payload; }
    catch (e) { raw = { ok: false, status: 0, data: '', error: String(e) }; }
    if (raw && raw.transportError) {
      reportNet(pending, 0, 0, String(raw.error || 'network error'));
      pending.reject(makeError(raw.error || 'network error', raw.status || 0, raw.data || '', raw.headers || {}));
      return;
    }
    var bytes = 0;
    try {
      var body = raw && raw.data;
      bytes = typeof body === 'string' ? body.length : JSON.stringify(body || '').length;
    } catch (e) {}
    reportNet(pending, Number(raw && raw.status) || 0, bytes, (raw && raw.ok === false) ? ('HTTP ' + (raw.status || 0)) : '');
    pending.resolve(buildResponse(raw));
  };

  window.__capyReject = function (cbId, message) {
    var pending = httpPending[cbId];
    if (!pending) { return; }
    clearTimeout(pending.timer);
    delete httpPending[cbId];
    reportNet(pending, 0, 0, String(message || 'rejected'));
    pending.reject(makeError(message, 0, '', {}));
  };

  /* ------------------------------------------------------------------ fetch */
  // WebView 的 origin 是本地壳（capy.local），直接 fetch 外部站点会被 CORS 拦。
  // 有些组件写了「Widget.http 优先、fetch 兜底」的双通道，兜底那条必然失败，
  // 所以这里把 fetch 也接到原生通道上，让双通道真正可用。
  (function () {
    var originalFetch = window.fetch ? window.fetch.bind(window) : null;
    window.fetch = function (input, init) {
      var url;
      try {
        url = typeof input === 'string' ? input : (input && input.url) || String(input);
      } catch (e) { url = ''; }
      if (typeof url !== 'string' || !/^https?:/i.test(url)) {
        return originalFetch ? originalFetch(input, init) : Promise.reject(makeError('fetch: 非法 URL ' + url, 0, '', {}));
      }
      var method = String((init && init.method) || (input && input.method) || 'GET').toUpperCase();
      var headers = {};
      var merge = function (source) {
        if (!source) { return; }
        try {
          if (typeof source.forEach === 'function') { source.forEach(function (v, k) { headers[k] = String(v); }); }
          else { Object.keys(source).forEach(function (k) { headers[k] = String(source[k]); }); }
        } catch (e) {}
      };
      merge(input && input.headers);
      if (init && init.headers) { merge(init.headers); }
      var body = init && init.body !== undefined ? init.body : null;
      return request(method, url, { headers: headers, body: body, timeout: DEFAULT_TIMEOUT })
        .then(function (res) {
          var isText = typeof res.data === 'string';
          var text = isText ? res.data : JSON.stringify(res.data);
          var response = {
            ok: res.ok !== false,
            status: res.status || 0,
            statusText: String(res.status || ''),
            headers: res.headers || {},
            url: url,
            json: function () {
              if (!isText) { return Promise.resolve(res.data); }
              try { return Promise.resolve(JSON.parse(text)); }
              catch (e) { return Promise.reject(e); }
            },
            text: function () { return Promise.resolve(text); }
          };
          response.clone = function () { return response; };
          return response;
        });
    };
    window.fetch.__capyBridged = true;
  })();

  /* --------------------------------------------------------------- html/dom */
  function jq() { return window.jQuery || window.$; }

  function loadHtml(html) {
    var text = String(html == null ? '' : html);
    var doc;
    try {
      doc = document.implementation.createHTMLDocument('capy');
      doc.open();
      doc.write(text);
      doc.close();
    } catch (e) {
      try {
        doc = document.implementation.createHTMLDocument('capy');
        doc.documentElement.innerHTML = text;
      } catch (e2) { doc = document; }
    }
    var $ = jq();
    function h(selector, context) {
      if (typeof selector === 'string') { return $(selector, context || doc); }
      if (selector && selector.nodeType) { return $(selector); }
      if (selector == null) { return $([]); }
      return $(selector);
    }
    h.root = $(doc);
    h.document = doc;
    h.html = function () { return doc.documentElement ? doc.documentElement.innerHTML : ''; };
    h.text = function () { return (doc.body && doc.body.textContent) || ''; };
    return h;
  }

  var domDocs = Object.create(null);
  var domSeq = 0;

  function parseHtmlDocument(html) {
    try { return new DOMParser().parseFromString(String(html == null ? '' : html), 'text/html'); }
    catch (e) { return null; }
  }

  var Widget = {
    version: 'capy-compat/1.0.0',
    pluginId: PLUGIN_ID,

    http: {
      get: function (url, opts) { return request('GET', url, opts); },
      post: function (url, body, opts) {
        var options = opts || {};
        if (body !== undefined && body !== null && options.body === undefined) { options.body = body; }
        return request('POST', url, options);
      },
      put: function (url, body, opts) {
        var options = opts || {};
        if (body !== undefined && body !== null && options.body === undefined) { options.body = body; }
        return request('PUT', url, options);
      },
      request: function (options) {
        options = options || {};
        return request(options.method || 'GET', options.url || options.uri || '', options);
      }
    },

    html: {
      load: loadHtml
    },

    dom: {
      parse: function (html) {
        var doc = parseHtmlDocument(html);
        var id = 'doc' + (++domSeq);
        domDocs[id] = doc;
        return id;
      },
      select: function (docId, selector) {
        var doc = domDocs[docId];
        if (!doc) { return []; }
        try { return Array.prototype.slice.call(doc.querySelectorAll(String(selector || ''))); }
        catch (e) { return []; }
      },
      text: function (node) { return node ? String(node.textContent || '') : ''; },
      attr: function (node, name) { return node && node.getAttribute ? node.getAttribute(String(name)) : null; },
      remove: function (docId) { delete domDocs[docId]; return true; }
    },

    storage: {
      get: function (key) {
        try { return window.localStorage.getItem(STORE_PREFIX + String(key)); }
        catch (e) { return null; }
      },
      set: function (key, value) {
        try {
          window.localStorage.setItem(STORE_PREFIX + String(key), typeof value === 'string' ? value : JSON.stringify(value));
          return true;
        } catch (e) { return false; }
      },
      remove: function (key) {
        try { window.localStorage.removeItem(STORE_PREFIX + String(key)); return true; }
        catch (e) { return false; }
      },
      getAsync: function (key) { return Promise.resolve(Widget.storage.get(key)); },
      setAsync: function (key, value) { return Promise.resolve(Widget.storage.set(key, value)); },
      removeAsync: function (key) { return Promise.resolve(Widget.storage.remove(key)); }
    },

    util: {
      log: function () { log('info', Array.prototype.slice.call(arguments)); },
      warn: function () { log('warn', Array.prototype.slice.call(arguments)); }
    },

    proxy: {
      get: function (url, opts) { return request('GET', url, opts); }
    },

    tmdb: {
      get: function () {
        return Promise.reject(makeError('Widget.tmdb 未实现（需要 TMDB API Key，本运行时未内置）', 0, '', {}));
      }
    }
  };

  window.Widget = Widget;

  // 老插件常见的裸 helper
  if (typeof window.apiGet !== 'function') {
    window.apiGet = function (url, opts) { return Widget.http.get(url, opts); };
  }
  if (typeof window.apiGetAbsolute !== 'function') {
    window.apiGetAbsolute = function (url, opts) { return Widget.http.get(url, opts); };
  }
  if (typeof window.ensureArray !== 'function') {
    window.ensureArray = function (value) {
      if (Array.isArray(value)) { return value; }
      if (value == null) { return []; }
      return [value];
    };
  }

  /* ------------------------------------------------------------ 模块调用入口 */
  function resolvePath(path) {
    var parts = String(path || '').split('.');
    var cur = window;
    for (var i = 0; i < parts.length; i++) {
      if (cur == null) { return null; }
      cur = cur[parts[i]];
    }
    return cur;
  }

  function runInvoke(cbId, functionName, invoke) {
    var done = function (ok, payload) {
      var text;
      try { text = JSON.stringify({ ok: ok, data: payload === undefined ? null : payload }); }
      catch (e) { text = JSON.stringify({ ok: false, error: 'result not serializable: ' + e }); }
      post({ type: 'result', pluginId: PLUGIN_ID, cbId: cbId, payload: text });
    };
    var fn;
    try { fn = resolvePath(functionName); } catch (e) { fn = null; }
    if (typeof fn !== 'function') {
      done(false, { error: 'function not found: ' + functionName });
      return;
    }
    var out;
    try { out = invoke(fn); } catch (e) { done(false, { error: String((e && e.message) || e) }); return; }
    Promise.resolve(out).then(function (value) { done(true, value === undefined ? null : value); },
      function (e) { done(false, { error: String((e && e.message) || e) }); });
  }

  /// 模块函数：参数是 params 对象（规范约定）
  window.__capyInvoke = function (cbId, functionName, paramsJson) {
    var params = {};
    try { params = paramsJson ? JSON.parse(paramsJson) : {}; } catch (e) { params = {}; }
    runInvoke(cbId, functionName, function (fn) { return fn(params); });
  };

  /// loadDetail：参数按规范是「链接字符串」，但部分宿主会传整个条目对象，
  /// 组件侧两种写法都存在（有的直接当 URL 用，有的读 .detailUrl/.link）。
  /// 调用方先传字符串，失败再回退传对象。
  window.__capyInvokeArg = function (cbId, functionName, argJson) {
    var arg = null;
    try { arg = (argJson === undefined || argJson === null) ? null : JSON.parse(argJson); }
    catch (e) { arg = null; }
    runInvoke(cbId, functionName, function (fn) { return fn(arg); });
  };

  // 只读元数据（同步返回，给 runJavaScriptReturningResult 用）
  window.__capyMetadata = function () {
    try {
      if (typeof window.WidgetMetadata === 'undefined' || window.WidgetMetadata === null) { return 'null'; }
      return JSON.stringify(window.WidgetMetadata);
    } catch (e) { return 'null'; }
  };

  /// 宿主播放内核声明。
  ///
  /// 组件会把播放模式写成全局常量（实测 MissAV：`var MISSAV_PLAYER_MODE = "mpv"`），
  /// 并据此向后端索要「mpv 专用清单」—— 而本宿主用的是系统播放器
  /// （AVPlayer / ExoPlayer），拿到 mpv 变体只会报 unsupported URL。
  /// 组件装载后把这类全局量改成宿主真正支持的内核即可（MissAV 自己的注释：
  /// 「显式指定 hls/system 时由服务端下发符合 Apple/FFmpeg 标准的 HLS master」）。
  window.__capyApplyHostPlayerMode = function (mode) {
    var target = String(mode || 'hls').toLowerCase();
    var changed = [];
    try {
      Object.keys(window).forEach(function (key) {
        if (!/_?PLAYER_?MODE$/i.test(key)) { return; }
        var value = window[key];
        if (typeof value !== 'string' || !value) { return; }
        if (value.toLowerCase() === target) { return; }
        try {
          window[key] = target;
          changed.push(key + '=' + target);
        } catch (e) {}
      });
    } catch (e) {}
    return changed.join(',');
  };

  // 装配诊断：哪些全局函数可调用
  window.__capyDiagnose = function () {
    var meta = window.WidgetMetadata || {};
    var mods = Array.isArray(meta.modules) ? meta.modules : [];
    var out = [];
    for (var i = 0; i < mods.length; i++) {
      var name = mods[i] && mods[i].functionName;
      var fn = null;
      try { fn = resolvePath(name); } catch (e) { fn = null; }
      out.push({ id: (mods[i] && mods[i].id) || name, functionName: name, present: typeof fn === 'function' });
    }
    return JSON.stringify({ pluginId: PLUGIN_ID, metadata: !!window.WidgetMetadata, modules: out });
  };

  post({ type: 'ready', pluginId: PLUGIN_ID });
})();
