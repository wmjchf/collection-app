import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:webview_flutter/webview_flutter.dart';

/// 用隐藏 WebView 加载页面（过抖音等 WAF JS 挑战后抽取内容）
class ClientWebViewFetch {
  ClientWebViewFetch._();

  static const _ua =
      'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) '
      'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 '
      'Mobile/15E148 Safari/604.1';

  static OverlayEntry? _entry;
  static Completer<String>? _active;

  static bool needsWebView(String url) {
    final u = url.toLowerCase();
    return u.contains('douyin.com') ||
        u.contains('iesdouyin.com') ||
        u.contains('v.douyin.com');
  }

  /// 需在有 Overlay 的上下文中调用（App 前台）
  static Future<String> fetchHtml(
    BuildContext context,
    String url, {
    Duration timeout = const Duration(seconds: 55),
  }) async {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) {
      throw ClientWebViewFetchException('链接无效');
    }
    if (_active != null) {
      throw ClientWebViewFetchException('已有页面正在抓取');
    }

    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) {
      throw ClientWebViewFetchException('无法启动页面抓取');
    }

    final loadUri = await _preferShareUri(uri);
    debugPrint('[douyin-fetch] load $loadUri');

    final completer = Completer<String>();
    _active = completer;

    late final WebViewController controller;
    Timer? pollTimer;
    Timer? timeoutTimer;

    void fail(String message) {
      pollTimer?.cancel();
      timeoutTimer?.cancel();
      _removeOverlay();
      if (!completer.isCompleted) {
        completer.completeError(ClientWebViewFetchException(message));
      }
      _active = null;
    }

    void succeed(String html) {
      pollTimer?.cancel();
      timeoutTimer?.cancel();
      _removeOverlay();
      if (!completer.isCompleted) {
        completer.complete(html);
      }
      _active = null;
    }

    Future<void> tryExtract() async {
      if (completer.isCompleted) return;
      try {
        final raw = await controller.runJavaScriptReturningResult(_extractJs);
        final text = _jsString(raw);
        if (text == null || text.isEmpty || text == 'null') return;
        final map = jsonDecode(text) as Map<String, dynamic>;
        if (map['ready'] == true) {
          final html = map['html'] as String?;
          if (html != null && html.length > 80) {
            debugPrint(
              '[douyin-fetch] ready title=${map['title']} video=${map['hasVideo']} cover=${map['hasCover']}',
            );
            succeed(html);
          }
        }
      } catch (e) {
        debugPrint('[douyin-fetch] poll err $e');
      }
    }

    Future<void> injectCaptureHook() async {
      try {
        await controller.runJavaScript(_networkCaptureJs);
      } catch (e) {
        debugPrint('[douyin-fetch] capture hook err $e');
      }
    }

    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(_ua)
      ..setBackgroundColor(const Color(0x00000000))
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) {
            final u = Uri.tryParse(request.url);
            final scheme = (u?.scheme ?? '').toLowerCase();
            // 抖音会跳 snssdk1128:// / aweme:// 等，WKWebView 报 unsupported URL
            if (scheme == 'http' ||
                scheme == 'https' ||
                scheme == 'about' ||
                scheme == 'blob' ||
                scheme == 'data') {
              return NavigationDecision.navigate;
            }
            debugPrint('[douyin-fetch] skip scheme=$scheme');
            return NavigationDecision.prevent;
          },
          onPageStarted: (u) {
            debugPrint('[douyin-fetch] start $u');
            unawaited(injectCaptureHook());
          },
          onPageFinished: (u) async {
            debugPrint('[douyin-fetch] finished $u');
            await injectCaptureHook();
            // note 页正文靠异步接口
            await Future<void>.delayed(const Duration(milliseconds: 1600));
            await tryExtract();
          },
          onWebResourceError: (err) {
            final desc = err.description;
            if (desc.contains('unsupported URL') ||
                desc.contains('snssdk') ||
                desc.contains('aweme')) {
              return;
            }
            debugPrint('[douyin-fetch] resource err $desc');
          },
        ),
      );

    // note 页异步脚本需要足够视口；屏外完整尺寸
    _entry = OverlayEntry(
      builder: (ctx) => Positioned(
        left: -1200,
        top: 0,
        width: 390,
        height: 844,
        child: IgnorePointer(
          child: WebViewWidget(controller: controller),
        ),
      ),
    );
    overlay.insert(_entry!);

    timeoutTimer = Timer(timeout, () {
      fail('页面抓取超时，请稍后重试');
    });

    pollTimer = Timer.periodic(const Duration(milliseconds: 900), (_) {
      unawaited(tryExtract());
    });

    try {
      await controller.loadRequest(
        loadUri,
        headers: const {
          'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
          'Accept': 'text/html,application/xhtml+xml;q=0.9,*/*;q=0.8',
        },
      );
    } catch (_) {
      fail('无法打开页面');
    }

    return completer.future;
  }

  /// 通用：加载任意页面，等 JS 跑完后回传 outerHTML（服务端抽失败时的本机兜底）
  static Future<String> fetchHtmlGeneric(
    BuildContext context,
    String url, {
    Duration timeout = const Duration(seconds: 35),
  }) async {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) {
      throw ClientWebViewFetchException('链接无效');
    }
    if (_active != null) {
      throw ClientWebViewFetchException('已有页面正在抓取');
    }

    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) {
      throw ClientWebViewFetchException('无法启动页面抓取');
    }

    debugPrint('[webview-fetch] generic $uri');
    final completer = Completer<String>();
    _active = completer;

    late final WebViewController controller;
    Timer? pollTimer;
    Timer? timeoutTimer;
    var finishedOnce = false;
    var bestHtml = '';

    void fail(String message) {
      pollTimer?.cancel();
      timeoutTimer?.cancel();
      _removeOverlay();
      if (!completer.isCompleted) {
        completer.completeError(ClientWebViewFetchException(message));
      }
      _active = null;
    }

    void succeed(String html) {
      pollTimer?.cancel();
      timeoutTimer?.cancel();
      _removeOverlay();
      if (!completer.isCompleted) {
        completer.complete(html);
      }
      _active = null;
    }

    Future<void> tryCapture({bool force = false}) async {
      if (completer.isCompleted) return;
      try {
        final raw = await controller.runJavaScriptReturningResult(
          r'''
(function(){
  try {
    var html = document.documentElement ? document.documentElement.outerHTML : '';
    var text = (document.body && document.body.innerText) || '';
    var title = document.title || '';
    var ready = html.length > 800 || text.replace(/\s+/g,'').length > 40;
    return JSON.stringify({
      ready: ready,
      len: html.length,
      title: title,
      html: html
    });
  } catch (e) {
    return JSON.stringify({ ready:false, error:String(e) });
  }
})()
''',
        );
        final text = _jsString(raw);
        if (text == null || text.isEmpty || text == 'null') return;
        final map = jsonDecode(text) as Map<String, dynamic>;
        final html = map['html'] as String? ?? '';
        if (html.length > bestHtml.length) bestHtml = html;
        final ready = map['ready'] == true;
        if ((ready && html.length > 800) || (force && bestHtml.length > 200)) {
          debugPrint(
            '[webview-fetch] generic ready len=${bestHtml.length} title=${map['title']}',
          );
          succeed(bestHtml.isNotEmpty ? bestHtml : html);
        }
      } catch (e) {
        debugPrint('[webview-fetch] generic poll err $e');
      }
    }

    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(_ua)
      ..setBackgroundColor(const Color(0x00000000))
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) {
            final u = Uri.tryParse(request.url);
            final scheme = (u?.scheme ?? '').toLowerCase();
            if (scheme == 'http' ||
                scheme == 'https' ||
                scheme == 'about' ||
                scheme == 'blob' ||
                scheme == 'data') {
              return NavigationDecision.navigate;
            }
            debugPrint('[webview-fetch] skip scheme=$scheme');
            return NavigationDecision.prevent;
          },
          onPageFinished: (u) async {
            finishedOnce = true;
            debugPrint('[webview-fetch] finished $u');
            await Future<void>.delayed(const Duration(milliseconds: 1000));
            await tryCapture();
          },
          onWebResourceError: (err) {
            final desc = err.description;
            if (desc.contains('unsupported URL')) return;
            debugPrint('[webview-fetch] resource err $desc');
          },
        ),
      );

    _entry = OverlayEntry(
      builder: (ctx) => Positioned(
        right: 0,
        bottom: 0,
        width: 320,
        height: 180,
        child: IgnorePointer(
          child: Opacity(
            opacity: 0.02,
            child: WebViewWidget(controller: controller),
          ),
        ),
      ),
    );
    overlay.insert(_entry!);

    timeoutTimer = Timer(timeout, () {
      if (bestHtml.length > 200) {
        succeed(bestHtml);
      } else {
        fail('页面抓取超时，请稍后重试');
      }
    });

    pollTimer = Timer.periodic(const Duration(milliseconds: 1200), (_) {
      unawaited(tryCapture(force: finishedOnce));
    });

    try {
      await controller.loadRequest(
        uri,
        headers: const {
          'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
          'Accept': 'text/html,application/xhtml+xml;q=0.9,*/*;q=0.8',
        },
      );
    } catch (_) {
      fail('无法打开页面');
    }

    return completer.future;
  }

  /// 短链先解析到 aweme id，优先打开 iesdouyin 分享页（比 www 桌面页好抽）
  static Future<Uri> _preferShareUri(Uri raw) async {
    var current = raw;
    final client = http.Client();
    try {
      for (var i = 0; i < 6; i++) {
        final req = http.Request('GET', current)
          ..followRedirects = false
          ..headers.addAll({
            'User-Agent': _ua,
            'Accept': 'text/html,application/xhtml+xml;q=0.9,*/*;q=0.8',
            'Accept-Language': 'zh-CN,zh;q=0.9',
          });
        final streamed = await client.send(req).timeout(
              const Duration(seconds: 12),
            );
        final status = streamed.statusCode;
        final loc = streamed.headers['location'];
        await streamed.stream.drain<void>();

        if (loc != null &&
            loc.isNotEmpty &&
            (status == 301 ||
                status == 302 ||
                status == 303 ||
                status == 307 ||
                status == 308)) {
          current = current.resolve(loc);
          debugPrint('[douyin-fetch] redirect -> $current');
          continue;
        }
        break;
      }
    } catch (e) {
      debugPrint('[douyin-fetch] resolve err $e');
    } finally {
      client.close();
    }

    // 已落到带签分享页则原样保留（note/slides/video），勿改写成无签名 video
    final pathLower = current.path.toLowerCase();
    if (pathLower.contains('/share/note/') ||
        pathLower.contains('/share/slides/') ||
        pathLower.contains('/share/video/')) {
      debugPrint('[douyin-fetch] keep share $current');
      return current;
    }

    final id = _awemeIdFromUri(current) ?? _awemeIdFromUri(raw);
    if (id != null) {
      if (pathLower.contains('/note/') ||
          raw.path.toLowerCase().contains('/note/')) {
        final share = Uri.parse(
          'https://www.iesdouyin.com/share/note/$id/?from_ssr=1',
        );
        debugPrint('[douyin-fetch] note $share');
        return share;
      }
      final share = Uri.parse(
        'https://www.iesdouyin.com/share/video/$id/?from_ssr=1',
      );
      debugPrint('[douyin-fetch] share $share');
      return share;
    }
    return current;
  }

  static String? _awemeIdFromUri(Uri uri) {
    final path = uri.path;
    final m = RegExp(r'/(?:video|note|slides)/(\d{5,})', caseSensitive: false)
        .firstMatch(path);
    if (m != null) return m.group(1);
    for (final key in ['modal_id', 'aweme_id', 'item_ids']) {
      final v = uri.queryParameters[key];
      if (v != null && RegExp(r'^\d{5,}$').hasMatch(v)) return v;
    }
    return null;
  }

  static void _removeOverlay() {
    _entry?.remove();
    _entry = null;
  }

  static String? _jsString(Object raw) {
    if (raw is String) {
      var s = raw;
      if (s.startsWith('"') && s.endsWith('"')) {
        try {
          s = jsonDecode(s) as String;
        } catch (_) {}
      }
      return s;
    }
    return raw.toString();
  }

  /// 拦截 fetch/XHR，抓住 note 页异步下发的 aweme JSON
  static const _networkCaptureJs = r'''
(function(){
  if (window.__SC_DY_HOOKED) return;
  window.__SC_DY_HOOKED = true;
  window.__SC_DY_JSON = window.__SC_DY_JSON || [];
  function keep(t){
    if (!t || t.length < 80 || t.length > 4000000) return;
    if (!/\"images\"|play_addr|aweme_detail|item_list/i.test(t)) return;
    if (window.__SC_DY_JSON.length > 10) window.__SC_DY_JSON.shift();
    window.__SC_DY_JSON.push(t);
  }
  try {
    var ofetch = window.fetch;
    if (ofetch) {
      window.fetch = function(){
        return ofetch.apply(this, arguments).then(function(res){
          try { res.clone().text().then(keep).catch(function(){}); } catch (e) {}
          return res;
        });
      };
    }
  } catch (e) {}
  try {
    var XO = XMLHttpRequest.prototype.open;
    var XS = XMLHttpRequest.prototype.send;
    XMLHttpRequest.prototype.open = function(){
      this.__sc_url = arguments[1];
      return XO.apply(this, arguments);
    };
    XMLHttpRequest.prototype.send = function(){
      this.addEventListener('load', function(){
        try { keep(this.responseText); } catch (e) {}
      });
      return XS.apply(this, arguments);
    };
  } catch (e) {}
})();
''';

  /// 抽取视频/标题/封面/图集，只回传精简 HTML
  static const _extractJs = r'''
(function(){
  function abs(u){
    if(!u) return null;
    u = String(u).trim();
    if(u.indexOf('//')===0) u='https:'+u;
    if(u.indexOf('http://')===0) u='https://'+u.slice(7);
    if(u.indexOf('https://')!==0) return null;
    return u.replace(/\/playwm\//g,'/play/');
  }
  function isJunk(u){
    if(!u) return true;
    return /logo_launcher|fe_app_new|\/eden-cn\/[^"'\\\s]*logo|\/(avatar|logo|icon|emoji|favicon)([_\/.-]|$)/i.test(String(u));
  }
  function firstUrlList(obj){
    if(!obj) return null;
    if(typeof obj==='string') return abs(obj);
    var list = obj.url_list || obj.urlList || obj.uri_list;
    if(list && list.length){
      for(var i=0;i<list.length;i++){
        var u=abs(list[i]);
        if(u) return u;
      }
    }
    return abs(obj.url||obj.uri||null);
  }
  function collectGallery(aweme){
    var out = [];
    var src = aweme.images || aweme.image_list || (aweme.image_post_info && aweme.image_post_info.images) || [];
    if(!Array.isArray(src)) return out;
    for(var i=0;i<src.length;i++){
      var im = src[i];
      var one = firstUrlList(im && im.url_list ? im : im) ||
                (im && im.download_url_list ? firstUrlList({url_list: im.download_url_list}) : null);
      one = abs(one);
      if(one && !isJunk(one) && out.indexOf(one)<0) out.push(one);
    }
    return out;
  }
  function fromAweme(aweme){
    if(!aweme) return null;
    var desc = (aweme.desc || aweme.title || '').trim();
    var author = (aweme.author && (aweme.author.nickname||aweme.author.nick_name)) || null;
    var video = aweme.video || {};
    var videoUrl = firstUrlList(video.play_addr) || firstUrlList(video.play_addr_h264) || firstUrlList(video.playAddr) || null;
    if(!videoUrl && video.bit_rate && video.bit_rate.length){
      for(var i=0;i<video.bit_rate.length;i++){
        videoUrl = firstUrlList(video.bit_rate[i].play_addr || video.bit_rate[i].playAddr);
        if(videoUrl) break;
      }
    }
    var imageUrls = collectGallery(aweme);
    var cover = firstUrlList(video.cover) || firstUrlList(video.origin_cover) || firstUrlList(video.dynamic_cover);
    if(isJunk(cover)) cover = null;
    if(!cover && imageUrls.length) cover = imageUrls[0];
    var title = (desc.split(/\n+/).filter(Boolean)[0]||'').slice(0,80) || (author ? author+'的抖音' : null);
    if(!videoUrl && !cover && !title && !imageUrls.length) return null;
    return { title:title, author:author, desc:desc, videoUrl:videoUrl, cover:cover, imageUrls:imageUrls };
  }
  function walk(node, depth){
    if(!node || typeof node!=='object' || depth>14) return null;
    var best = null;
    function consider(p){
      if(!p) return;
      if(p.imageUrls && p.imageUrls.length){ best = p; return true; }
      if(p.videoUrl){ best = p; return true; }
      if(!best) best = p;
      return false;
    }
    if((node.video || node.images || node.image_list) && (node.desc!=null || node.author || node.aweme_id || node.awemeId)){
      if(consider(fromAweme(node))) return best;
    }
    if(node.item_list && node.item_list[0] && consider(fromAweme(node.item_list[0]))) return best;
    if(node.aweme_detail && consider(fromAweme(node.aweme_detail))) return best;
    if(node.awemeDetail && consider(fromAweme(node.awemeDetail))) return best;
    if(Array.isArray(node)){
      for(var i=0;i<node.length;i++){
        var f=walk(node[i], depth+1);
        if(f && f.imageUrls && f.imageUrls.length) return f;
        if(f && f.videoUrl) return f;
        if(f && !best) best = f;
      }
      return best;
    }
    for(var k in node){
      if(!Object.prototype.hasOwnProperty.call(node,k)) continue;
      var f2=walk(node[k], depth+1);
      if(f2 && f2.imageUrls && f2.imageUrls.length) return f2;
      if(f2 && f2.videoUrl) return f2;
      if(f2 && !best) best = f2;
    }
    return best;
  }
  function parseRouter(){
    try { if (window._ROUTER_DATA) return window._ROUTER_DATA; } catch (e) {}
    var el = document.getElementById('_ROUTER_DATA');
    if (el && el.textContent) {
      try { return JSON.parse(el.textContent); } catch (e) {}
    }
    return null;
  }
  try {
    // 媒体类型跟路径走：/note|/slides → 图文；/video → 视频。勿「有图集就清 videoUrl」
    var pageKind = 'video';
    try {
      var pn = location.pathname || '';
      if (/\/note\//i.test(pn)) pageKind = 'note';
      else if (/\/slides\//i.test(pn)) pageKind = 'slides';
    } catch(e){}
    var isNotePage = pageKind === 'note' || pageKind === 'slides';
    var head = document.documentElement.innerHTML.slice(0, 5000);
    var waf = /waf_js|waf-jschallenge/i.test(head);
    var videoUrl = '';
    var poster = null;
    var videos = document.querySelectorAll('video');
    for(var i=0;i<videos.length;i++){
      var src = videos[i].currentSrc || videos[i].src || '';
      if(src && src.indexOf('http')===0){ videoUrl = abs(src); }
      if(!poster && videos[i].poster) poster = abs(videos[i].poster);
      if(videoUrl) break;
    }
    var picked = null;
    var router = parseRouter();
    if(router){ picked = walk(router.loaderData || router, 0); }
    var ud = document.getElementById('__UNIVERSAL_DATA_FOR_REHYDRATION__');
    if(!picked && ud && ud.textContent){
      try { picked = walk(JSON.parse(ud.textContent), 0); } catch(e){}
    }
    // note：吃拦截到的接口 JSON
    if((!picked || !(picked.imageUrls && picked.imageUrls.length)) && window.__SC_DY_JSON){
      for(var ci=window.__SC_DY_JSON.length-1; ci>=0; ci--){
        try {
          var cp = walk(JSON.parse(window.__SC_DY_JSON[ci]), 0);
          if(cp && ((cp.imageUrls && cp.imageUrls.length) || cp.videoUrl)){
            picked = cp;
            break;
          }
        } catch(e){}
      }
    }
    if(picked && picked.videoUrl) videoUrl = picked.videoUrl;
    // note/slides 动图常带 play_addr，按路径丢掉；video 页即使有图也保留 videoUrl
    if(isNotePage) videoUrl = '';
    var title = (picked && picked.title) || document.title || '';
    if(title.indexOf('抖音')===0 && title.length<8) title = (picked && picked.desc) || title;
    var cover = (picked && picked.cover) || poster || null;
    if(isJunk(cover)) cover = null;
    var gallery = (picked && picked.imageUrls) ? picked.imageUrls.slice() : [];
    gallery = gallery.filter(function(u){ return u && !isJunk(u); });
    // DOM 上的正文图（仅 tos 内容图，不做全页 URL 扫）
    if(!gallery.length){
      var imgs = document.querySelectorAll('img');
      for(var j=0;j<imgs.length;j++){
        var isrc = abs(imgs[j].currentSrc || imgs[j].src || '');
        if(!isrc || isJunk(isrc)) continue;
        if(/tos-cn-p-|tos-cn-i-|~tplv-/i.test(isrc) && gallery.indexOf(isrc)<0) gallery.push(isrc);
      }
    }
    if(!cover && gallery.length) cover = gallery[0];
    var ogTitle = document.querySelector('meta[property="og:title"]');
    if((!title || title==='抖音') && ogTitle) title = ogTitle.getAttribute('content') || title;

    // note/slides：必须有真图集或视频；禁止默认封面冒充成功
    var ready = !waf && (
      !!videoUrl ||
      gallery.length > 0 ||
      (!isNotePage && !!picked && !!(picked.desc||picked.title) && !!cover)
    );
    if(!ready){
      return JSON.stringify({ ready:false, waf:waf, hasVideo:!!videoUrl, gallery:gallery.length, note:isNotePage, captured:(window.__SC_DY_JSON&&window.__SC_DY_JSON.length)||0, title:title });
    }
    var payload = {
      videoUrl: videoUrl || null,
      title: title || null,
      cover: cover || gallery[0] || null,
      imageUrls: gallery,
      author: (picked && picked.author) || null,
      desc: (picked && picked.desc) || null,
      pageKind: pageKind
    };
    if(!payload.videoUrl && !(payload.imageUrls && payload.imageUrls.length)){
      return JSON.stringify({ ready:false, reason:'no-real-media' });
    }
    var safeTitle = (payload.title || '抖音').replace(/</g,'');
    var html = '<!DOCTYPE html><html><head><meta charset="utf-8"><title>'+safeTitle+
      '</title></head><body><script id="SC_DOUYIN_EXTRACT" type="application/json">'+
      JSON.stringify(payload)+'</script></body></html>';
    return JSON.stringify({ ready:true, html:html, title:payload.title, hasVideo:!!payload.videoUrl, hasCover:!!payload.cover, gallery:gallery.length });
  } catch (e) {
    return JSON.stringify({ ready:false, error:String(e) });
  }
})()
''';
}

class ClientWebViewFetchException implements Exception {
  ClientWebViewFetchException(this.message);
  final String message;

  @override
  String toString() => message;
}
