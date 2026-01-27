import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

const String _fsApiMode = String.fromEnvironment('FS_API_MODE');

const String _fsOAuth2ClientId     = String.fromEnvironment('FS_OAUTH2_CLIENT_ID');
const String _fsOAuth2ClientSecret = String.fromEnvironment('FS_OAUTH2_CLIENT_SECRET');
const bool   _fsDevFetchOAuth2     = bool.fromEnvironment('FS_DEV_FETCH_OAUTH2', defaultValue: false);

const String _fsOAuth2Bearer       = String.fromEnvironment('FS_OAUTH2_BEARER');

const String _fsOAuth1Key    = String.fromEnvironment('FS_OAUTH1_CONSUMER_KEY');
const String _fsOAuth1Secret = String.fromEnvironment('FS_OAUTH1_CONSUMER_SECRET');

bool get _forceOAuth2 => _fsApiMode.toLowerCase() == 'oauth2';
bool get _forceOAuth1 => _fsApiMode.toLowerCase() == 'oauth1';

// void _log(String msg) => print('[NutritionService] $msg');
String _mask(String s, {int show = 6}) => s.isEmpty ? '(empty)' : '${s.substring(0, s.length < show ? s.length : show)}…(${s.length} chars)';


class FSFoodSummary {
  final String id;
  final String name;
  final String type; 
  FSFoodSummary({required this.id, required this.name, required this.type});
}

class FSServing {
  final String id;
  final String description; 
  final double calories, protein, carbs, fat;
  final double? metricAmount; 
  final String? metricUnit; 

  FSServing({
    required this.id,
    required this.description,
    required this.calories,
    required this.protein,
    required this.carbs,
    required this.fat,
    this.metricAmount,
    this.metricUnit,
  });

  factory FSServing.fromJson(Map<String, dynamic> j) {
    double d(v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0.0;
    return FSServing(
      id: '${j['serving_id'] ?? j['id'] ?? ''}',
      description: '${j['serving_description'] ?? j['description'] ?? ''}',
      calories: d(j['calories']),
      protein:  d(j['protein']),
      carbs:    d(j['carbohydrate']),
      fat:      d(j['fat']),
      metricAmount: j['metric_serving_amount'] != null ? d(j['metric_serving_amount']) : null,
      metricUnit: j['metric_serving_unit']?.toString(),
    );
  }
}

class FSFoodDetails {
  final String id;
  final String name;
  final List<FSServing> servings;
  FSFoodDetails({required this.id, required this.name, required this.servings});
}

class NutritionService {
  final http.Client _client;
  _OAuth2Cache? _oauth2; 

  NutritionService({http.Client? client}) : _client = client ?? http.Client() {
    // _log('Init  MODE=${_fsApiMode.isEmpty ? "auto" : _fsApiMode}'
    //     '  O2_ID=${_mask(_fsOAuth2ClientId)}  O2_SECRET=${_mask(_fsOAuth2ClientSecret)}'
    //     '  O2_BEARER=${_mask(_fsOAuth2Bearer)}'
    //     '  O1_KEY=${_mask(_fsOAuth1Key)}  O1_SECRET=${_mask(_fsOAuth1Secret)}'
    //     '  FETCH_OAUTH2=$_fsDevFetchOAuth2');
  }

  Future<FSFoodDetails> getFoodDetailsByBarcode(
    String rawCode, {
    String? region, 
    String? language,
  }) async {
    final gtin13 = _toGtin13(rawCode);
    Map<String, dynamic> data;

    final params = <String, String>{'barcode': gtin13, 'format': 'json'};
    if (region != null && region.isNotEmpty) params['region'] = region;
    if (language != null && language.isNotEmpty && params.containsKey('region')) {
      params['language'] = language;
    }

    if (await _useOAuth2()) {
      data = await _oauth2UrlGet('/food/barcode/find-by-id/v1', params);
    } else {
      data = await _oauth1MethodGet('food.find_id_for_barcode', params);
    }

    final node = data['food_id'];
    final id = (node is Map && node['value'] != null)
        ? '${node['value']}'
        : (node?.toString() ?? '');

    if (id.isEmpty || id == '0') {
      throw StateError('No match for barcode $gtin13');
    }

    return getFoodDetails(id);
  }

  String _toGtin13(String input) {
    final digits = input.replaceAll(RegExp(r'\D'), '');
    if (digits.length == 13) return digits;     
    if (digits.length == 12) return '0$digits'; 
    if (digits.length == 8)  return '00000$digits'; 
    throw ArgumentError('Unsupported barcode length: ${digits.length}');
  }


  Future<List<FSFoodSummary>> searchFoods(String query, {int max = 20, int page = 0}) async {
    final q = query.trim();
    if (q.isEmpty) return const [];

    Map<String, dynamic> data;

    if (await _useOAuth2()) {
      // _log('MODE=oauth2  bearer=${_oauth2 != null}  GET /rest/foods/search/v3  q="$q" page=$page max=$max');
      data = await _oauth2UrlGet('/foods/search/v3', {
        'search_expression': q,
        'max_results': '$max',
        'page_number': '$page',
      });
    } else {
      // _log('MODE=oauth1  GET method=foods.search.v2 (signed)  q="$q" page=$page max=$max');
      data = await _oauth1MethodGet('foods.search.v2', {
        'search_expression': q,
        'max_results': '$max',
        'page_number': '$page',
      });
    }

    dynamic node =
        (data['foods'] ?? const {})['food'] ??
        (data['foods_search'] ?? const {})['results']?['food'];

    if (node == null) return const [];
    final list = node is List ? node : [node];

    return list.map<FSFoodSummary>((f) => FSFoodSummary(
      id:   '${f['food_id']}',
      name: '${f['food_name']}',
      type: '${f['food_type'] ?? ''}',
    )).toList(growable: false);
  }

  Future<List<String>> autocomplete(String expr, {int max = 8}) async {
    final q = expr.trim();
    if (q.isEmpty) return [];

    try {
      if (await _useOAuth2()) {
        // _log('MODE=oauth2  POST /rest/server.api method=foods.autocomplete expr="$q"');
      } else {
        // _log('MODE=oauth1  GET method=foods.autocomplete expr="$q"');
      }
      final data = (await _useOAuth2())
          ? await _oauth2MethodPost('foods.autocomplete', {'expression': q, 'max_results': '$max'})
          : await _oauth1MethodGet('foods.autocomplete', {'expression': q, 'max_results': '$max'});

      final node = (data['suggestions'] ?? {})['suggestion'];
      if (node == null) return [];
      final list = node is List ? node : [node];
      return list.map((e) => '$e').toList(growable: false);
    } catch (e) {
      final msg = '$e';
      if (msg.contains('Missing scope') || msg.contains('Unknown method')) return const [];
      rethrow;
    }
  }

  Future<FSFoodDetails> getFoodDetails(String foodId) async {
    Map<String, dynamic> data;
    if (await _useOAuth2()) {
      // _log('MODE=oauth2  GET /rest/food/v4 id=$foodId');
      data = await _oauth2UrlGet('/food/v4', {'food_id': foodId});
    } else {
      // _log('MODE=oauth1  GET method=food.get id=$foodId');
      data = await _oauth1MethodGet('food.get', {'food_id': foodId});
    }

    final food = data['food'] as Map<String, dynamic>;
    final id = '${food['food_id']}';
    final name = '${food['food_name']}';

    final s = (food['servings'] ?? {})['serving'];
    final raw = s == null ? <Map<String, dynamic>>[] : (s is List ? s : [s]).cast<Map<String, dynamic>>();
    final servings = raw.map((j) => FSServing.fromJson(j)).toList(growable: false);

    return FSFoodDetails(id: id, name: name, servings: servings);
  }

  Future<bool> _useOAuth2() async {
    if (_forceOAuth1) return false;

    if (_fsOAuth2Bearer.isNotEmpty) {
      _oauth2 = _OAuth2Cache(_fsOAuth2Bearer, DateTime.now().add(const Duration(hours: 12)));
      return true;
    }

    if (_forceOAuth2) {
      final ok = await _ensureBearer(strict: true);
      // _log('FORCE oauth2 -> bearer=$ok');
      return ok;
    }

    return await _ensureBearer(strict: false);
  }

  Future<bool> _ensureBearer({required bool strict}) async {
    if (!_fsDevFetchOAuth2) {
      if (strict) throw StateError('FS_DEV_FETCH_OAUTH2 is false but FS_API_MODE=oauth2');
      return false;
    }
    if (_fsOAuth2ClientId.isEmpty || _fsOAuth2ClientSecret.isEmpty) {
      if (strict) {
        throw StateError('OAuth2 client creds missing (FS_OAUTH2_CLIENT_ID/SECRET). '
            'Got ID=${_mask(_fsOAuth2ClientId)}, SECRET=${_mask(_fsOAuth2ClientSecret)}');
      }
      return false;
    }

    if (_oauth2?.isValid == true) return true;

    try {
      final basic = base64Encode(utf8.encode('$_fsOAuth2ClientId:$_fsOAuth2ClientSecret'));
      // _log('Fetching OAuth2 token (client_credentials scope=premier)…');
      final resp = await _client.post(
        Uri.parse('https://oauth.fatsecret.com/connect/token'),
        headers: {
          HttpHeaders.authorizationHeader: 'Basic $basic',
          HttpHeaders.contentTypeHeader: 'application/x-www-form-urlencoded',
          HttpHeaders.acceptHeader: 'application/json',
        },
        body: {'grant_type': 'client_credentials', 'scope': 'premier barcode'},
      );

      final jsonBody = json.decode(resp.body) as Map<String, dynamic>;
      if (resp.statusCode != 200) {
        // _log('OAuth2 token fetch failed: ${resp.statusCode} ${resp.body}');
        _oauth2 = null;
        if (strict) throw StateError('OAuth2 token fetch failed (${resp.statusCode})');
        return false;
      }

      final access = '${jsonBody['access_token']}';
      final expiresIn = (jsonBody['expires_in'] ?? 3000) as int;
      _oauth2 = _OAuth2Cache(access, DateTime.now().add(Duration(seconds: expiresIn - 30)));
      // _log('OAuth2 token OK  token=${_mask(access)}  expiresIn=$expiresIn');
      return true;
    } catch (e) {
      // _log('OAuth2 token fetch error: $e');
      _oauth2 = null;
      if (strict) throw StateError('OAuth2 token fetch error: $e');
      return false;
    }
  }

  Future<Map<String, dynamic>> _oauth2UrlGet(String path, Map<String, String> params) async {
    final qp = <String, String>{'format': 'json', ...params};
    final uri = Uri.https('platform.fatsecret.com', '/rest${path.startsWith('/') ? path : '/$path'}', qp);

    final resp = await _client.get(uri, headers: {
      HttpHeaders.acceptHeader: 'application/json',
      HttpHeaders.authorizationHeader: 'Bearer ${_oauth2!.token}',
    });
    return _parseResponse(resp);
  }

  Future<Map<String, dynamic>> _oauth2MethodPost(String method, Map<String, String> params) async {
    final uri = Uri.https('platform.fatsecret.com', '/rest/server.api');
    final body = {'method': method, 'format': 'json', ...params};
    final resp = await _client.post(
      uri,
      headers: {
        HttpHeaders.authorizationHeader: 'Bearer ${_oauth2!.token}',
        HttpHeaders.contentTypeHeader: 'application/x-www-form-urlencoded',
        HttpHeaders.acceptHeader: 'application/json',
      },
      body: body,
    );
    return _parseResponse(resp);
  }

  String _oauthEnc(String input) {
    final codeUnits = utf8.encode(input);
    final buf = StringBuffer();
    const unreserved = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';
    for (final b in codeUnits) {
      final ch = String.fromCharCode(b);
      if (unreserved.contains(ch)) {
        buf.write(ch);
      } else {
        buf..write('%')..write(b.toRadixString(16).toUpperCase().padLeft(2, '0'));
      }
    }
    return buf.toString();
  }

  String _nonce() {
    const chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final r = Random.secure();
    return List.generate(32, (_) => chars[r.nextInt(chars.length)]).join();
  }
  String _ts() => (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString();

  String _normalizedParams(Map<String, String> params) {
    final pairs = <List<String>>[];
    params.forEach((k, v) => pairs.add([_oauthEnc(k), _oauthEnc(v)]));
    pairs.sort((a, b) {
      final k = a[0].compareTo(b[0]);
      return k != 0 ? k : a[1].compareTo(b[1]);
    });
    return pairs.map((kv) => '${kv[0]}=${kv[1]}').join('&');
  }

  String _oauth1Signature({
    required String httpMethod,
    required String baseUrl,
    required Map<String, String> params, 
    required String consumerSecret,
  }) {
    final baseString = [
      _oauthEnc(httpMethod.toUpperCase()),
      _oauthEnc(baseUrl),
      _oauthEnc(_normalizedParams(params)),
    ].join('&');

    final signingKey = '${_oauthEnc(consumerSecret)}&';
    final hmacSha1 = Hmac(sha1, utf8.encode(signingKey));
    final sig = base64Encode(hmacSha1.convert(utf8.encode(baseString)).bytes);
    return _oauthEnc(sig);
  }

  void _assertOAuth1Creds() {
    if (_fsOAuth1Key.isEmpty || _fsOAuth1Secret.isEmpty) {
      throw StateError('OAuth1 creds missing: FS_OAUTH1_CONSUMER_KEY/FS_OAUTH1_CONSUMER_SECRET');
    }
  }

  Future<Map<String, dynamic>> _oauth1MethodGet(String method, Map<String, String> params) async {
    _assertOAuth1Creds();

    const baseUrl = 'https://platform.fatsecret.com/rest/server.api';
    final oauth = <String, String>{
      'oauth_consumer_key': _fsOAuth1Key,
      'oauth_nonce': _nonce(),
      'oauth_signature_method': 'HMAC-SHA1',
      'oauth_timestamp': _ts(),
      'oauth_version': '1.0',
    };
    final all = <String, String>{'method': method, 'format': 'json', ...params, ...oauth};

    final sig = _oauth1Signature(
      httpMethod: 'GET',
      baseUrl: baseUrl,
      params: all,
      consumerSecret: _fsOAuth1Secret,
    );

    final qp = {...all, 'oauth_signature': sig};
    final query = qp.entries.map((e) => '${_oauthEnc(e.key)}=${_oauthEnc(e.value)}').join('&');
    final url = '$baseUrl?$query';

    final resp = await _client.get(Uri.parse(url), headers: {HttpHeaders.acceptHeader: 'application/json'});
    return _parseResponse(resp);
  }

  Map<String, dynamic> _parseResponse(http.Response resp) {
    Map<String, dynamic> body;
    try {
      body = json.decode(resp.body) as Map<String, dynamic>;
    } catch (_) {
      throw StateError('FatSecret ${resp.statusCode}: ${resp.body}');
    }
    final err = body['error'];
    if (err is Map) {
      // _log('API ERROR ${err['code']}: ${err['message']} (status=${resp.statusCode})');
      throw StateError('FatSecret error ${err['code']}: ${err['message']}');
    }
    if (resp.statusCode != 200) {
      throw StateError('FatSecret ${resp.statusCode}: ${resp.body}');
    }
    return body;
  }
}

class _OAuth2Cache {
  final String token;
  final DateTime expiry;
  _OAuth2Cache(this.token, this.expiry);
  bool get isValid => DateTime.now().isBefore(expiry) && token.isNotEmpty;
}

