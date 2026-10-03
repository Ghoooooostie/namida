import 'dart:convert';
import 'dart:io';

class AiTranslatorException implements Exception {
  final String message;
  const AiTranslatorException(this.message);

  @override
  String toString() => message;
}

/// Lets the call sites read `http.get(...).ensureOk()` instead of having to
/// unwrap the future first, which is easy to get wrong (`await` binds to the
/// whole expression, so `await http.get(..).ensureOk()` would await the wrong
/// thing).
extension AiHttpResponseFuture on Future<AiHttpResponse> {
  Future<AiHttpResponse> ensureOk() async => (await this).ensureOk();
}

/// Result of a request. [body] is always decoded as UTF-8, several of these
/// engines answer in UTF-8 while claiming something else in the header.
class AiHttpResponse {
  final int statusCode;
  final String body;
  final String? location;

  /// The url the response actually came from, after every redirect. Engines
  /// that scrape a token from an init page must post to this host (www.bing.com
  /// 302s to a regional host whose api rejects the other one).
  final String? finalUrl;

  AiHttpResponse(this.statusCode, this.body, [this.location, this.finalUrl]);

  bool get isOk => statusCode >= 200 && statusCode < 300;

  Map<String, dynamic>? get json {
    if (body.isEmpty) return null;
    try {
      final decoded = jsonDecode(body);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  List<dynamic>? get jsonList {
    if (body.isEmpty) return null;
    try {
      final decoded = jsonDecode(body);
      return decoded is List ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  /// A short single line version of the body, for error messages: an engine
  /// failing to parse the answer is only diagnosable by seeing what came back.
  String get snippet {
    var s = body.replaceAll('\n', ' ').trim();
    if (s.length > 120) s = '${s.substring(0, 120)}…';
    return s.isEmpty ? '<empty body>' : s;
  }

  /// Throws with something readable instead of a bare status code, this is what
  /// ends up on the failed task card.
  AiHttpResponse ensureOk() {
    if (isOk) return this;
    throw AiTranslatorException('HTTP $statusCode${location != null ? ' -> $location' : ''}: $snippet');
  }

  @override
  String toString() => 'AiHttpResponse($statusCode, ${body.length} chars)';
}

/// A very small HTTP client for the key-less ("传统") translation engines.
///
/// They all need the same three things, none of which the app's usual `rhttp`
/// call site makes convenient:
///  * a **cookie jar** that survives from the init request to the translate
///    request (bing / papago / 彩云 / TranslateCom / 阿里 all depend on it),
///  * **form encoded** bodies *and* **query parameters** side by side, since the
///    engines disagree on which one carries the payload (阿里 puts everything in
///    the query and sends no body at all),
///  * the **raw HTML** of an init page, to scrape a token out of it.
///
/// One instance per engine, so cookies never leak between providers.
class AiTranslatorHttp {
  final Map<String, String> _cookies = {};

  /// A desktop UA on purpose: 有道 only answers to its own app's UA, 火山
  /// requires the request to look like it came from a browser extension.
  static const desktopUa = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36';

  static const _chromeSecHeaders = <String, String>{
    'sec-ch-ua': '"Chromium";v="126", "Not.A/Brand";v="24"',
    'sec-ch-ua-mobile': '?0',
    'sec-ch-ua-platform': '"Windows"',
  };

  final HttpClient _client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 20)
    ..userAgent = desktopUa;

  Map<String, String> get cookies => Map.unmodifiable(_cookies);

  Future<AiHttpResponse> _send(
    String method,
    Uri uri, {
    Map<String, String> headers = const {},
    String? body,
    bool followRedirects = true,
    int redirectsLeft = 5,
  }) async {
    final request = await _client.openUrl(method, uri);

    headers.forEach(request.headers.set);
    if (_cookies.isNotEmpty) {
      request.cookies.addAll(_cookies.entries.map((e) => Cookie(e.key, e.value)));
    }
    if (body != null) {
      final bytes = utf8.encode(body);
      request.contentLength = bytes.length;
      request.add(bytes);
    }

    final response = await request.close();
    final text = await response.transform(utf8.decoder).join();
    assert(() {
      // -- device-side ground truth: shows under the flutter tag in logcat.
      // ignore: avoid_print
      print('aiTranslator: $method ${uri.host}${uri.path} -> ${response.statusCode} ${text.length}B');
      return true;
    }());

    for (final cookie in response.cookies) {
      if (cookie.maxAge == 0) {
        _cookies.remove(cookie.name);
      } else {
        _cookies[cookie.name] = cookie.value;
      }
    }

    final location = response.headers.value(HttpHeaders.locationHeader);
    final isRedirect = response.isRedirect || response.statusCode == 302 || response.statusCode == 301;
    if (followRedirects && isRedirect && location != null && redirectsLeft > 0) {
      final next = uri.resolve(location);
      // -- like a browser, a 301/302 after a POST continues as GET
      final keepMethod = method == 'POST' && (response.statusCode == 307 || response.statusCode == 308);
      return _send(
        keepMethod ? method : 'GET',
        next,
        headers: headers,
        followRedirects: true,
        redirectsLeft: redirectsLeft - 1,
      );
    }

    return AiHttpResponse(response.statusCode, text, location, uri.toString());
  }

  static Uri _withQuery(Uri uri, Map<String, String>? query) {
    if (query == null || query.isEmpty) return uri;
    return uri.replace(queryParameters: {...uri.queryParameters, ...query});
  }

  static String encodeForm(Map<String, String> form) =>
      form.entries.map((e) => '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}').join('&');

  Future<AiHttpResponse> get(
    String url, {
    Map<String, String>? query,
    Map<String, String>? headers,
    bool followRedirects = true,
  }) =>
      _send('GET', _withQuery(Uri.parse(url), query), headers: headers ?? const {}, followRedirects: followRedirects);

  Future<AiHttpResponse> post(
    String url, {
    Map<String, String>? query,
    Map<String, String>? headers,
    Map<String, String>? form,
    String? rawBody,
    bool followRedirects = true,
  }) {
    final allHeaders = <String, String>{...?headers};
    String? body = rawBody;
    if (form != null) {
      body = encodeForm(form);
      allHeaders.putIfAbsent('Content-Type', () => 'application/x-www-form-urlencoded; charset=UTF-8');
    }
    return _send('POST', _withQuery(Uri.parse(url), query), headers: allHeaders, body: body, followRedirects: followRedirects);
  }

  /// json body; pass [rawBody] to hand-encode, and [contentType] for the
  /// endpoints that want something other than `application/json` (谷歌).
  Future<AiHttpResponse> postJson(
    String url, {
    Object? json,
    String? rawBody,
    Map<String, String>? query,
    Map<String, String>? headers,
    String contentType = 'application/json',
  }) {
    final allHeaders = <String, String>{...?headers};
    allHeaders.putIfAbsent('Content-Type', () => contentType);
    return _send(
      'POST',
      _withQuery(Uri.parse(url), query),
      headers: allHeaders,
      body: rawBody ?? (json == null ? null : jsonEncode(json)),
    );
  }

  /// 彩云 rejects the POST unless a preflight happened first.
  Future<AiHttpResponse> options(
    String url, {
    Object? json,
    Map<String, String>? headers,
    String contentType = 'application/json',
  }) {
    final allHeaders = <String, String>{...?headers};
    allHeaders['Content-Type'] = allHeaders['Content-Type'] ?? contentType;
    allHeaders['Origin'] = allHeaders['Origin'] ?? uriOrigin(url);
    allHeaders.addAll(_chromeSecHeaders);
    allHeaders['Sec-Fetch-Mode'] = 'cors';
    allHeaders['Sec-Fetch-Site'] = 'cross-site';
    return _send('OPTIONS', Uri.parse(url), headers: allHeaders, body: json == null ? null : jsonEncode(json));
  }

  static String uriOrigin(String url) {
    final uri = Uri.parse(url);
    return '${uri.scheme}://${uri.host}${uri.port == 80 || uri.port == 443 ? '' : ':${uri.port}'}';
  }

  void close() {
    _client.close(force: true);
  }
}

/// Dart has no `html.unescape`, and 谷歌 / 阿里 / TranslateCom all hand back
/// HTML entities in the translation.
String aiHtmlUnescape(String input) {
  if (!input.contains('&')) return input;

  final entities = <String, String>{
    '&amp;': '&',
    '&lt;': '<',
    '&gt;': '>',
    '&quot;': '"',
    '&apos;': "'",
    '&#39;': "'",
    '&nbsp;': ' ',
    '&hellip;': '…',
    '&mdash;': '—',
    '&ndash;': '–',
  };

  var result = input;
  for (final entry in entities.entries) {
    result = result.replaceAll(entry.key, entry.value);
  }

  // -- numeric entities (&#39; / &#x27;)
  result = result.replaceAllMapped(RegExp(r'&#(x?)([0-9a-fA-F]+);'), (match) {
    final code = match.group(2)!;
    final value = match.group(1) == 'x' ? int.tryParse(code, radix: 16) : int.tryParse(code);
    if (value == null || value <= 0 || value > 0x10FFFF) return match.group(0)!;
    return String.fromCharCode(value);
  });

  return result;
}

/// Maps the app's target code onto what an engine accepts. `zh` is the app's
/// simplified chinese: engines that natively do simplified are asked for
/// `zh-CN` (engines with their own spelling override [AiTranslatorEngine.mapTarget]),
/// traditional-only engines get their traditional code as the closest thing,
/// since no simplified/traditional conversion table is shipped here. The
/// explicit traditional request goes to the declared traditional code, engines
/// without one are passed the code as-is.
String aiResolveTarget(String code, {required bool supportsSimplified, required bool supportsTraditional}) {
  return switch (code) {
    'zh' || 'zh-CN' => supportsSimplified ? 'zh-CN' : (supportsTraditional ? 'zh-TW' : code),
    'zh-Hant' || 'zh-TW' => supportsTraditional ? 'zh-TW' : code,
    _ => code,
  };
}
