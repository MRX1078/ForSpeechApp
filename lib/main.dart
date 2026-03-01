import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  runApp(const ReflectionDiaryApp());
}

class ReflectionDiaryApp extends StatefulWidget {
  const ReflectionDiaryApp({super.key});

  @override
  State<ReflectionDiaryApp> createState() => _ReflectionDiaryAppState();
}

class _ReflectionDiaryAppState extends State<ReflectionDiaryApp> {
  late final AuthService _authService;
  late final DiaryService _diaryService;
  AppUser? _currentUser;
  bool _isInitializingSession = true;

  @override
  void initState() {
    super.initState();
    _authService = AuthService();
    _diaryService = DiaryService(authService: _authService);
    unawaited(_restoreSession());
  }

  Future<void> _restoreSession() async {
    AppUser? restoredUser;
    try {
      restoredUser = await _authService
          .tryRestoreSession()
          .timeout(const Duration(seconds: 1), onTimeout: () => null);
      if (restoredUser != null) {
        try {
          await _diaryService.refreshEntries(restoredUser);
        } catch (_) {
          // Ignore initial sync errors: UI will surface them later.
        }
      }
    } catch (_) {
      restoredUser = null;
    }
    if (!mounted) {
      return;
    }

    setState(() {
      _currentUser = restoredUser;
      _isInitializingSession = false;
    });
  }

  void _handleAuthenticated(AppUser user) {
    setState(() {
      _currentUser = user;
    });
    unawaited(
      _diaryService.refreshEntries(user).catchError((Object _) {
        // Ошибка будет показана на экране хаба как состояние синхронизации.
      }),
    );
  }

  Future<void> _handleSignOut() async {
    final AppUser? user = _currentUser;
    if (user == null) {
      return;
    }

    await _authService.signOut(user);
    if (!mounted) {
      return;
    }

    setState(() {
      _currentUser = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isInitializingSession) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          backgroundColor: _AppColors.background,
          body: const Center(child: CircularProgressIndicator()),
        ),
      );
    }

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Reflection Diary',
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: _AppColors.background,
        colorScheme: const ColorScheme.light(
          primary: _AppColors.mintDark,
          secondary: _AppColors.lavenderDark,
          surface: _AppColors.cardStrong,
          onPrimary: Colors.white,
          onSecondary: Colors.white,
          onSurface: _AppColors.textPrimary,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          foregroundColor: _AppColors.textPrimary,
          centerTitle: false,
          titleTextStyle: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: _AppColors.textPrimary,
          ),
        ),
        dividerColor: _AppColors.border,
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: _AppColors.mutedSurface,
          hintStyle: const TextStyle(color: _AppColors.textMuted, fontSize: 13),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: _AppColors.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: _AppColors.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: _AppColors.mintDark),
          ),
        ),
      ),
      home: _currentUser == null
          ? AuthScreen(
              authService: _authService,
              onAuthenticated: _handleAuthenticated,
            )
          : DiaryHubScreen(
              user: _currentUser!,
              diaryService: _diaryService,
              onSignOut: _handleSignOut,
            ),
    );
  }
}

class AppUser {
  const AppUser({
    required this.id,
    required this.name,
    required this.email,
    required this.isGoogleAccount,
  });

  final String id;
  final String name;
  final String email;
  final bool isGoogleAccount;
}

class AuthException implements Exception {
  const AuthException(this.message);

  final String message;
}

class ApiException implements Exception {
  const ApiException(this.message);

  final String message;
}

class UserProfile {
  const UserProfile({
    required this.userId,
    required this.summary,
    required this.topics,
    required this.lastUpdated,
    required this.lastMentalHealthIndex,
    required this.lastRiskLevel,
  });

  final String userId;
  final String? summary;
  final List<String> topics;
  final DateTime? lastUpdated;
  final int? lastMentalHealthIndex;
  final String? lastRiskLevel;
}

class _AuthTokens {
  const _AuthTokens({
    required this.accessToken,
    required this.refreshToken,
    required this.tokenType,
  });

  factory _AuthTokens.fromJson(Map<String, dynamic> json) {
    return _AuthTokens(
      accessToken: (json['access_token'] as String?) ?? '',
      refreshToken: (json['refresh_token'] as String?) ?? '',
      tokenType: (json['token_type'] as String?) ?? 'bearer',
    );
  }

  final String accessToken;
  final String refreshToken;
  final String tokenType;

  bool get isValid => accessToken.isNotEmpty && refreshToken.isNotEmpty;
}

class AuthService {
  static const String _apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://46.253.132.35.sslip.io',
  );
  static const String _prefsAccessTokenKey = 'mindflow_access_token';
  static const String _prefsRefreshTokenKey = 'mindflow_refresh_token';
  static const String _prefsTokenTypeKey = 'mindflow_token_type';
  static const String _googleClientId = String.fromEnvironment(
    'GOOGLE_CLIENT_ID',
  );
  static const String _googleServerClientId = String.fromEnvironment(
    'GOOGLE_SERVER_CLIENT_ID',
  );

  AuthService({http.Client? httpClient})
    : _httpClient = httpClient ?? http.Client();

  final GoogleSignIn _googleSignIn = GoogleSignIn.instance;
  final http.Client _httpClient;
  Future<void>? _googleInit;
  Future<SharedPreferences>? _prefsFuture;
  _AuthTokens? _tokens;

  String get apiBaseUrl => _apiBaseUrl;

  Future<AppUser?> tryRestoreSession() async {
    final SharedPreferences prefs = await _prefs();
    final String accessToken = prefs.getString(_prefsAccessTokenKey) ?? '';
    final String refreshToken = prefs.getString(_prefsRefreshTokenKey) ?? '';
    final String tokenType = prefs.getString(_prefsTokenTypeKey) ?? 'bearer';
    if (accessToken.isEmpty || refreshToken.isEmpty) {
      return null;
    }

    _tokens = _AuthTokens(
      accessToken: accessToken,
      refreshToken: refreshToken,
      tokenType: tokenType,
    );

    try {
      return _fetchMe();
    } catch (_) {
      await _clearTokens();
      return null;
    }
  }

  Future<AppUser> signIn({
    required String email,
    required String password,
  }) async {
    final http.Response response = await _httpClient.post(
      _buildUri('/api/auth/login'),
      headers: const <String, String>{
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
      body: jsonEncode(<String, String>{
        'email': email.trim().toLowerCase(),
        'password': password,
      }),
    );
    if (!_isSuccessfulStatus(response.statusCode)) {
      throw AuthException(
        _apiErrorMessage(
          response,
          fallback: 'Не удалось выполнить вход по email и паролю.',
        ),
      );
    }

    final _AuthTokens tokens = _AuthTokens.fromJson(_jsonObject(response.body));
    if (!tokens.isValid) {
      throw const AuthException(
        'Сервер вернул неполные данные авторизации. Повторите попытку.',
      );
    }
    await _setTokens(tokens);
    return _fetchMe();
  }

  Future<AppUser> register({
    required String name,
    required String email,
    required String password,
  }) async {
    final http.Response response = await _httpClient.post(
      _buildUri('/api/auth/register'),
      headers: const <String, String>{
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
      body: jsonEncode(<String, String>{
        'email': email.trim().toLowerCase(),
        'password': password,
        'full_name': name.trim(),
      }),
    );
    if (!_isSuccessfulStatus(response.statusCode)) {
      throw AuthException(
        _apiErrorMessage(
          response,
          fallback: 'Не удалось зарегистрировать пользователя.',
        ),
      );
    }

    final Map<String, dynamic> payload = _jsonObject(response.body);
    final Map<String, dynamic>? userJson =
        payload['user'] as Map<String, dynamic>?;
    final Map<String, dynamic>? tokensJson =
        payload['tokens'] as Map<String, dynamic>?;
    if (userJson == null || tokensJson == null) {
      throw const AuthException(
        'Сервер вернул неполные данные регистрации. Повторите попытку.',
      );
    }

    final _AuthTokens tokens = _AuthTokens.fromJson(tokensJson);
    if (!tokens.isValid) {
      throw const AuthException(
        'Сервер вернул неполные данные авторизации. Повторите попытку.',
      );
    }
    await _setTokens(tokens);
    return _appUserFromApi(userJson, isGoogleAccount: false);
  }

  Future<AppUser> _fetchMe() async {
    final http.Response response = await authorizedRequest((
      String accessToken,
    ) {
      return _httpClient.get(
        _buildUri('/api/auth/me'),
        headers: <String, String>{
          'Accept': 'application/json',
          'Authorization': 'Bearer $accessToken',
        },
      );
    });
    if (!_isSuccessfulStatus(response.statusCode)) {
      throw AuthException(
        _apiErrorMessage(
          response,
          fallback: 'Не удалось получить профиль пользователя.',
        ),
      );
    }
    return _appUserFromApi(_jsonObject(response.body), isGoogleAccount: false);
  }

  Future<http.Response> authorizedRequest(
    Future<http.Response> Function(String accessToken) sendRequest, {
    bool retryUnauthorized = true,
  }) async {
    _tokens ??= await _readTokensFromPrefs();
    final _AuthTokens? currentTokens = _tokens;
    if (currentTokens == null || !currentTokens.isValid) {
      throw const AuthException('Сессия неактивна. Выполните вход снова.');
    }

    http.Response response = await sendRequest(currentTokens.accessToken);
    if (response.statusCode == 401 && retryUnauthorized) {
      await _refreshTokens();
      final _AuthTokens? refreshed = _tokens;
      if (refreshed == null || !refreshed.isValid) {
        throw const AuthException('Сессия истекла. Выполните вход снова.');
      }
      response = await sendRequest(refreshed.accessToken);
    }
    if (response.statusCode == 401) {
      await _clearTokens();
      throw const AuthException('Сессия истекла. Выполните вход снова.');
    }
    return response;
  }

  Future<void> _refreshTokens() async {
    final _AuthTokens? current = _tokens;
    if (current == null || current.refreshToken.isEmpty) {
      throw const AuthException(
        'Не найден refresh-токен. Выполните вход снова.',
      );
    }

    final http.Response response = await _httpClient.post(
      _buildUri('/api/auth/refresh'),
      headers: const <String, String>{
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
      body: jsonEncode(<String, String>{'refresh_token': current.refreshToken}),
    );
    if (!_isSuccessfulStatus(response.statusCode)) {
      await _clearTokens();
      throw AuthException(
        _apiErrorMessage(
          response,
          fallback: 'Не удалось обновить сессию. Выполните вход снова.',
        ),
      );
    }

    final _AuthTokens refreshedTokens = _AuthTokens.fromJson(
      _jsonObject(response.body),
    );
    if (!refreshedTokens.isValid) {
      await _clearTokens();
      throw const AuthException('Сервер вернул невалидные токены.');
    }
    await _setTokens(refreshedTokens);
  }

  Future<AppUser> signInWithGoogle() async {
    // Swagger backend не содержит endpoint для OAuth Google.
    // Оставляем контролируемую ошибку, чтобы UX был прозрачным.
    await _ensureGoogleInitialized();
    if (!_googleSignIn.supportsAuthenticate()) {
      throw const AuthException(
        'Google-вход недоступен на этой платформе и не поддерживается backend-API.',
      );
    }
    throw const AuthException(
      'Google-вход пока не подключен на backend. Добавьте endpoint обмена Google-токена на JWT.',
    );
  }

  Future<void> signOut(AppUser user) async {
    final _AuthTokens? currentTokens = _tokens;
    if (currentTokens != null && currentTokens.refreshToken.isNotEmpty) {
      try {
        await _httpClient.post(
          _buildUri('/api/auth/logout'),
          headers: const <String, String>{
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
          body: jsonEncode(<String, String>{
            'refresh_token': currentTokens.refreshToken,
          }),
        );
      } catch (_) {
        // Ignore network sign out errors; local cleanup is still required.
      }
    }
    await _clearTokens();

    if (user.isGoogleAccount) {
      await _ensureGoogleInitialized();
      try {
        await _googleSignIn.signOut();
      } on GoogleSignInException {
        // Ignore Google sign out errors to avoid blocking local cleanup.
      }
    }
  }

  Future<_AuthTokens?> _readTokensFromPrefs() async {
    final SharedPreferences prefs = await _prefs();
    final String accessToken = prefs.getString(_prefsAccessTokenKey) ?? '';
    final String refreshToken = prefs.getString(_prefsRefreshTokenKey) ?? '';
    final String tokenType = prefs.getString(_prefsTokenTypeKey) ?? 'bearer';
    if (accessToken.isEmpty || refreshToken.isEmpty) {
      return null;
    }
    return _AuthTokens(
      accessToken: accessToken,
      refreshToken: refreshToken,
      tokenType: tokenType,
    );
  }

  Future<void> _setTokens(_AuthTokens tokens) async {
    _tokens = tokens;
    final SharedPreferences prefs = await _prefs();
    await prefs.setString(_prefsAccessTokenKey, tokens.accessToken);
    await prefs.setString(_prefsRefreshTokenKey, tokens.refreshToken);
    await prefs.setString(_prefsTokenTypeKey, tokens.tokenType);
  }

  Future<void> _clearTokens() async {
    _tokens = null;
    final SharedPreferences prefs = await _prefs();
    await prefs.remove(_prefsAccessTokenKey);
    await prefs.remove(_prefsRefreshTokenKey);
    await prefs.remove(_prefsTokenTypeKey);
  }

  Future<SharedPreferences> _prefs() {
    _prefsFuture ??= SharedPreferences.getInstance();
    return _prefsFuture!;
  }

  Future<void> _ensureGoogleInitialized() {
    _googleInit ??= _googleSignIn.initialize(
      clientId: _googleClientId.isEmpty ? null : _googleClientId,
      serverClientId: _googleServerClientId.isEmpty
          ? null
          : _googleServerClientId,
    );
    return _googleInit!;
  }

  Uri _buildUri(String path, [Map<String, String>? queryParameters]) {
    final Uri baseUri = Uri.parse(_apiBaseUrl);
    return baseUri.replace(
      path: path,
      queryParameters: queryParameters?.isEmpty ?? true
          ? null
          : queryParameters,
    );
  }
}

bool _isSuccessfulStatus(int statusCode) {
  return statusCode >= 200 && statusCode < 300;
}

Map<String, dynamic> _jsonObject(String body) {
  if (body.trim().isEmpty) {
    return <String, dynamic>{};
  }
  final dynamic decoded = jsonDecode(body);
  if (decoded is Map<String, dynamic>) {
    return decoded;
  }
  return <String, dynamic>{};
}

String _apiErrorMessage(http.Response response, {required String fallback}) {
  final Map<String, dynamic> payload = _jsonObject(response.body);
  final dynamic detail = payload['detail'];
  if (detail is String && detail.trim().isNotEmpty) {
    return detail.trim();
  }
  if (detail is List && detail.isNotEmpty) {
    final dynamic first = detail.first;
    if (first is Map<String, dynamic>) {
      final dynamic message = first['msg'];
      if (message is String && message.trim().isNotEmpty) {
        return message.trim();
      }
    }
  }
  if (response.body.trim().isNotEmpty && response.body.length < 120) {
    return response.body.trim();
  }
  return fallback;
}

AppUser _appUserFromApi(
  Map<String, dynamic> payload, {
  required bool isGoogleAccount,
}) {
  final String email = (payload['email'] as String?)?.trim() ?? '';
  final String fullName = (payload['full_name'] as String?)?.trim() ?? '';
  final String name = fullName.isEmpty
      ? (email.contains('@') ? email.split('@').first : 'Пользователь')
      : fullName;
  return AppUser(
    id: (payload['id'] as String?) ?? '',
    name: name,
    email: email,
    isGoogleAccount: isGoogleAccount,
  );
}

enum AuthMode { signIn, signUp }

class AuthScreen extends StatefulWidget {
  const AuthScreen({
    super.key,
    required this.authService,
    required this.onAuthenticated,
  });

  final AuthService authService;
  final ValueChanged<AppUser> onAuthenticated;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  static final RegExp _emailPattern = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  final TextEditingController _signInEmailController = TextEditingController();
  final TextEditingController _signInPasswordController =
      TextEditingController();

  final TextEditingController _signUpNameController = TextEditingController();
  final TextEditingController _signUpEmailController = TextEditingController();
  final TextEditingController _signUpPasswordController =
      TextEditingController();
  final TextEditingController _signUpConfirmPasswordController =
      TextEditingController();

  AuthMode _mode = AuthMode.signIn;
  bool _isSubmitting = false;
  String? _errorText;

  @override
  void dispose() {
    _signInEmailController.dispose();
    _signInPasswordController.dispose();
    _signUpNameController.dispose();
    _signUpEmailController.dispose();
    _signUpPasswordController.dispose();
    _signUpConfirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _submitPrimaryAction() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorText = null;
    });

    try {
      final AppUser user = _mode == AuthMode.signIn
          ? await widget.authService.signIn(
              email: _signInEmailController.text,
              password: _signInPasswordController.text,
            )
          : await widget.authService.register(
              name: _signUpNameController.text,
              email: _signUpEmailController.text,
              password: _signUpPasswordController.text,
            );

      if (!mounted) {
        return;
      }
      widget.onAuthenticated(user);
    } on AuthException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorText = error.message;
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  Future<void> _submitGoogleSignIn() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _isSubmitting = true;
      _errorText = null;
    });

    try {
      final AppUser user = await widget.authService.signInWithGoogle();
      if (!mounted) {
        return;
      }
      widget.onAuthenticated(user);
    } on AuthException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorText = error.message;
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  void _switchMode(AuthMode mode) {
    setState(() {
      _mode = mode;
      _errorText = null;
      _formKey.currentState?.reset();
    });
  }

  String? _validateRequired(String? value, String label) {
    if (value == null || value.trim().isEmpty) {
      return 'Введите $label';
    }
    return null;
  }

  String? _validateEmail(String? value) {
    final String? requiredError = _validateRequired(value, 'email');
    if (requiredError != null) {
      return requiredError;
    }
    if (!_emailPattern.hasMatch(value!.trim())) {
      return 'Введите корректный email';
    }
    return null;
  }

  String? _validatePassword(String? value) {
    final String? requiredError = _validateRequired(value, 'пароль');
    if (requiredError != null) {
      return requiredError;
    }
    if (value!.length < 8) {
      return 'Пароль должен быть не короче 8 символов';
    }
    return null;
  }

  InputDecoration _authInputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    );
  }

  ButtonStyle _mintPrimaryButtonStyle() {
    return FilledButton.styleFrom(
      backgroundColor: _AppColors.mintDark,
      foregroundColor: Colors.white,
      minimumSize: const Size.fromHeight(42),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    );
  }

  ButtonStyle _lavenderActionButtonStyle() {
    return FilledButton.styleFrom(
      backgroundColor: _AppColors.lavender,
      foregroundColor: _AppColors.lavenderDark,
      minimumSize: const Size.fromHeight(42),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool signInMode = _mode == AuthMode.signIn;
    return Scaffold(
      backgroundColor: _AppColors.background,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 430),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 14),
              child: Column(
                children: <Widget>[
                  _SurfaceCard(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      children: <Widget>[
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                'Дневник\nсаморефлексии',
                                style: TextStyle(
                                  fontSize: 24,
                                  height: 1.04,
                                  fontWeight: FontWeight.w800,
                                  color: _AppColors.textPrimary,
                                ),
                              ),
                              SizedBox(height: 6),
                              Text(
                                'Сохраняйте мысли, следите\nза прогрессом и привычкой',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: _AppColors.textMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          width: 76,
                          height: 76,
                          decoration: BoxDecoration(
                            color: const Color(0xFFD8F0EE),
                            borderRadius: BorderRadius.circular(22),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(18),
                            child: Image.asset(
                              _AppAssets.heroPerson,
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  _SurfaceCard(
                    padding: const EdgeInsets.all(14),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: _AppColors.card,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: _AppColors.border),
                            ),
                            child: Row(
                              children: <Widget>[
                                Expanded(
                                  child: _AuthModeSegment(
                                    title: 'Вход',
                                    selected: signInMode,
                                    onTap: _isSubmitting
                                        ? null
                                        : () => _switchMode(AuthMode.signIn),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: _AuthModeSegment(
                                    title: 'Регистрация',
                                    selected: !signInMode,
                                    onTap: _isSubmitting
                                        ? null
                                        : () => _switchMode(AuthMode.signUp),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 14),
                          if (signInMode) ...<Widget>[
                            TextFormField(
                              controller: _signInEmailController,
                              keyboardType: TextInputType.emailAddress,
                              textInputAction: TextInputAction.next,
                              autofillHints: const <String>[
                                AutofillHints.email,
                              ],
                              decoration: _authInputDecoration('Email'),
                              validator: _validateEmail,
                            ),
                            const SizedBox(height: 10),
                            TextFormField(
                              controller: _signInPasswordController,
                              obscureText: true,
                              textInputAction: TextInputAction.done,
                              autofillHints: const <String>[
                                AutofillHints.password,
                              ],
                              decoration: _authInputDecoration('Пароль'),
                              validator: _validatePassword,
                            ),
                          ] else ...<Widget>[
                            TextFormField(
                              controller: _signUpNameController,
                              textInputAction: TextInputAction.next,
                              autofillHints: const <String>[AutofillHints.name],
                              decoration: _authInputDecoration('Имя'),
                              validator: (String? value) {
                                return _validateRequired(value, 'имя');
                              },
                            ),
                            const SizedBox(height: 10),
                            TextFormField(
                              controller: _signUpEmailController,
                              keyboardType: TextInputType.emailAddress,
                              textInputAction: TextInputAction.next,
                              autofillHints: const <String>[
                                AutofillHints.email,
                              ],
                              decoration: _authInputDecoration('Email'),
                              validator: _validateEmail,
                            ),
                            const SizedBox(height: 10),
                            TextFormField(
                              controller: _signUpPasswordController,
                              obscureText: true,
                              textInputAction: TextInputAction.next,
                              autofillHints: const <String>[
                                AutofillHints.newPassword,
                              ],
                              decoration: _authInputDecoration('Пароль'),
                              validator: _validatePassword,
                            ),
                            const SizedBox(height: 10),
                            TextFormField(
                              controller: _signUpConfirmPasswordController,
                              obscureText: true,
                              textInputAction: TextInputAction.done,
                              autofillHints: const <String>[
                                AutofillHints.newPassword,
                              ],
                              decoration: _authInputDecoration(
                                'Подтверждение пароля',
                              ),
                              validator: (String? value) {
                                final String? requiredError = _validateRequired(
                                  value,
                                  'подтверждение пароля',
                                );
                                if (requiredError != null) {
                                  return requiredError;
                                }
                                if (value != _signUpPasswordController.text) {
                                  return 'Пароли не совпадают';
                                }
                                return null;
                              },
                            ),
                          ],
                          if (_errorText != null) ...<Widget>[
                            const SizedBox(height: 10),
                            Text(
                              _errorText!,
                              style: const TextStyle(color: Color(0xFFCA5959)),
                            ),
                          ],
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton(
                              onPressed: _isSubmitting
                                  ? null
                                  : _submitPrimaryAction,
                              style: _mintPrimaryButtonStyle(),
                              child: Text(
                                signInMode ? 'Войти' : 'Создать аккаунт',
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed: _isSubmitting
                                  ? null
                                  : _submitGoogleSignIn,
                              style: _lavenderActionButtonStyle(),
                              icon: const Icon(Icons.login_rounded, size: 18),
                              label: const Text('Войти через Google'),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Center(
                            child: TextButton(
                              onPressed: _isSubmitting
                                  ? null
                                  : () {
                                      _switchMode(
                                        signInMode
                                            ? AuthMode.signUp
                                            : AuthMode.signIn,
                                      );
                                    },
                              child: Text(
                                signInMode
                                    ? 'Нет аккаунта? Регистрация'
                                    : 'Уже есть аккаунт? Войти',
                                style: const TextStyle(
                                  color: _AppColors.textMuted,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AuthModeSegment extends StatelessWidget {
  const _AuthModeSegment({
    required this.title,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        height: 32,
        decoration: BoxDecoration(
          color: selected ? _AppColors.mint : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Center(
          child: Text(
            title,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: selected ? const Color(0xFF2E8F89) : _AppColors.textMuted,
            ),
          ),
        ),
      ),
    );
  }
}

class DiaryService {
  DiaryService({required AuthService authService, http.Client? httpClient})
    : _authService = authService,
      _httpClient = httpClient ?? http.Client();

  final AuthService _authService;
  final http.Client _httpClient;
  final Map<String, Map<String, DiaryEntry>> _entriesByUser =
      <String, Map<String, DiaryEntry>>{};
  final Map<String, UserProfile> _profilesByUser = <String, UserProfile>{};
  String? _lastSyncError;

  String? get lastSyncError => _lastSyncError;

  Future<void> refreshEntries(AppUser user) async {
    final http.Response response = await _authService.authorizedRequest((
      String accessToken,
    ) {
      return _httpClient.get(
        _buildUri('/api/diary/entries', <String, String>{
          'limit': '120',
          'offset': '0',
        }),
        headers: <String, String>{
          'Accept': 'application/json',
          'Authorization': 'Bearer $accessToken',
        },
      );
    });
    if (!_isSuccessfulStatus(response.statusCode)) {
      throw AuthException(
        _apiErrorMessage(
          response,
          fallback: 'Не удалось загрузить список дневников.',
        ),
      );
    }

    final List<dynamic> diaries =
        (_jsonObject(response.body)['diaries'] as List<dynamic>?) ??
        <dynamic>[];
    for (final dynamic raw in diaries) {
      if (raw is Map<String, dynamic>) {
        _mergeApiListItem(user, raw);
      }
    }
    _lastSyncError = null;
  }

  Future<DiaryEntry> refreshEntry(AppUser user, DateTime date) async {
    final String dateIso = _formatApiDate(DateUtils.dateOnly(date));
    final http.Response response = await _authService.authorizedRequest((
      String accessToken,
    ) {
      return _httpClient.get(
        _buildUri('/api/diary/entries/$dateIso'),
        headers: <String, String>{
          'Accept': 'application/json',
          'Authorization': 'Bearer $accessToken',
        },
      );
    });
    if (response.statusCode == 404) {
      return getOrCreateEntry(user, date);
    }
    if (!_isSuccessfulStatus(response.statusCode)) {
      throw AuthException(
        _apiErrorMessage(
          response,
          fallback: 'Не удалось загрузить дневник за выбранную дату.',
        ),
      );
    }

    _mergeApiEntry(user, _jsonObject(response.body));
    _lastSyncError = null;
    return getOrCreateEntry(user, date);
  }

  Future<UserProfile?> refreshProfile(AppUser user) async {
    final http.Response response = await _authService.authorizedRequest((
      String accessToken,
    ) {
      return _httpClient.get(
        _buildUri('/api/profile'),
        headers: <String, String>{
          'Accept': 'application/json',
          'Authorization': 'Bearer $accessToken',
        },
      );
    });
    if (!_isSuccessfulStatus(response.statusCode)) {
      return null;
    }
    final UserProfile profile = _profileFromApi(_jsonObject(response.body));
    _profilesByUser[user.email] = profile;
    return profile;
  }

  Map<String, DiaryEntry> _userEntries(AppUser user) {
    return _entriesByUser.putIfAbsent(user.email, () => <String, DiaryEntry>{});
  }

  UserProfile? profileForUser(AppUser user) {
    return _profilesByUser[user.email];
  }

  DiaryEntry? entryForDate(AppUser user, DateTime date) {
    return _userEntries(user)[_dayKey(date)];
  }

  DiaryEntry getOrCreateEntry(AppUser user, DateTime date) {
    final DateTime day = DateUtils.dateOnly(date);
    return _userEntries(user).putIfAbsent(
      _dayKey(day),
      () => DiaryEntry(
        date: day,
        markdown: _defaultDiaryTemplate(day),
        createdAt: DateTime.now(),
      ),
    );
  }

  List<DiaryEntry> listEntries(AppUser user) {
    final List<DiaryEntry> items = _userEntries(user).values.toList();
    items.sort((DiaryEntry a, DiaryEntry b) => b.date.compareTo(a.date));
    return items;
  }

  Future<void> updateMarkdown(
    AppUser user,
    DateTime date,
    String markdown, {
    bool silent = true,
  }) async {
    final DiaryEntry entry = getOrCreateEntry(user, date);
    if (entry.isClosed) {
      return;
    }
    entry.markdown = markdown;
    entry.updatedAt = DateTime.now();

    try {
      await _upsertEntryRemote(user, entry);
      _lastSyncError = null;
    } catch (error) {
      _lastSyncError = _userMessage(error);
      if (!silent) {
        rethrow;
      }
    }
  }

  Future<DiaryEntry> closeEntry(AppUser user, DateTime date) async {
    final DiaryEntry entry = getOrCreateEntry(user, date);
    if (entry.isClosed) {
      return entry;
    }

    await updateMarkdown(user, date, entry.markdown, silent: true);
    final String dateIso = _formatApiDate(DateUtils.dateOnly(date));
    try {
      final http.Response response = await _authService.authorizedRequest((
        String accessToken,
      ) {
        return _httpClient.post(
          _buildUri('/api/diary/entries/$dateIso/close'),
          headers: <String, String>{
            'Accept': 'application/json',
            'Authorization': 'Bearer $accessToken',
          },
        );
      });
      if (!_isSuccessfulStatus(response.statusCode)) {
        throw AuthException(
          _apiErrorMessage(
            response,
            fallback: 'Не удалось закрыть дневник на сервере.',
          ),
        );
      }

      final Map<String, dynamic> payload = _jsonObject(response.body);
      final Map<String, dynamic>? diaryJson =
          payload['diary'] as Map<String, dynamic>?;
      final Map<String, dynamic>? profileJson =
          payload['profile'] as Map<String, dynamic>?;
      final String assistantMessage =
          (payload['assistant_message'] as String?)?.trim() ?? '';

      if (diaryJson != null) {
        _mergeApiEntry(user, diaryJson);
      } else {
        entry.isClosed = true;
        entry.closedAt = DateTime.now();
      }

      if (profileJson != null) {
        _profilesByUser[user.email] = _profileFromApi(profileJson);
      }

      final DiaryEntry merged = getOrCreateEntry(user, date);
      if (assistantMessage.isNotEmpty) {
        if (merged.chatMessages.isEmpty ||
            merged.chatMessages.last.text != assistantMessage) {
          merged.chatMessages.add(ChatMessage.assistant(assistantMessage));
        }
      }
      _lastSyncError = null;
      return merged;
    } catch (error) {
      // Fallback: сохраняем UX даже если backend временно недоступен.
      _lastSyncError = _userMessage(error);
      entry.isClosed = true;
      entry.closedAt = DateTime.now();
      entry.updatedAt = DateTime.now();

      final DiaryAnalysis analysis = _buildAnalysis(entry.markdown);
      entry.summaryMarkdown = analysis.summaryMarkdown;
      entry.metrics = analysis.metrics;
      entry.chatMessages.add(
        ChatMessage.assistant(
          '## Итоги дня\n'
          '${analysis.summaryMarkdown}\n\n'
          '## Метрики ментального состояния\n'
          '${_metricsMarkdown(analysis.metrics)}\n\n'
          'Если хочешь, можем обсудить, как сделать завтра немного легче и спокойнее.',
        ),
      );
      return entry;
    }
  }

  Future<void> sendChatMessage({
    required AppUser user,
    required DateTime date,
    required String text,
  }) async {
    final DiaryEntry entry = getOrCreateEntry(user, date);
    final String trimmedText = text.trim();
    if (trimmedText.isEmpty) {
      return;
    }

    entry.chatMessages.add(ChatMessage.user(trimmedText));
    entry.updatedAt = DateTime.now();

    await Future<void>.delayed(const Duration(milliseconds: 380));

    entry.chatMessages.add(
      ChatMessage.assistant(_assistantReply(entry, trimmedText)),
    );
    entry.updatedAt = DateTime.now();
  }

  Future<void> _upsertEntryRemote(AppUser user, DiaryEntry entry) async {
    final String dateIso = _formatApiDate(entry.date);
    final http.Response response = await _authService.authorizedRequest((
      String accessToken,
    ) {
      return _httpClient.post(
        _buildUri('/api/diary/entries'),
        headers: <String, String>{
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $accessToken',
        },
        body: jsonEncode(<String, dynamic>{
          'entry_date': dateIso,
          'content': entry.markdown,
        }),
      );
    });

    if (!_isSuccessfulStatus(response.statusCode)) {
      throw AuthException(
        _apiErrorMessage(
          response,
          fallback: 'Не удалось сохранить дневник на сервере.',
        ),
      );
    }
    _mergeApiEntry(user, _jsonObject(response.body));
  }

  void _mergeApiListItem(AppUser user, Map<String, dynamic> item) {
    final String? rawDate = item['entry_date'] as String?;
    if (rawDate == null || rawDate.trim().isEmpty) {
      return;
    }
    final DateTime date = DateUtils.dateOnly(DateTime.parse(rawDate));
    final DiaryEntry entry = getOrCreateEntry(user, date);

    entry.isClosed = (item['is_closed'] as bool?) ?? entry.isClosed;
    entry.summaryMarkdown = item['summary'] as String?;
    entry.metrics = _metricsFromServer(
      mentalHealthIndex: item['mental_health_index'] as int?,
      riskLevel: item['risk_level'] as String?,
    );
    entry.updatedAt = DateTime.now();
  }

  void _mergeApiEntry(AppUser user, Map<String, dynamic> item) {
    final String? rawDate = item['entry_date'] as String?;
    if (rawDate == null || rawDate.trim().isEmpty) {
      return;
    }
    final DateTime date = DateUtils.dateOnly(DateTime.parse(rawDate));
    final DiaryEntry entry = getOrCreateEntry(user, date);

    entry.markdown = (item['content'] as String?) ?? entry.markdown;
    entry.isClosed = (item['is_closed'] as bool?) ?? entry.isClosed;
    entry.closedAt = _parseDateTime(item['closed_at']);
    entry.summaryMarkdown = item['summary'] as String?;
    entry.metrics = _metricsFromServer(
      mentalHealthIndex: item['mental_health_index'] as int?,
      riskLevel: item['risk_level'] as String?,
    );
    entry.updatedAt = _parseDateTime(item['updated_at']) ?? DateTime.now();
  }

  MentalMetrics? _metricsFromServer({
    required int? mentalHealthIndex,
    required String? riskLevel,
  }) {
    if (mentalHealthIndex == null && riskLevel == null) {
      return null;
    }

    final int mood = _clampInt(mentalHealthIndex ?? 60, 5, 95);
    final int stress;
    switch (riskLevel) {
      case 'critical':
        stress = 86;
        break;
      case 'warning':
        stress = 62;
        break;
      case 'safe':
      default:
        stress = 35;
        break;
    }
    final int energy = _clampInt((mood * 0.78).round() + 15, 5, 95);
    final int resilience = _clampInt(
      (mood + (100 - stress) + energy) ~/ 3,
      5,
      95,
    );

    return MentalMetrics(
      mood: mood,
      stress: stress,
      energy: energy,
      resilience: resilience,
    );
  }

  UserProfile _profileFromApi(Map<String, dynamic> payload) {
    final List<String> topics =
        (payload['topics'] as List<dynamic>? ?? <dynamic>[])
            .whereType<String>()
            .toList();
    return UserProfile(
      userId: (payload['user_id'] as String?) ?? '',
      summary: payload['summary'] as String?,
      topics: topics,
      lastUpdated: _parseDateTime(payload['last_updated']),
      lastMentalHealthIndex: payload['last_mental_health_index'] as int?,
      lastRiskLevel: payload['last_risk_level'] as String?,
    );
  }

  DateTime? _parseDateTime(dynamic value) {
    if (value is! String || value.trim().isEmpty) {
      return null;
    }
    return DateTime.tryParse(value);
  }

  DiaryAnalysis _buildAnalysis(String markdown) {
    final String lower = markdown.toLowerCase();
    final int positive = _countKeywords(lower, <String>[
      'рад',
      'благодар',
      'получил',
      'получилась',
      'спокой',
      'хорош',
      'вдохнов',
      'энерг',
      'смог',
    ]);
    final int negative = _countKeywords(lower, <String>[
      'стресс',
      'трев',
      'устал',
      'груст',
      'плохо',
      'зл',
      'выгор',
      'тяжел',
      'одиноч',
    ]);

    final int mood = _clampInt(52 + positive * 8 - negative * 7, 5, 95);
    final int stress = _clampInt(44 + negative * 9 - positive * 5, 5, 95);
    final int energy = _clampInt(50 + positive * 7 - negative * 4, 5, 95);
    final int resilience = _clampInt(
      ((mood + (100 - stress) + energy) / 3).round(),
      5,
      95,
    );

    final MentalMetrics metrics = MentalMetrics(
      mood: mood,
      stress: stress,
      energy: energy,
      resilience: resilience,
    );

    final String summaryMarkdown = _composeSummary(
      markdown: markdown,
      positive: positive,
      negative: negative,
      metrics: metrics,
    );
    return DiaryAnalysis(summaryMarkdown: summaryMarkdown, metrics: metrics);
  }

  String _composeSummary({
    required String markdown,
    required int positive,
    required int negative,
    required MentalMetrics metrics,
  }) {
    final String volumeComment = markdown.trim().length < 100
        ? 'Запись короткая: завтра можно добавить чуть больше деталей о мыслях и эмоциях.'
        : 'Запись достаточно подробная: это хорошо помогает отслеживать динамику состояния.';

    final String emotionalComment;
    if (positive >= negative + 2) {
      emotionalComment =
          'В тексте больше опорных и ресурсных сигналов, чем напряжения.';
    } else if (negative >= positive + 2) {
      emotionalComment =
          'В тексте заметно напряжение: стоит уделить внимание восстановлению и отдыху.';
    } else {
      emotionalComment =
          'Эмоциональный фон смешанный: есть и сложные, и поддерживающие моменты.';
    }

    return '- **Общее состояние:** ${metrics.stateLabel}\n'
        '- **Эмоциональный контекст:** $emotionalComment\n'
        '- **Комментарий по записи:** $volumeComment\n'
        '- **Фокус на завтра:** выделить 1 конкретный шаг заботы о себе (сон, пауза, прогулка, поддержка).';
  }

  String _assistantReply(DiaryEntry entry, String message) {
    final String lower = message.toLowerCase();
    final MentalMetrics? metrics = entry.metrics;

    if (_containsAny(lower, <String>['трев', 'страш', 'паник', 'стресс'])) {
      return 'Понимаю, что сейчас непросто. Давай короткий шаг на 2-3 минуты: '
          'замедлить дыхание и назвать 3 вещи вокруг, которые ты видишь. '
          'Если хочешь, помогу составить небольшой антикризисный план на вечер.';
    }

    if (_containsAny(lower, <String>['устал', 'нет сил', 'выгор'])) {
      return 'Похоже, ресурса действительно мало. Предлагаю минимальный план восстановления: '
          'вода, короткая еда, 15 минут без экрана, и одна простая задача вместо списка из десяти.';
    }

    if (_containsAny(lower, <String>['спасибо', 'благодар'])) {
      return 'Рад быть рядом. Если хочешь, можем закрепить на завтра один реалистичный ритуал '
          'самоподдержки, чтобы зафиксировать прогресс.';
    }

    final String metricsHint = metrics == null
        ? 'Если закроешь дневник, я смогу дать более точные метрики и рекомендации.'
        : 'По текущим метрикам: настроение ${metrics.mood}, стресс ${metrics.stress}, энергия ${metrics.energy}.';
    return 'Слышу тебя. $metricsHint '
        'Можем пойти в формате диалога: что сегодня было самым тяжелым моментом и что помогло с ним справиться хотя бы немного?';
  }

  String _metricsMarkdown(MentalMetrics metrics) {
    return '- Настроение: **${metrics.mood}/100**\n'
        '- Стресс: **${metrics.stress}/100**\n'
        '- Энергия: **${metrics.energy}/100**\n'
        '- Устойчивость: **${metrics.resilience}/100**';
  }

  int _countKeywords(String source, List<String> keywords) {
    int score = 0;
    for (final String keyword in keywords) {
      if (source.contains(keyword)) {
        score++;
      }
    }
    return score;
  }

  bool _containsAny(String source, List<String> keywords) {
    for (final String keyword in keywords) {
      if (source.contains(keyword)) {
        return true;
      }
    }
    return false;
  }

  int _clampInt(int value, int min, int max) {
    if (value < min) {
      return min;
    }
    if (value > max) {
      return max;
    }
    return value;
  }

  String _dayKey(DateTime date) {
    final DateTime day = DateUtils.dateOnly(date);
    final String year = day.year.toString().padLeft(4, '0');
    final String month = day.month.toString().padLeft(2, '0');
    final String dayPart = day.day.toString().padLeft(2, '0');
    return '$year-$month-$dayPart';
  }

  String _defaultDiaryTemplate(DateTime date) {
    final String formattedDate = _formatDate(date);
    return '# Дневник за $formattedDate\n\n'
        '## Как я себя чувствую\n'
        '- \n\n'
        '## Что сегодня получилось\n'
        '- \n\n'
        '## Что было трудным\n'
        '- \n\n'
        '## Что я беру с собой в завтра\n'
        '- ';
  }

  Uri _buildUri(String path, [Map<String, String>? queryParameters]) {
    final Uri baseUri = Uri.parse(_authService.apiBaseUrl);
    return baseUri.replace(
      path: path,
      queryParameters: queryParameters?.isEmpty ?? true
          ? null
          : queryParameters,
    );
  }
}

String _formatApiDate(DateTime date) {
  final DateTime day = DateUtils.dateOnly(date);
  final String year = day.year.toString().padLeft(4, '0');
  final String month = day.month.toString().padLeft(2, '0');
  final String dayPart = day.day.toString().padLeft(2, '0');
  return '$year-$month-$dayPart';
}

String _userMessage(Object error) {
  if (error is AuthException) {
    return error.message;
  }
  if (error is ApiException) {
    return error.message;
  }
  return 'Ошибка синхронизации. Проверьте подключение и повторите.';
}

class DiaryAnalysis {
  const DiaryAnalysis({required this.summaryMarkdown, required this.metrics});

  final String summaryMarkdown;
  final MentalMetrics metrics;
}

class MentalMetrics {
  const MentalMetrics({
    required this.mood,
    required this.stress,
    required this.energy,
    required this.resilience,
  });

  final int mood;
  final int stress;
  final int energy;
  final int resilience;

  String get stateLabel {
    if (resilience >= 75) {
      return 'стабильное';
    }
    if (resilience >= 50) {
      return 'умеренно стабильное';
    }
    return 'чувствительное к нагрузке';
  }
}

enum ChatAuthor { user, assistant }

class ChatMessage {
  const ChatMessage({
    required this.author,
    required this.text,
    required this.createdAt,
  });

  factory ChatMessage.user(String text) {
    return ChatMessage(
      author: ChatAuthor.user,
      text: text,
      createdAt: DateTime.now(),
    );
  }

  factory ChatMessage.assistant(String text) {
    return ChatMessage(
      author: ChatAuthor.assistant,
      text: text,
      createdAt: DateTime.now(),
    );
  }

  final ChatAuthor author;
  final String text;
  final DateTime createdAt;
}

class DiaryEntry {
  DiaryEntry({
    required this.date,
    required this.markdown,
    required this.createdAt,
  }) : updatedAt = createdAt;

  final DateTime date;
  final DateTime createdAt;
  DateTime updatedAt;

  String markdown;
  bool isClosed = false;
  DateTime? closedAt;
  String? summaryMarkdown;
  MentalMetrics? metrics;
  final List<ChatMessage> chatMessages = <ChatMessage>[];
}

class DiaryHubScreen extends StatefulWidget {
  const DiaryHubScreen({
    super.key,
    required this.user,
    required this.diaryService,
    required this.onSignOut,
  });

  final AppUser user;
  final DiaryService diaryService;
  final Future<void> Function() onSignOut;

  @override
  State<DiaryHubScreen> createState() => _DiaryHubScreenState();
}

enum DiaryTabView { diary, ai }

class _AppColors {
  static const Color background = Color(0xFFEFEEF3);
  static const Color card = Color(0xFFF3F3F6);
  static const Color cardStrong = Color(0xFFF9F9FB);
  static const Color mutedSurface = Color(0xFFE9E9EE);
  static const Color border = Color(0xFFE1E1E7);
  static const Color textPrimary = Color(0xFF171719);
  static const Color textMuted = Color(0xFF8B8D97);

  static const Color mint = Color(0xFFC7EFEA);
  static const Color mintDark = Color(0xFF5EBDB4);
  static const Color lavender = Color(0xFFD9D8EF);
  static const Color lavenderDark = Color(0xFF6C669F);
}

class _AppAssets {
  static const String iconAiChat = 'assets/icons/ic_ai_chat.png';
  static const String iconInfo = 'assets/icons/ic_info.png';
  static const String iconNotebook = 'assets/icons/ic_notebook.png';
  static const String iconImage = 'assets/icons/ic_image.png';
  static const String iconMic = 'assets/icons/ic_mic.png';
  static const String iconSmile = 'assets/icons/ic_smile.png';
  static const String heroPerson = 'assets/illustrations/hero_person.png';
  static const String heroHeart = 'assets/illustrations/hero_heart.png';
}

class _DiaryHubScreenState extends State<DiaryHubScreen> {
  bool _isLoading = true;
  String? _loadingError;

  @override
  void initState() {
    super.initState();
    unawaited(_loadHubData());
  }

  Future<void> _loadHubData() async {
    setState(() {
      _isLoading = true;
      _loadingError = null;
    });
    try {
      await widget.diaryService.refreshEntries(widget.user);
      await widget.diaryService.refreshProfile(widget.user);
    } catch (error) {
      _loadingError = _userMessage(error);
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _isLoading = false;
    });
  }

  Future<void> _openTodayDiary() async {
    final DiaryEntry entry = widget.diaryService.getOrCreateEntry(
      widget.user,
      DateTime.now(),
    );
    try {
      await widget.diaryService.refreshEntry(widget.user, entry.date);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_userMessage(error))));
      }
    }
    if (!mounted) {
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute<DiaryEntryScreen>(
        builder: (BuildContext context) {
          return DiaryEntryScreen(
            user: widget.user,
            diaryService: widget.diaryService,
            date: entry.date,
          );
        },
      ),
    );

    if (!mounted) {
      return;
    }
    setState(() {});
  }

  Future<void> _openHistory() async {
    await Navigator.of(context).push(
      MaterialPageRoute<DiaryHistoryScreen>(
        builder: (BuildContext context) {
          return DiaryHistoryScreen(
            user: widget.user,
            diaryService: widget.diaryService,
          );
        },
      ),
    );

    if (!mounted) {
      return;
    }
    setState(() {});
  }

  void _openDashboardsPlaceholder() {
    Navigator.of(context).push(
      MaterialPageRoute<DashboardPlaceholderScreen>(
        builder: (BuildContext context) {
          return const DashboardPlaceholderScreen();
        },
      ),
    );
  }

  Future<void> _openAiChatTab() async {
    DiaryEntry todayEntry = widget.diaryService.getOrCreateEntry(
      widget.user,
      DateTime.now(),
    );

    if (!todayEntry.isClosed) {
      final bool shouldClose = await _confirmCloseForAi();
      if (!shouldClose) {
        return;
      }
      todayEntry = await widget.diaryService.closeEntry(
        widget.user,
        DateTime.now(),
      );
    }

    if (!mounted) {
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute<DiaryAiChatScreen>(
        builder: (BuildContext context) {
          return DiaryAiChatScreen(
            user: widget.user,
            diaryService: widget.diaryService,
            date: todayEntry.date,
          );
        },
      ),
    );

    if (!mounted) {
      return;
    }
    setState(() {});
  }

  Future<bool> _confirmCloseForAi() async {
    final bool? result = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Закрыть дневник за сегодня?'),
          content: const Text(
            'Чтобы открыть ИИ-чат с итогами дня, дневник нужно закрыть.',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Закрыть и перейти'),
            ),
          ],
        );
      },
    );

    return result ?? false;
  }

  String _statusLabel(int mood) {
    if (mood >= 70) {
      return 'Хорошее';
    }
    if (mood >= 45) {
      return 'Умеренное';
    }
    return 'Низкое';
  }

  List<Widget> _buildRecentDayCards(DateTime today) {
    final List<DiaryEntry> recentEntries = widget.diaryService
        .listEntries(widget.user)
        .where((DiaryEntry entry) => entry.date.isBefore(today))
        .take(3)
        .toList();

    final List<_RecentDayData> cards = <_RecentDayData>[];
    for (final DiaryEntry entry in recentEntries) {
      final int mood = entry.metrics?.mood ?? 60;
      cards.add(
        _RecentDayData(date: entry.date, mood: mood, label: _statusLabel(mood)),
      );
    }

    for (int i = cards.length; i < 3; i++) {
      final DateTime fallbackDate = today.subtract(Duration(days: i + 1));
      cards.add(_RecentDayData(date: fallbackDate, mood: 60, label: '—'));
    }

    final List<Widget> widgets = <Widget>[];
    for (int i = 0; i < cards.length; i++) {
      if (i > 0) {
        widgets.add(const SizedBox(width: 8));
      }
      widgets.add(
        Expanded(
          child: _RecentDayCard(data: cards[i], onTap: _openHistory),
        ),
      );
    }
    return widgets;
  }

  @override
  Widget build(BuildContext context) {
    final DateTime today = DateUtils.dateOnly(DateTime.now());
    final DiaryEntry? todayEntry = widget.diaryService.entryForDate(
      widget.user,
      today,
    );
    final int todayMood = todayEntry?.metrics?.mood ?? 62;

    return Scaffold(
      backgroundColor: _AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _SurfaceCard(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: <Widget>[
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            'Дневник\nсаморефлексии',
                            style: TextStyle(
                              fontSize: 24,
                              height: 1.02,
                              fontWeight: FontWeight.w800,
                              color: _AppColors.textPrimary,
                            ),
                          ),
                          SizedBox(height: 6),
                          Text(
                            'Сохраняйте мысли, следите\nза прогрессом и привычкой',
                            style: TextStyle(
                              fontSize: 12,
                              height: 1.25,
                              color: _AppColors.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      width: 76,
                      height: 76,
                      decoration: BoxDecoration(
                        color: const Color(0xFFD8F0EE),
                        borderRadius: BorderRadius.circular(22),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(18),
                        child: Image.asset(
                          _AppAssets.heroPerson,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              _SurfaceCard(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            'Привет, ${widget.user.name}!',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: _AppColors.textPrimary,
                            ),
                          ),
                        ),
                        _RoundIconButton(
                          icon: Icons.bar_chart_rounded,
                          onTap: _openDashboardsPlaceholder,
                        ),
                        const SizedBox(width: 8),
                        _RoundIconButton(
                          icon: Icons.logout_rounded,
                          onTap: () async {
                            await widget.onSignOut();
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: <Widget>[
                        Text(
                          'Сегодня, ${_formatDayMonth(today)}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: _AppColors.textMuted,
                          ),
                        ),
                        const Spacer(),
                        const Icon(
                          Icons.circle,
                          size: 8,
                          color: _AppColors.mintDark,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '$todayMood/100',
                          style: const TextStyle(
                            fontSize: 12,
                            color: _AppColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _openTodayDiary,
                        style: FilledButton.styleFrom(
                          backgroundColor: _AppColors.mintDark,
                          foregroundColor: Colors.white,
                          minimumSize: const Size.fromHeight(38),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(24),
                          ),
                        ),
                        child: const Text('Открыть дневник на сегодня'),
                      ),
                    ),
                  ],
                ),
              ),
              if (_loadingError != null) ...<Widget>[
                const SizedBox(height: 8),
                _SyncStateBanner(
                  message: _loadingError!,
                  actionLabel: 'Повторить',
                  onAction: _loadHubData,
                ),
              ],
              const SizedBox(height: 14),
              Row(
                children: <Widget>[
                  const Text(
                    'Последние дни',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: _AppColors.textPrimary,
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: _openHistory,
                    child: const Text('История'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (_isLoading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: Center(child: CircularProgressIndicator()),
                )
              else
                Row(children: _buildRecentDayCards(today)),
              const Spacer(),
              _BottomSwitchBar(
                activeTab: DiaryTabView.diary,
                onDiaryTap: null,
                onAiTap: _openAiChatTab,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SurfaceCard extends StatelessWidget {
  const _SurfaceCard({
    required this.child,
    this.padding = const EdgeInsets.all(12),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: _AppColors.cardStrong,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _AppColors.border),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x0D000000),
            blurRadius: 10,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _SyncStateBanner extends StatelessWidget {
  const _SyncStateBanner({
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  final String message;
  final String actionLabel;
  final Future<void> Function() onAction;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF1F1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE3B9B9)),
      ),
      child: Row(
        children: <Widget>[
          const Icon(
            Icons.error_outline_rounded,
            size: 16,
            color: Color(0xFFAF5D5D),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: Color(0xFF8F4545)),
            ),
          ),
          TextButton(
            onPressed: () {
              unawaited(onAction());
            },
            child: Text(actionLabel),
          ),
        ],
      ),
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: _AppColors.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _AppColors.border),
        ),
        child: Icon(icon, size: 18, color: _AppColors.textPrimary),
      ),
    );
  }
}

class _RecentDayData {
  const _RecentDayData({
    required this.date,
    required this.mood,
    required this.label,
  });

  final DateTime date;
  final int mood;
  final String label;
}

class _RecentDayCard extends StatelessWidget {
  const _RecentDayCard({required this.data, required this.onTap});

  final _RecentDayData data;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        decoration: BoxDecoration(
          color: _AppColors.cardStrong,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _AppColors.border),
        ),
        child: Column(
          children: <Widget>[
            Text(
              _formatShortDate(data.date),
              style: const TextStyle(fontSize: 11, color: _AppColors.textMuted),
            ),
            const SizedBox(height: 8),
            Image.asset(_AppAssets.iconSmile, width: 20, height: 20),
            const SizedBox(height: 6),
            Text(
              data.label,
              style: const TextStyle(
                fontSize: 11,
                color: _AppColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BottomSwitchBar extends StatelessWidget {
  const _BottomSwitchBar({
    required this.activeTab,
    required this.onDiaryTap,
    required this.onAiTap,
  });

  final DiaryTabView activeTab;
  final VoidCallback? onDiaryTap;
  final VoidCallback? onAiTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: _AppColors.cardStrong,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: _AppColors.border),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: _BottomTabButton(
              title: 'Дневник',
              iconAsset: _AppAssets.iconNotebook,
              active: activeTab == DiaryTabView.diary,
              onTap: onDiaryTap,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: _BottomTabButton(
              title: 'ИИ-чат',
              iconAsset: _AppAssets.iconAiChat,
              active: activeTab == DiaryTabView.ai,
              onTap: onAiTap,
            ),
          ),
        ],
      ),
    );
  }
}

class _BottomTabButton extends StatelessWidget {
  const _BottomTabButton({
    required this.title,
    required this.iconAsset,
    required this.active,
    required this.onTap,
  });

  final String title;
  final String iconAsset;
  final bool active;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final Color background = active ? _AppColors.mint : _AppColors.lavender;
    final Color textColor = active
        ? const Color(0xFF2E8F89)
        : _AppColors.lavenderDark;

    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Container(
        height: 34,
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            ColorFiltered(
              colorFilter: ColorFilter.mode(textColor, BlendMode.srcIn),
              child: Image.asset(iconAsset, width: 16, height: 16),
            ),
            const SizedBox(width: 6),
            Text(
              title,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: textColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class DiaryEntryScreen extends StatefulWidget {
  const DiaryEntryScreen({
    super.key,
    required this.user,
    required this.diaryService,
    required this.date,
  });

  final AppUser user;
  final DiaryService diaryService;
  final DateTime date;

  @override
  State<DiaryEntryScreen> createState() => _DiaryEntryScreenState();
}

class _DiaryEntryScreenState extends State<DiaryEntryScreen> {
  late DiaryEntry _entry;
  late final TextEditingController _controller;
  double _mood = 62;
  bool _isClosingDiary = false;
  bool _isLoadingRemote = true;
  String? _syncError;

  @override
  void initState() {
    super.initState();
    _entry = widget.diaryService.getOrCreateEntry(widget.user, widget.date);
    _controller = TextEditingController(text: _entry.markdown);
    _controller.addListener(_persistDraft);
    _mood = (_entry.metrics?.mood ?? 62).toDouble();
    unawaited(_loadEntryFromServer());
  }

  @override
  void dispose() {
    _controller.removeListener(_persistDraft);
    _controller.dispose();
    super.dispose();
  }

  void _persistDraft() {
    unawaited(
      widget.diaryService.updateMarkdown(
        widget.user,
        widget.date,
        _controller.text,
      ),
    );
  }

  Future<void> _loadEntryFromServer() async {
    setState(() {
      _isLoadingRemote = true;
      _syncError = null;
    });
    try {
      final DiaryEntry synced = await widget.diaryService.refreshEntry(
        widget.user,
        widget.date,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _entry = synced;
        _controller.removeListener(_persistDraft);
        _controller.text = synced.markdown;
        _controller.addListener(_persistDraft);
        _mood = (synced.metrics?.mood ?? _mood).toDouble();
      });
    } catch (error) {
      _syncError = _userMessage(error);
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _isLoadingRemote = false;
    });
  }

  Future<void> _saveDraft() async {
    try {
      await widget.diaryService.updateMarkdown(
        widget.user,
        widget.date,
        _controller.text,
        silent: false,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _syncError = null;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Черновик сохранен')));
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _syncError = _userMessage(error);
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_userMessage(error))));
    }
  }

  Future<void> _closeDiary() async {
    if (_entry.isClosed || _isClosingDiary) {
      return;
    }

    final bool? shouldClose = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Закрыть дневник сегодня?'),
          content: const Text('После закрытия откроется ИИ-чат с итогами дня.'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Закрыть'),
            ),
          ],
        );
      },
    );

    if (shouldClose != true) {
      return;
    }

    setState(() {
      _isClosingDiary = true;
    });

    DiaryEntry closedEntry;
    try {
      await widget.diaryService.updateMarkdown(
        widget.user,
        widget.date,
        _controller.text,
        silent: false,
      );
      closedEntry = await widget.diaryService.closeEntry(
        widget.user,
        widget.date,
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isClosingDiary = false;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_userMessage(error))));
      return;
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _entry = closedEntry;
      _isClosingDiary = false;
    });

    await _openAiChat();
  }

  Future<void> _goToAiChat() async {
    if (!_entry.isClosed) {
      final bool? shouldClose = await showDialog<bool>(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: const Text('Перейти в ИИ-чат?'),
            content: const Text(
              'Для корректных итогов дня дневник нужно закрыть.',
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Остаться'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Закрыть и перейти'),
              ),
            ],
          );
        },
      );

      if (shouldClose != true) {
        return;
      }

      try {
        await widget.diaryService.updateMarkdown(
          widget.user,
          widget.date,
          _controller.text,
          silent: false,
        );
        _entry = await widget.diaryService.closeEntry(widget.user, widget.date);
      } catch (error) {
        if (!mounted) {
          return;
        }
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_userMessage(error))));
        return;
      }
    }

    await _openAiChat();
  }

  Future<void> _openAiChat() async {
    await Navigator.of(context).push(
      MaterialPageRoute<DiaryAiChatScreen>(
        builder: (BuildContext context) {
          return DiaryAiChatScreen(
            user: widget.user,
            diaryService: widget.diaryService,
            date: widget.date,
          );
        },
      ),
    );

    if (!mounted) {
      return;
    }
    setState(() {
      _entry = widget.diaryService.getOrCreateEntry(widget.user, widget.date);
    });
  }

  String _moodSubtitle(int mood) {
    if (mood >= 70) {
      return 'Хорошее настроение';
    }
    if (mood >= 45) {
      return 'Умеренное настроение';
    }
    return 'Сложное настроение';
  }

  @override
  Widget build(BuildContext context) {
    final int moodInt = _mood.round();

    return Scaffold(
      backgroundColor: _AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              if (_isLoadingRemote) const LinearProgressIndicator(minHeight: 2),
              _SurfaceCard(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          const Text(
                            'Сегодня',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              color: _AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _formatDate(widget.date),
                            style: const TextStyle(
                              fontSize: 16,
                              color: _AppColors.textPrimary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _moodSubtitle(moodInt),
                            style: const TextStyle(
                              fontSize: 12,
                              color: _AppColors.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        color: const Color(0xFFD9F2F0),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Image.asset(
                          _AppAssets.heroHeart,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (_syncError != null) ...<Widget>[
                const SizedBox(height: 8),
                _SyncStateBanner(
                  message: _syncError!,
                  actionLabel: 'Обновить',
                  onAction: _loadEntryFromServer,
                ),
              ],
              const SizedBox(height: 10),
              _SurfaceCard(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                child: Column(
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        const Text(
                          'Настроение',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: _AppColors.textPrimary,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          '$moodInt/100',
                          style: const TextStyle(
                            fontSize: 12,
                            color: _AppColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        activeTrackColor: _AppColors.mintDark,
                        inactiveTrackColor: const Color(0xFFDCE2E2),
                        thumbColor: _AppColors.mintDark,
                        trackHeight: 4,
                      ),
                      child: Slider(
                        value: _mood,
                        min: 0,
                        max: 100,
                        onChanged: _entry.isClosed
                            ? null
                            : (double value) {
                                setState(() {
                                  _mood = value;
                                });
                              },
                      ),
                    ),
                    const SizedBox(height: 2),
                    const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        _SliderDot(active: false),
                        SizedBox(width: 5),
                        _SliderDot(active: true),
                        SizedBox(width: 5),
                        _SliderDot(active: false),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: <Widget>[
                  const Text(
                    'Дневник',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: _AppColors.textPrimary,
                    ),
                  ),
                  const Spacer(),
                  _RoundInfoBadge(
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Поддерживается Markdown-формат.'),
                        ),
                      );
                    },
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Expanded(
                child: _SurfaceCard(
                  padding: const EdgeInsets.all(10),
                  child: Container(
                    decoration: BoxDecoration(
                      color: _AppColors.mutedSurface,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: TextField(
                      controller: _controller,
                      enabled: !_entry.isClosed,
                      expands: true,
                      maxLines: null,
                      minLines: null,
                      keyboardType: TextInputType.multiline,
                      textAlignVertical: TextAlignVertical.top,
                      decoration: const InputDecoration(
                        hintText: 'Пиши в формате Markdown',
                        hintStyle: TextStyle(
                          color: _AppColors.textMuted,
                          fontSize: 12,
                        ),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.all(14),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _saveDraft,
                  style: FilledButton.styleFrom(
                    backgroundColor: _AppColors.mint,
                    foregroundColor: const Color(0xFF2F8F89),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                  ),
                  icon: const Icon(Icons.save_outlined, size: 16),
                  label: const Text('Сохранить'),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _goToAiChat,
                  style: FilledButton.styleFrom(
                    backgroundColor: _AppColors.lavender,
                    foregroundColor: _AppColors.lavenderDark,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                  ),
                  icon: const Icon(Icons.auto_awesome_rounded, size: 16),
                  label: const Text('Перейти в ИИ-чат'),
                ),
              ),
              if (!_entry.isClosed)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: _closeDiary,
                    child: _isClosingDiary
                        ? const Text('Закрываем...')
                        : const Text('Закрыть дневник сегодня'),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BackButtonBox extends StatelessWidget {
  const _BackButtonBox({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: _AppColors.cardStrong,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _AppColors.border),
        ),
        child: const Icon(Icons.arrow_back_ios_new_rounded, size: 16),
      ),
    );
  }
}

class _RoundInfoBadge extends StatelessWidget {
  const _RoundInfoBadge({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Container(
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          color: _AppColors.cardStrong,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _AppColors.border),
        ),
        child: Center(
          child: Image.asset(_AppAssets.iconInfo, width: 14, height: 14),
        ),
      ),
    );
  }
}

class _SliderDot extends StatelessWidget {
  const _SliderDot({required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: active ? 6 : 4,
      height: active ? 6 : 4,
      decoration: BoxDecoration(
        color: active ? _AppColors.textMuted : _AppColors.border,
        shape: BoxShape.circle,
      ),
    );
  }
}

class DiaryHistoryScreen extends StatefulWidget {
  const DiaryHistoryScreen({
    super.key,
    required this.user,
    required this.diaryService,
  });

  final AppUser user;
  final DiaryService diaryService;

  @override
  State<DiaryHistoryScreen> createState() => _DiaryHistoryScreenState();
}

class _DiaryHistoryScreenState extends State<DiaryHistoryScreen> {
  bool _isLoading = true;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    unawaited(_loadHistory());
  }

  Future<void> _loadHistory() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    try {
      await widget.diaryService.refreshEntries(widget.user);
    } catch (error) {
      _loadError = _userMessage(error);
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _isLoading = false;
    });
  }

  Future<void> _openEntry(DiaryEntry entry) async {
    try {
      await widget.diaryService.refreshEntry(widget.user, entry.date);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_userMessage(error))));
      }
    }
    if (!mounted) {
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute<DiaryReadOnlyScreen>(
        builder: (BuildContext context) {
          return DiaryReadOnlyScreen(
            user: widget.user,
            diaryService: widget.diaryService,
            date: entry.date,
          );
        },
      ),
    );

    if (!mounted) {
      return;
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final DateTime today = DateUtils.dateOnly(DateTime.now());
    final List<DiaryEntry> pastEntries = widget.diaryService
        .listEntries(widget.user)
        .where((DiaryEntry entry) => entry.date.isBefore(today))
        .toList();

    return Scaffold(
      backgroundColor: _AppColors.background,
      appBar: AppBar(
        title: const Text('Прошлые дневники'),
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: _SyncStateBanner(
                  message: _loadError!,
                  actionLabel: 'Повторить',
                  onAction: _loadHistory,
                ),
              ),
            )
          : pastEntries.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Пока нет дневников за прошлые дни.\n'
                  'Сначала закрой дневник за сегодня.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemBuilder: (BuildContext context, int index) {
                final DiaryEntry entry = pastEntries[index];
                return ListTile(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: const BorderSide(color: _AppColors.border),
                  ),
                  tileColor: _AppColors.cardStrong,
                  title: Text(_formatDate(entry.date)),
                  subtitle: Text(_markdownSnippet(entry.markdown)),
                  trailing: const Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 16,
                  ),
                  onTap: () => _openEntry(entry),
                );
              },
              separatorBuilder: (BuildContext context, int index) {
                return const SizedBox(height: 10);
              },
              itemCount: pastEntries.length,
            ),
    );
  }
}

class DiaryReadOnlyScreen extends StatelessWidget {
  const DiaryReadOnlyScreen({
    super.key,
    required this.user,
    required this.diaryService,
    required this.date,
  });

  final AppUser user;
  final DiaryService diaryService;
  final DateTime date;

  @override
  Widget build(BuildContext context) {
    final DiaryEntry entry = diaryService.getOrCreateEntry(user, date);

    return Scaffold(
      backgroundColor: _AppColors.background,
      appBar: AppBar(
        title: Text('Дневник: ${_formatDate(entry.date)}'),
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
      ),
      body: Column(
        children: <Widget>[
          Expanded(
            child: Container(
              margin: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _AppColors.cardStrong,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: _AppColors.border),
              ),
              child: Markdown(
                padding: const EdgeInsets.all(16),
                data: entry.markdown.trim().isEmpty
                    ? '_Запись пустая._'
                    : entry.markdown,
              ),
            ),
          ),
          SafeArea(
            top: false,
            minimum: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: entry.isClosed
                    ? () {
                        Navigator.of(context).push(
                          MaterialPageRoute<DiaryAiChatScreen>(
                            builder: (BuildContext context) {
                              return DiaryAiChatScreen(
                                user: user,
                                diaryService: diaryService,
                                date: entry.date,
                              );
                            },
                          ),
                        );
                      }
                    : null,
                style: FilledButton.styleFrom(
                  backgroundColor: _AppColors.mint,
                  foregroundColor: const Color(0xFF2F8F89),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                ),
                icon: const Icon(Icons.chat_bubble_outline),
                label: const Text('Открыть ИИ-чат этого дня'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class DiaryAiChatScreen extends StatefulWidget {
  const DiaryAiChatScreen({
    super.key,
    required this.user,
    required this.diaryService,
    required this.date,
  });

  final AppUser user;
  final DiaryService diaryService;
  final DateTime date;

  @override
  State<DiaryAiChatScreen> createState() => _DiaryAiChatScreenState();
}

class _DiaryAiChatScreenState extends State<DiaryAiChatScreen> {
  late DiaryEntry _entry;
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isSending = false;
  bool _isLoading = true;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _entry = widget.diaryService.getOrCreateEntry(widget.user, widget.date);
    unawaited(_loadChatContext());
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _sendMessage() async {
    final String text = _messageController.text.trim();
    if (text.isEmpty || _isSending) {
      return;
    }

    setState(() {
      _isSending = true;
    });

    _messageController.clear();
    await widget.diaryService.sendChatMessage(
      user: widget.user,
      date: widget.date,
      text: text,
    );

    if (!mounted) {
      return;
    }

    setState(() {
      _isSending = false;
      _entry = widget.diaryService.getOrCreateEntry(widget.user, widget.date);
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) {
        return;
      }
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent + 120,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  void _saveChatState() {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Состояние чата сохранено')));
  }

  Future<void> _loadChatContext() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    try {
      _entry = await widget.diaryService.refreshEntry(widget.user, widget.date);
    } catch (error) {
      _loadError = _userMessage(error);
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              if (_isLoading) const LinearProgressIndicator(minHeight: 2),
              Row(
                children: <Widget>[
                  _BackButtonBox(onTap: () => Navigator.of(context).pop()),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'ИИ чат',
                      style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w700,
                        color: _AppColors.textPrimary,
                      ),
                    ),
                  ),
                  _RoundInfoBadge(
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Позже сюда подключим отдельную backend-ручку итогов и метрик.',
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
              if (_loadError != null) ...<Widget>[
                const SizedBox(height: 8),
                _SyncStateBanner(
                  message: _loadError!,
                  actionLabel: 'Обновить',
                  onAction: _loadChatContext,
                ),
              ],
              const SizedBox(height: 10),
              Expanded(
                child: _SurfaceCard(
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    children: <Widget>[
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            color: _AppColors.mutedSurface,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: _entry.chatMessages.isEmpty
                              ? Center(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: <Widget>[
                                      Image.asset(
                                        _AppAssets.iconSmile,
                                        width: 32,
                                        height: 32,
                                      ),
                                      const SizedBox(height: 8),
                                      const Text(
                                        'Пиши в формате Markdown',
                                        style: TextStyle(
                                          color: _AppColors.textMuted,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                )
                              : ListView.builder(
                                  controller: _scrollController,
                                  padding: const EdgeInsets.all(12),
                                  itemCount: _entry.chatMessages.length,
                                  itemBuilder:
                                      (BuildContext context, int index) {
                                        final ChatMessage message =
                                            _entry.chatMessages[index];
                                        return _ChatBubble(message: message);
                                      },
                                ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: _AppColors.cardStrong,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: _AppColors.border),
                        ),
                        child: Row(
                          children: <Widget>[
                            Expanded(
                              child: TextField(
                                controller: _messageController,
                                textInputAction: TextInputAction.send,
                                onSubmitted: (_) => _sendMessage(),
                                decoration: const InputDecoration(
                                  hintText: 'Расскажите о состоянии',
                                  hintStyle: TextStyle(
                                    fontSize: 12,
                                    color: _AppColors.textMuted,
                                  ),
                                  border: InputBorder.none,
                                  isDense: true,
                                ),
                              ),
                            ),
                            Image.asset(
                              _AppAssets.iconImage,
                              width: 18,
                              height: 18,
                            ),
                            const SizedBox(width: 10),
                            Image.asset(
                              _AppAssets.iconMic,
                              width: 18,
                              height: 18,
                            ),
                            const SizedBox(width: 10),
                            InkWell(
                              onTap: _isSending ? null : _sendMessage,
                              borderRadius: BorderRadius.circular(14),
                              child: Container(
                                width: 24,
                                height: 24,
                                decoration: const BoxDecoration(
                                  color: Color(0xFFD4D4DA),
                                  shape: BoxShape.circle,
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(5),
                                  child: ColorFiltered(
                                    colorFilter: const ColorFilter.mode(
                                      Colors.white,
                                      BlendMode.srcIn,
                                    ),
                                    child: Image.asset(_AppAssets.iconAiChat),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _saveChatState,
                  style: FilledButton.styleFrom(
                    backgroundColor: _AppColors.mint,
                    foregroundColor: const Color(0xFF2F8F89),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                  ),
                  icon: const Icon(Icons.save_outlined, size: 16),
                  label: const Text('Сохранить'),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => Navigator.of(context).pop(),
                  style: FilledButton.styleFrom(
                    backgroundColor: _AppColors.mint,
                    foregroundColor: const Color(0xFF2F8F89),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                  ),
                  icon: const Icon(Icons.article_outlined, size: 16),
                  label: const Text('Вернуться в дневник'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChatBubble extends StatelessWidget {
  const _ChatBubble({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final bool isUser = message.author == ChatAuthor.user;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(10),
        constraints: const BoxConstraints(maxWidth: 320),
        decoration: BoxDecoration(
          color: isUser ? const Color(0xFFDDF2F0) : _AppColors.cardStrong,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _AppColors.border),
        ),
        child: MarkdownBody(data: message.text),
      ),
    );
  }
}

class DashboardPlaceholderScreen extends StatelessWidget {
  const DashboardPlaceholderScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _AppColors.background,
      appBar: AppBar(
        title: const Text('Дашборды'),
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
      ),
      body: const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Здесь будут дашборды ментального здоровья.\n'
            'Пока это заглушка-кнопка, как договорились.',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}

String _formatDate(DateTime date) {
  const List<String> monthNames = <String>[
    'января',
    'февраля',
    'марта',
    'апреля',
    'мая',
    'июня',
    'июля',
    'августа',
    'сентября',
    'октября',
    'ноября',
    'декабря',
  ];
  return '${date.day} ${monthNames[date.month - 1]} ${date.year}';
}

String _formatDayMonth(DateTime date) {
  const List<String> monthNames = <String>[
    'января',
    'февраля',
    'марта',
    'апреля',
    'мая',
    'июня',
    'июля',
    'августа',
    'сентября',
    'октября',
    'ноября',
    'декабря',
  ];
  return '${date.day} ${monthNames[date.month - 1]}';
}

String _formatShortDate(DateTime date) {
  const List<String> monthShort = <String>[
    'янв.',
    'фев.',
    'мар.',
    'апр.',
    'мая',
    'июн.',
    'июл.',
    'авг.',
    'сен.',
    'окт.',
    'ноя.',
    'дек.',
  ];
  return '${date.day} ${monthShort[date.month - 1]}';
}

String _markdownSnippet(String markdown) {
  final String cleaned = markdown
      .replaceAll(RegExp(r'[#*_`>\-\[\]\(\)]'), '')
      .replaceAll('\n', ' ')
      .trim();
  if (cleaned.isEmpty) {
    return 'Пустая запись';
  }
  if (cleaned.length <= 90) {
    return cleaned;
  }
  return '${cleaned.substring(0, 90)}...';
}
