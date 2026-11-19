import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'config.dart';

/// A readable error from the API. [isNetwork] means "could not reach the server" (so offline handling applies).
class ApiException implements Exception {
  ApiException(this.message, {this.status, this.isNetwork = false, this.data = const {}});
  final String message;
  final int? status;
  final bool isNetwork;
  final Map<String, dynamic> data;
  @override
  String toString() => message;
}

const _tokenKey = 'folk_token';

/// Keeps the sign-in token in the phone's secure storage (Android Keystore).
class TokenStore {
  TokenStore() : _s = const FlutterSecureStorage();
  final FlutterSecureStorage _s;
  String? _cache;
  bool _loaded = false;

  Future<String?> read() async {
    if (!_loaded) {
      try {
        _cache = await _s.read(key: _tokenKey);
      } catch (_) {
        _cache = null;
      }
      _loaded = true;
    }
    return _cache;
  }

  Future<void> write(String token) async {
    _cache = token;
    _loaded = true;
    try {
      await _s.write(key: _tokenKey, value: token);
    } catch (_) {}
  }

  Future<void> clear() async {
    _cache = null;
    _loaded = true;
    try {
      await _s.delete(key: _tokenKey);
    } catch (_) {}
  }
}

final tokenStoreProvider = Provider<TokenStore>((ref) => TokenStore());

class Api {
  Api(this._tokens)
    : dio = Dio(
        BaseOptions(
          baseUrl: kApiBaseUrl,
          connectTimeout: const Duration(seconds: 12),
          receiveTimeout: const Duration(seconds: 20),
          sendTimeout: const Duration(seconds: 20),
          contentType: Headers.jsonContentType,
          responseType: ResponseType.json,
        ),
      ) {
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (o, h) async {
          final t = await _tokens.read();
          if (t != null) o.headers['Authorization'] = 'Bearer $t';
          h.next(o);
        },
      ),
    );
  }

  final Dio dio;
  final TokenStore _tokens;

  /// Set by the auth controller: called when the server says the session is no longer valid
  /// (token expired, account disabled or made Public).
  void Function()? onUnauthorized;

  Future<Map<String, dynamic>> get(String path, {Map<String, dynamic>? query}) => _send('GET', path, query: query);

  /// [timeout] lets one slow-but-legitimate request (a big batch write) wait longer than the usual 20 seconds.
  Future<Map<String, dynamic>> post(String path, {Object? body, Duration? timeout}) => _send('POST', path, body: body, timeout: timeout);
  Future<Map<String, dynamic>> put(String path, {Object? body}) => _send('PUT', path, body: body);
  Future<Map<String, dynamic>> patch(String path, {Object? body}) => _send('PATCH', path, body: body);
  Future<Map<String, dynamic>> delete(String path) => _send('DELETE', path);

  /// Downloads a text file (CSV) from the API.
  Future<String> getText(String path, {Map<String, dynamic>? query}) async {
    try {
      final r = await dio.get<String>(
        path,
        queryParameters: query,
        options: Options(responseType: ResponseType.plain),
      );
      return r.data ?? '';
    } on DioException catch (e) {
      throw await _convert(e);
    }
  }

  Future<Map<String, dynamic>> _send(String method, String path, {Map<String, dynamic>? query, Object? body, Duration? timeout}) async {
    try {
      final r = await dio.request<Map<String, dynamic>>(
        path,
        data: body,
        queryParameters: query,
        options: Options(method: method, receiveTimeout: timeout, sendTimeout: timeout),
      );
      return r.data ?? {};
    } on DioException catch (e) {
      throw await _convert(e);
    }
  }

  Future<ApiException> _convert(DioException e) async {
    final res = e.response;
    if (res == null) return ApiException(await _noReplyMessage(e), isNetwork: true);
    final data = res.data is Map ? Map<String, dynamic>.from(res.data as Map) : <String, dynamic>{};
    if (res.statusCode == 401 && data['signed_out'] == true) onUnauthorized?.call();
    final fallback = res.statusCode != null && res.statusCode! >= 500 ? 'The server is busy. Please try again.' : 'Something went wrong.';
    return ApiException((data['error'] as String?) ?? fallback, status: res.statusCode, data: data, isNetwork: (res.statusCode ?? 0) >= 502);
  }
}

/// Why no reply came back, in words the user can act on. The device's own network state tells
/// "this device is offline" apart from "online, but the FOLK server could not be reached".
Future<String> _noReplyMessage(DioException e) async {
  switch (e.type) {
    case DioExceptionType.connectionTimeout:
    case DioExceptionType.sendTimeout:
      return 'Could not connect to the FOLK server in time. Your internet may be slow. Please try again.';
    case DioExceptionType.receiveTimeout:
    case DioExceptionType.transformTimeout:
      return 'The FOLK server is taking too long to reply. Please try again in a moment.';
    case DioExceptionType.badCertificate:
      return 'Secure connection to the FOLK server failed. Check the date and time on this device, or try another network.';
    case DioExceptionType.cancel:
      return 'The request was cancelled. Please try again.';
    case DioExceptionType.badResponse:
    case DioExceptionType.connectionError:
    case DioExceptionType.unknown:
      break;
  }
  var online = true;
  try {
    online = !(await Connectivity().checkConnectivity()).every((r) => r == ConnectivityResult.none);
  } catch (_) {
    // unknown: assume online and blame the server, never "no internet" when we don't know
  }
  if (!online) return 'No internet connection. Connect to Wi-Fi or mobile data, then try again.';
  return kIsWeb
      ? 'Your internet is working, but this page could not reach the FOLK server. Open the site at $kWebUrl, '
            'refresh the page and try again. If it keeps happening, tell the admin.'
      : 'Your internet is working, but the FOLK server could not be reached. Try again, or switch between '
            'Wi-Fi and mobile data. If it keeps happening, tell the admin.';
}

final apiProvider = Provider<Api>((ref) => Api(ref.watch(tokenStoreProvider)));
