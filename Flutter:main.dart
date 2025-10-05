// StratoSense — single-file demo with gamification + OpenAQ heat overlay
// Tabs: Scan / Profile / Map
// Uses: google_fonts, image_picker, flutter_animate,
//       dotted_border, flutter_map, latlong2, geolocator, http (for OpenAQ)

import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:convert';
import 'dart:ui' show lerpDouble, FontFeature;

import 'package:dotted_border/dotted_border.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_map/flutter_map.dart' as fm;
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarBrightness: Brightness.dark,
    statusBarIconBrightness: Brightness.light,
  ));
  runApp(const CosmicPointsApp());
}

// =================== APP ROOT ===================
class CosmicPointsApp extends StatelessWidget {
  const CosmicPointsApp({super.key});

  @override
  Widget build(BuildContext context) {
    final base = ThemeData.dark(useMaterial3: true);
    final colorScheme = base.colorScheme.copyWith(
      primary: const Color(0xFF8A7CFF),
      secondary: const Color(0xFF00E5FF),
      surface: const Color(0xFF0A0B14),
      background: const Color(0xFF070814),
    );

    return AppStateProvider(
      state: AppState(),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'StratoSense',
        theme: base.copyWith(
          colorScheme: colorScheme,
          scaffoldBackgroundColor: colorScheme.background,
          textTheme: GoogleFonts.spaceGroteskTextTheme(base.textTheme).apply(
            bodyColor: Colors.white,
            displayColor: Colors.white,
          ),
          inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: Colors.white.withOpacity(.06),
            border: _glassBorder,
            enabledBorder: _glassBorder,
            focusedBorder: _glassBorder.copyWith(
              borderSide: const BorderSide(color: Color(0xFF7D6BFF), width: 1.2),
            ),
            hintStyle: TextStyle(color: Colors.white.withOpacity(.62)),
          ),
          elevatedButtonTheme: ElevatedButtonThemeData(
            style: ElevatedButton.styleFrom(
              foregroundColor: Colors.white,
              backgroundColor: const Color(0xFF7D6BFF),
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ),
        home: const CosmicLoginScreen(),
      ),
    );
  }
}

final _glassBorder = OutlineInputBorder(
  borderRadius: BorderRadius.circular(16),
  borderSide: BorderSide(color: Colors.white.withOpacity(.18)),
);

// =================== APP STATE + GAMIFICATION ===================
class AppState extends ChangeNotifier {
  // profile
  bool loggedIn = false;
  String firstName = '';
  String lastName = '';
  File? avatarFile;

  // points / level
  int points = 0;
  int get level => 1 + points ~/ 200;
  int get _currLevelMin => max(0, (level - 1) * 200);
  int get nextLevelAt => level * 200;
  double get levelProgress =>
      (points - _currLevelMin) / max(1, (nextLevelAt - _currLevelMin));

  // gameplay stats
  int uploadsTotal = 0;
  int uploadsFromCamera = 0;
  int tempoRefreshes = 0;

  // daily streak
  int dailyStreak = 0;
  DateTime? lastDailyClaim; // runtime only (demo)
  bool get canClaimDaily =>
      lastDailyClaim == null || !_sameDay(lastDailyClaim!, DateTime.now());

  int get nextDailyReward {
    final nextStreak = (canClaimDaily
        ? (lastDailyClaim == null
        ? 1
        : (_daysBetween(lastDailyClaim!, DateTime.now()) == 1
        ? dailyStreak + 1
        : 1))
        : dailyStreak);
    return 20 + min(nextStreak * 5, 50);
  }

  // quests claimed
  final Map<String, bool> questClaimed = {
    'upload1': false,
    'camera1': false,
    'tempo3': false,
  };

  // achievements
  final Set<String> badges = {}; // 'first_upload', 'lvl3', 'streak3'

  XFile? lastPickedImage;

  // --- helpers ---
  void login({required String first, required String last}) {
    firstName = first.trim();
    lastName = last.trim();
    loggedIn = true;
    notifyListeners();
  }

  void addPoints(int value) {
    points += value;
    _checkBadges();
    notifyListeners();
  }

  void setAvatar(File f) {
    avatarFile = f;
    notifyListeners();
  }

  void setLastPicked(XFile x) {
    lastPickedImage = x;
    avatarFile = File(x.path);
    notifyListeners();
  }

  // gameplay actions
  void rewardUpload({required bool fromCamera}) {
    uploadsTotal++;
    if (fromCamera) uploadsFromCamera++;
    addPoints(50);
    _checkBadges();
  }

  void recordTempoRefresh() {
    tempoRefreshes++;
    notifyListeners();
  }

  bool claimDaily() {
    if (!canClaimDaily) return false;
    final now = DateTime.now();
    if (lastDailyClaim == null) {
      dailyStreak = 1;
    } else {
      final diff = _daysBetween(lastDailyClaim!, now);
      dailyStreak = (diff == 1) ? dailyStreak + 1 : 1;
    }
    lastDailyClaim = now;
    addPoints(20 + min(dailyStreak * 5, 50));
    _checkBadges();
    return true;
  }

  bool isQuestComplete(String id) {
    if (id == 'upload1') return uploadsTotal >= 1;
    if (id == 'camera1') return uploadsFromCamera >= 1;
    if (id == 'tempo3') return tempoRefreshes >= 3;
    return false;
  }

  bool claimQuest(String id) {
    if (questClaimed[id] == true) return false;
    if (!isQuestComplete(id)) return false;
    questClaimed[id] = true;
    addPoints(30);
    return true;
  }

  // badges auto
  void _checkBadges() {
    if (uploadsTotal >= 1) badges.add('first_upload');
    if (level >= 3) badges.add('lvl3');
    if (dailyStreak >= 3) badges.add('streak3');
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static int _daysBetween(DateTime a, DateTime b) =>
      DateTime(b.year, b.month, b.day)
          .difference(DateTime(a.year, a.month, a.day))
          .inDays;
}

class AppStateProvider extends InheritedNotifier<AppState> {
  final AppState state;
  const AppStateProvider({super.key, required this.state, required super.child})
      : super(notifier: state);

  static AppState of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppStateProvider>()!.state;
}

// =================== LOGIN SCREEN ===================
class CosmicLoginScreen extends StatefulWidget {
  const CosmicLoginScreen({super.key});
  @override
  State<CosmicLoginScreen> createState() => _CosmicLoginScreenState();
}

class _CosmicLoginScreenState extends State<CosmicLoginScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _firstCtrl = TextEditingController();
  final _lastCtrl = TextEditingController();
  late AnimationController _bgAnim;

  @override
  void initState() {
    super.initState();
    _bgAnim =
    AnimationController(vsync: this, duration: const Duration(seconds: 10))
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _bgAnim.dispose();
    _firstCtrl.dispose();
    _lastCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = AppStateProvider.of(context);
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        body: Stack(
          children: [
            const CosmicBackground(),
            AnimatedBuilder(
              animation: _bgAnim,
              builder: (context, _) {
                return Align(
                  alignment:
                  Alignment(lerpDouble(-0.6, 0.6, _bgAnim.value)!, -0.9),
                  child: _neonOrb(
                      220, const Color(0xFF7D6BFF).withOpacity(.28)),
                );
              },
            ),
            const Positioned.fill(child: AnimatedStarfield()),
            Center(
              child: Padding(
                padding: const EdgeInsets.all(22),
                child: GlassContainer(
                  padding: const EdgeInsets.all(22),
                  borderRadius: 24,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.blur_on,
                                  size: 28, color: Colors.white70),
                              const SizedBox(width: 8),
                              Text('StratoSense',
                                  style: GoogleFonts.orbitron(
                                    fontSize: 20,
                                    letterSpacing: 3,
                                    fontWeight: FontWeight.w600,
                                  )),
                            ],
                          )
                              .animate()
                              .fadeIn(duration: 600.ms)
                              .slideY(begin: .2, end: 0),
                          const SizedBox(height: 18),
                          Text('Добро пожаловать',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.spaceGrotesk(
                                  fontSize: 30,
                                  fontWeight: FontWeight.w700)),
                          const SizedBox(height: 18),
                          TextFormField(
                            controller: _firstCtrl,
                            textInputAction: TextInputAction.next,
                            decoration: const InputDecoration(
                              hintText: 'Имя',
                              prefixIcon: Icon(Icons.person_outline),
                            ),
                            validator: (v) => (v == null ||
                                v.trim().length < 2)
                                ? 'Введите имя'
                                : null,
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _lastCtrl,
                            textInputAction: TextInputAction.done,
                            decoration: const InputDecoration(
                              hintText: 'Фамилия',
                              prefixIcon: Icon(Icons.badge_outlined),
                            ),
                            validator: (v) => (v == null ||
                                v.trim().length < 2)
                                ? 'Введите фамилию'
                                : null,
                          ),
                          const SizedBox(height: 20),
                          ElevatedButton.icon(
                            icon: const Icon(Icons.login),
                            label: const Text('Войти'),
                            onPressed: () {
                              if (_formKey.currentState!.validate()) {
                                state.login(
                                  first: _firstCtrl.text,
                                  last: _lastCtrl.text,
                                );
                                Navigator.of(context).pushReplacement(
                                  PageRouteBuilder(
                                    transitionDuration:
                                    const Duration(milliseconds: 700),
                                    pageBuilder: (_, __, ___) =>
                                    const ShellScreen(),
                                    transitionsBuilder:
                                        (_, anim, __, child) =>
                                        FadeTransition(
                                            opacity: anim, child: child),
                                  ),
                                );
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =================== SHELL WITH TABS ===================
class ShellScreen extends StatefulWidget {
  const ShellScreen({super.key});
  @override
  State<ShellScreen> createState() => _ShellScreenState();
}

class _ShellScreenState extends State<ShellScreen> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final pages = [const ScanPage(), const ProfilePage(), const MapPage()];
    return Scaffold(
      body: Stack(children: [
        const CosmicBackground(),
        const Positioned.fill(child: AnimatedStarfield()),
        AnimatedSwitcher(
            duration: const Duration(milliseconds: 500), child: pages[_index]),
      ]),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: GlassContainer(
          padding:
          const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          borderRadius: 18,
          child: NavigationBar(
            selectedIndex: _index,
            onDestinationSelected: (i) => setState(() => _index = i),
            indicatorColor: Colors.white.withOpacity(.08),
            backgroundColor: Colors.transparent,
            destinations: const [
              NavigationDestination(
                  icon: Icon(Icons.add_a_photo_outlined), label: 'Скан'),
              NavigationDestination(
                  icon: Icon(Icons.person_outline), label: 'Профиль'),
              NavigationDestination(
                  icon: Icon(Icons.map_outlined), label: 'Карта'),
            ],
          ),
        ),
      ),
    );
  }
}

// =================== SCAN PAGE ===================
class ScanPage extends StatefulWidget {
  const ScanPage({super.key});
  @override
  State<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<ScanPage> {
  final ImagePicker _picker = ImagePicker();
  XFile? _selected;
  bool _processing = false;
  bool _fromCamera = false;

  @override
  Widget build(BuildContext context) {
    final state = AppStateProvider.of(context);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 96),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Text('Отправка изображения',
                  style: GoogleFonts.spaceGrotesk(
                      fontSize: 24, fontWeight: FontWeight.w700)),
            ).animate().fadeIn(duration: 450.ms, curve: Curves.easeOut),
            const SizedBox(height: 8),
            // gamified chips
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _statChip(Icons.auto_awesome, 'Очки',
                    state.points.toString()),
                _statChip(Icons.military_tech, 'Уровень', '${state.level}'),
                _statChip(Icons.local_fire_department, 'Стрик',
                    '${state.dailyStreak}'),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: GlassContainer(
                borderRadius: 22,
                padding: const EdgeInsets.all(16),
                child: InkWell(
                  onTap: _pickFromGallery,
                  borderRadius: BorderRadius.circular(20),
                  child: DottedBorder(
                    borderType: BorderType.RRect,
                    radius: const Radius.circular(18),
                    dashPattern: const [8, 6],
                    color: Colors.white.withOpacity(.28),
                    strokeWidth: 1.2,
                    child: Container(
                      width: double.infinity,
                      height: double.infinity,
                      alignment: Alignment.center,
                      padding: const EdgeInsets.all(16),
                      child: _selected == null
                          ? Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.image_outlined, size: 72),
                          const SizedBox(height: 12),
                          Text(
                            'Нажмите, чтобы выбрать изображение',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                color: Colors.white.withOpacity(.8)),
                          ),
                        ],
                      )
                          : ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Image.file(File(_selected!.path),
                            fit: BoxFit.cover),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _CosmicButton(
                    icon: Icons.photo_library_outlined,
                    label: 'Галерея',
                    onPressed: _pickFromGallery,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _CosmicButton(
                    icon: Icons.photo_camera_outlined,
                    label: 'Камера',
                    onPressed: _pickFromCamera,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ElevatedButton(
              onPressed: (_selected != null && !_processing)
                  ? () => _send(context)
                  : null,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  Icon(Icons.rocket_launch_outlined),
                  SizedBox(width: 8),
                  Text('Отправить'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Widget _statChip(IconData i, String t, String v) => Chip(
    backgroundColor: Colors.white.withOpacity(.08),
    avatar: Icon(i, size: 18),
    label: Text('$t: $v'),
  );

  Future<void> _pickFromGallery() async {
    try {
      final x = await _picker.pickImage(
          source: ImageSource.gallery, imageQuality: 85);
      if (x != null) {
        setState(() {
          _selected = x;
          _fromCamera = false;
        });
      }
    } catch (e) {
      _showSnack('Не удалось открыть галерею');
    }
  }

  Future<void> _pickFromCamera() async {
    try {
      final x = await _picker.pickImage(
          source: ImageSource.camera, imageQuality: 85);
      if (x != null) {
        setState(() {
          _selected = x;
          _fromCamera = true;
        });
      }
    } catch (e) {
      _showSnack('Не удалось открыть камеру');
    }
  }

  // мгновенное начисление очков, без диалогов
  Future<void> _send(BuildContext context) async {
    final state = AppStateProvider.of(context);
    setState(() => _processing = true);

    final oldLevel = state.level;
    state.rewardUpload(fromCamera: _fromCamera);

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Изображение принято: +50 баллов')),
    );
    if (state.level > oldLevel) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Новый уровень: ${state.level}!')),
      );
    }

    // опционально сбрасываем выбранное изображение
    setState(() {
      _selected = null;
      _processing = false;
    });
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }
}

class _CosmicButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  const _CosmicButton(
      {required this.icon, required this.label, this.onPressed});

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.white.withOpacity(.08),
        elevation: 0,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon),
          const SizedBox(width: 8),
          Text(label),
        ],
      ),
    );
  }
}

// =================== PROFILE PAGE ===================
class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppStateProvider.of(context);

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 120),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Профиль',
                style: GoogleFonts.spaceGrotesk(
                    fontSize: 26, fontWeight: FontWeight.w700)),
            const SizedBox(height: 16),

            // User + Level
            GlassContainer(
              borderRadius: 22,
              padding: const EdgeInsets.all(18),
              child: Row(
                children: [
                  _Avatar(size: 72, file: state.avatarFile),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${state.firstName} ${state.lastName}',
                            style: const TextStyle(
                                fontSize: 20, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 6),
                        Row(children: [
                          const Icon(Icons.auto_awesome,
                              size: 18, color: Colors.white70),
                          const SizedBox(width: 6),
                          Text('Баллы: ${state.points}',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600)),
                        ]),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            const Icon(Icons.military_tech, size: 18),
                            const SizedBox(width: 6),
                            Text('Уровень ${state.level}'),
                          ],
                        ),
                        const SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: LinearProgressIndicator(
                            value: state.levelProgress.clamp(0, 1),
                            minHeight: 8,
                            color: const Color(0xFF00E5FF),
                            backgroundColor:
                            Colors.white.withOpacity(.12),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                            'До след. уровня: ${state.nextLevelAt - state.points} оч.',
                            style: TextStyle(
                                color: Colors.white.withOpacity(.8),
                                fontSize: 12)),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 14),

            // Daily streak
            GlassContainer(
              borderRadius: 22,
              padding: const EdgeInsets.all(18),
              child: Row(
                children: [
                  const Icon(Icons.local_fire_department,
                      size: 28, color: Colors.orangeAccent),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Ежедневная комета',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w700)),
                        Text(
                            'Стрик: ${state.dailyStreak}  ·  Награда сегодня: +${state.nextDailyReward}'),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: state.canClaimDaily
                        ? () {
                      final old = state.level;
                      if (state.claimDaily()) {
                        if (state.level > old) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                                content: Text(
                                    'Новый уровень: ${state.level}!')),
                          );
                        }
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text('Бонус получен!')),
                        );
                      }
                    }
                        : null,
                    child: const Text('Забрать'),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 14),

            // Quests
            GlassContainer(
              borderRadius: 22,
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Квесты дня',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 10),
                  _QuestTile(
                    title: 'Новобранец',
                    subtitle: 'Отправьте 1 изображение',
                    progress: min(1.0, state.uploadsTotal / 1.0),
                    label: '${min(state.uploadsTotal, 1)}/1',
                    claimed: state.questClaimed['upload1']!,
                    canClaim: state.isQuestComplete('upload1'),
                    onClaim: () {
                      final old = state.level;
                      if (state.claimQuest('upload1') && old < state.level) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                              content:
                              Text('Новый уровень: ${state.level}!')),
                        );
                      }
                    },
                  ),
                  const SizedBox(height: 10),
                  _QuestTile(
                    title: 'Пилот камеры',
                    subtitle: 'Сделайте снимок с камеры',
                    progress: min(1.0, state.uploadsFromCamera / 1.0),
                    label: '${min(state.uploadsFromCamera, 1)}/1',
                    claimed: state.questClaimed['camera1']!,
                    canClaim: state.isQuestComplete('camera1'),
                    onClaim: () {
                      final old = state.level;
                      if (state.claimQuest('camera1') && old < state.level) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                              content:
                              Text('Новый уровень: ${state.level}!')),
                        );
                      }
                    },
                  ),
                  const SizedBox(height: 10),
                  _QuestTile(
                    title: 'Метеоролог',
                    subtitle: 'Обновите TEMPO 3 раза',
                    progress: min(1.0, state.tempoRefreshes / 3.0),
                    label: '${min(state.tempoRefreshes, 3)}/3',
                    claimed: state.questClaimed['tempo3']!,
                    canClaim: state.isQuestComplete('tempo3'),
                    onClaim: () {
                      final old = state.level;
                      if (state.claimQuest('tempo3') && old < state.level) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                              content:
                              Text('Новый уровень: ${state.level}!')),
                        );
                      }
                    },
                  ),
                  const SizedBox(height: 6),
                  const Text('Награда за каждый квест: +30 очков',
                      style: TextStyle(fontSize: 12)),
                ],
              ),
            ),

            const SizedBox(height: 14),

            // Achievements
            GlassContainer(
              borderRadius: 22,
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Достижения',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _badge('first_upload', 'Первый запуск',
                          state.badges.contains('first_upload')),
                      _badge('lvl3', 'Уровень 3+',
                          state.badges.contains('lvl3')),
                      _badge('streak3', 'Стрик ×3',
                          state.badges.contains('streak3')),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 14),

            // Leaderboard
            GlassContainer(
              borderRadius: 22,
              padding: const EdgeInsets.all(18),
              child: _Leaderboard(
                  userPoints: state.points,
                  userName:
                  state.firstName.isEmpty ? 'Вы' : state.firstName),
            ),
          ],
        ),
      ),
    );
  }

  static Widget _badge(String id, String label, bool unlocked) {
    return Opacity(
      opacity: unlocked ? 1 : 0.35,
      child: Container(
        padding:
        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(.06),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withOpacity(.2)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              id == 'first_upload'
                  ? Icons.camera_alt_outlined
                  : id == 'lvl3'
                  ? Icons.military_tech
                  : Icons.local_fire_department,
              size: 18,
            ),
            const SizedBox(width: 6),
            Text(label),
          ],
        ),
      ),
    );
  }
}

class _QuestTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final double progress;
  final String label;
  final bool claimed;
  final bool canClaim;
  final VoidCallback onClaim;

  const _QuestTile({
    required this.title,
    required this.subtitle,
    required this.progress,
    required this.label,
    required this.claimed,
    required this.canClaim,
    required this.onClaim,
  });

  @override
  Widget build(BuildContext context) {
    return GlassContainer(
      borderRadius: 14,
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          const Icon(Icons.flag_circle_outlined, size: 24),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(subtitle,
                    style: TextStyle(
                        color: Colors.white.withOpacity(.8))),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: progress.clamp(0, 1),
                    minHeight: 6,
                    color: const Color(0xFF00E5FF),
                    backgroundColor:
                    Colors.white.withOpacity(.12),
                  ),
                ),
                const SizedBox(height: 4),
                Text(label, style: const TextStyle(fontSize: 12)),
              ],
            ),
          ),
          const SizedBox(width: 10),
          claimed
              ? const Icon(Icons.check_circle,
              color: Colors.lightGreenAccent)
              : ElevatedButton(
            onPressed: canClaim ? onClaim : null,
            child: const Text('Забрать'),
          ),
        ],
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  final double size;
  final File? file;
  const _Avatar({required this.size, this.file});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          colors: [Color(0xFF7D6BFF), Color(0xFF00E5FF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF7D6BFF).withOpacity(.4),
            blurRadius: 22,
            spreadRadius: 2,
          ),
        ],
      ),
      child: ClipOval(
        child: file != null
            ? Image.file(file!, fit: BoxFit.cover)
            : Icon(Icons.person,
            size: size * 0.6,
            color: Colors.white.withOpacity(.9)),
      ),
    );
  }
}

class _Leaderboard extends StatelessWidget {
  final int userPoints;
  final String userName;
  const _Leaderboard(
      {required this.userPoints, required this.userName});

  @override
  Widget build(BuildContext context) {
    final bots = [
      {'name': 'Orion', 'pts': 420},
      {'name': 'Vega', 'pts': 160},
      {'name': 'Nova', 'pts': 260},
      {'name': 'Lyra', 'pts': 560},
      {'name': 'Atlas', 'pts': 310},
    ];
    final list = [...bots, {'name': userName, 'pts': userPoints, 'me': true}];
    list.sort((a, b) =>
        (b['pts'] as int).compareTo(a['pts'] as int));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Лидерборд',
            style:
            TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        ...List.generate(list.length, (i) {
          final e = list[i];
          final me = e['me'] == true;
          return Container(
            margin: const EdgeInsets.symmetric(vertical: 4),
            padding: const EdgeInsets.symmetric(
                horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: me
                  ? Colors.white.withOpacity(.10)
                  : Colors.white.withOpacity(.06),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Text('${i + 1}'.padLeft(2, '0'),
                    style: const TextStyle(
                        fontFeatures: [FontFeature.tabularFigures()])),
                const SizedBox(width: 10),
                Icon(me ? Icons.star : Icons.person, size: 18),
                const SizedBox(width: 8),
                Expanded(child: Text(e['name'] as String)),
                Text('${e['pts']}'),
              ],
            ),
          );
        }),
      ],
    );
  }
}

// =================== MAP PAGE (with Heatmap + OpenAQ) ===================

enum _AirSource { tempo, openaq }
// Цветовая серьёзность для карточки рекомендаций
enum _Severity { green, yellow, red }

// Градиент/иконка/заголовок по уровню серьёзности (top-level, чтобы использовать в карточке)
(LinearGradient, IconData, String) severityStyle(_Severity s) {
  switch (s) {
    case _Severity.green:
      return (
      const LinearGradient(colors: [Color(0xFF2ECC71), Color(0xFF27AE60)]),
      Icons.check_circle,
      'Зелёный уровень'
      );
    case _Severity.yellow:
      return (
      const LinearGradient(colors: [Color(0xFFF1C40F), Color(0xFFF39C12)]),
      Icons.warning_amber_rounded,
      'Жёлтый уровень'
      );
    case _Severity.red:
      return (
      const LinearGradient(colors: [Color(0xFFE74C3C), Color(0xFFC0392B)]),
      Icons.report_rounded,
      'Красный уровень'
      );
  }
}

class MapPage extends StatefulWidget {
  const MapPage({super.key});
  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  LatLng? _center;

  // Map controller (двигаем карту при смене центра)
  late final fm.MapController _mapController;

  // TEMPO (fake) UI
  int? _aqi;
  String _label = '';
  Color _aqiColor = const Color(0xFF2ecc71);
  String _status = 'Определяем позицию…';

  // source mode
  _AirSource _mode = _AirSource.tempo;

  // OpenAQ data
  List<_OpenAqPoint> _openAq = [];
  String _openAqParameter = 'no2';
  double? _nearestValue;
  String? _nearestUnit;

  // OpenAQ heat overlay toggle & grid params
  bool _openAqHeat = true;
  final double _oaCellKm = 1.2; // cell size
  final double _oaRadiusKm = 10; // coverage radius

  // heatmap params (for TEMPO simulation)
  final double _radiusKm = 10;
  final double _cellKm = 1.2;

  // Advice card visibility
  bool _showAdvice = true;

  @override
  void initState() {
    super.initState();
    _mapController = fm.MapController();
    _initLocation();
  }

  void _moveMap(LatLng p) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        _mapController.move(p, 13); // держим зум 13
      } catch (_) {}
    });
  }

  Future<void> _initLocation() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        setState(() => _status = 'Геолокация выключена');
        return;
      }
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        setState(() => _status = 'Нет доступа к геолокации');
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);
      final p = LatLng(pos.latitude, pos.longitude);
      setState(() => _center = p);
      _moveMap(p);
      if (_mode == _AirSource.tempo) {
        _computeAqi();
      } else {
        _fetchOpenAQ();
      }
    } catch (e) {
      setState(() => _status = 'Не удалось получить позицию');
    }
  }

  // ---------- TEMPO (fake) ----------
  void _computeAqi() {
    if (_center == null) return;
    final aqi = _fakeTempoAqi(_center!);
    final cat = _aqiCategory(aqi);
    setState(() {
      _aqi = aqi;
      _label = cat.$1;
      _aqiColor = cat.$2;
      _showAdvice = true; // при обновлении показываем карточку снова
    });
    if (aqi >= 151) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFFC0392B),
          content: const Text(
              'Красный уровень: ограничьте активность на улице, используйте маску.'),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  int _fakeTempoAqi(LatLng p) {
    final v = 90 + 60 * (sin(p.latitude * 0.22) * cos(p.longitude * 0.18));
    return v.clamp(0, 300).round();
  }

  (String, Color) _aqiCategory(int aqi) {
    if (aqi <= 50) return ('Хорошо', const Color(0xFF2ecc71));
    if (aqi <= 100) return ('Умеренно', const Color(0xFFf1c40f));
    if (aqi <= 150) return ('Вредно для чувствительных', const Color(0xFFe67e22));
    if (aqi <= 200) return ('Вредно', const Color(0xFFe74c3c));
    if (aqi <= 300) return ('Очень вредно', const Color(0xFF8e44ad));
    return ('Опасно', const Color(0xFF7f0000));
  }

  Color _aqiRamp(int aqi) {
    final t = (aqi.clamp(0, 300) / 300.0);
    const stops = [0.0, 0.25, 0.5, 0.75, 1.0];
    const cols = [
      Color(0xFF2ECC71),
      Color(0xFFF1C40F),
      Color(0xFFE67E22),
      Color(0xFFE74C3C),
      Color(0xFF8E44AD),
    ];
    int i = 0;
    for (; i < stops.length - 1; i++) {
      if (t <= stops[i + 1]) break;
    }
    final t0 = stops[i], t1 = stops[i + 1];
    final local = (t - t0) / (t1 - t0);
    return Color.lerp(cols[i], cols[i + 1], local)!;
  }

  List<fm.Polygon> _buildHeatPolygons(LatLng center) {
    const kmPerDegLat = 110.574;
    final kmPerDegLng = 111.320 * cos(center.latitude * pi / 180.0);

    final dLat = _cellKm / kmPerDegLat;
    final dLng = _cellKm / kmPerDegLng;
    final latRadius = _radiusKm / kmPerDegLat;
    final lngRadius = _radiusKm / kmPerDegLng;

    final minLat = center.latitude - latRadius;
    final maxLat = center.latitude + latRadius;
    final minLng = center.longitude - lngRadius;
    final maxLng = center.longitude + lngRadius;

    final polys = <fm.Polygon>[];

    for (double lat = minLat; lat < maxLat; lat += dLat) {
      for (double lng = minLng; lng < maxLng; lng += dLng) {
        final cellCenter = LatLng(lat + dLat / 2, lng + dLng / 2);
        final aqi = _fakeTempoAqi(cellCenter);
        final c = _aqiRamp(aqi).withOpacity(0.28);

        polys.add(
          fm.Polygon(
            points: [
              LatLng(lat, lng),
              LatLng(lat + dLat, lng),
              LatLng(lat + dLat, lng + dLng),
              LatLng(lat, lng + dLng),
            ],
            color: c,
            borderColor: c.withOpacity(.35),
            borderStrokeWidth: 0,
          ),
        );
      }
    }
    return polys;
  }

  // ---------- OpenAQ ----------
  Future<void> _fetchOpenAQ() async {
    if (_center == null) return;
    setState(() {
      _status = 'Запрашиваем OpenAQ…';
      _openAq = [];
      _nearestValue = null;
      _nearestUnit = null;
    });

    Future<bool> _load(String parameter) async {
      final uri = Uri.https('api.openaq.org', '/v2/measurements', {
        'coordinates': '${_center!.latitude},${_center!.longitude}',
        'radius': '25000', // 25 км вокруг
        'limit': '100',
        'page': '1',
        'parameter': parameter,
        'order_by': 'datetime',
        'sort': 'desc',
      });
      final r =
      await http.get(uri, headers: {'accept': 'application/json'});
      if (r.statusCode != 200) return false;
      final data = jsonDecode(r.body) as Map<String, dynamic>;
      final results =
      (data['results'] as List).cast<Map<String, dynamic>>();
      if (results.isEmpty) return false;

      final pts = <_OpenAqPoint>[];
      for (final m in results) {
        final coords =
        (m['coordinates'] ?? {}) as Map<String, dynamic>;
        final lat = (coords['latitude'] as num?)?.toDouble();
        final lon = (coords['longitude'] as num?)?.toDouble();
        final val = (m['value'] as num?)?.toDouble();
        final unit = (m['unit'] as String?) ?? '';
        if (lat == null || lon == null || val == null) continue;
        pts.add(_OpenAqPoint(
          p: LatLng(lat, lon),
          value: val,
          unit: unit,
          parameter: (m['parameter'] as String?) ?? parameter,
        ));
      }
      if (pts.isEmpty) return false;

      pts.sort((a, b) =>
          _dist(a.p, _center!).compareTo(_dist(b.p, _center!)));
      final nearest = pts.first;
      final cat = _categoryFromMeasurement(
          nearest.parameter, nearest.value, nearest.unit);

      setState(() {
        _openAq = pts;
        _openAqParameter = parameter;
        _nearestValue = nearest.value;
        _nearestUnit = nearest.unit;
        _label = cat.$1;
        _aqiColor = cat.$2;
        _status = 'OpenAQ данные получены';
        _showAdvice = true; // при новом fetch показываем карточку
      });
      return true;
    }

    // Пробуем NO2, затем PM2.5
    if (!await _load('no2')) {
      await _load('pm25');
    }
  }

  // категории для NO2 (EPA 1h, ppb) и PM2.5 (µg/m³, 24h)
  (String, Color) _categoryFromMeasurement(
      String parameter, double value, String unit) {
    if (parameter.toLowerCase() == 'no2') {
      // привести к ppb
      final ppb = unit.toLowerCase().contains('µg') ||
          unit.toLowerCase().contains('ug')
          ? value / 1.88
          : value;
      if (ppb <= 53) return ('Хорошо', const Color(0xFF2ecc71));
      if (ppb <= 100) return ('Умеренно', const Color(0xFFf1c40f));
      if (ppb <= 360) {
        return ('Вредно для чувствительных', const Color(0xFFe67e22));
      }
      if (ppb <= 649) return ('Вредно', const Color(0xFFe74c3c));
      if (ppb <= 1249) return ('Очень вредно', const Color(0xFF8e44ad));
      return ('Опасно', const Color(0xFF7f0000));
    } else {
      // PM2.5 µg/m³
      final v = value;
      if (v <= 12) return ('Хорошо', const Color(0xFF2ecc71));
      if (v <= 35.4) return ('Умеренно', const Color(0xFFf1c40f));
      if (v <= 55.4) {
        return ('Вредно для чувствительных', const Color(0xFFe67e22));
      }
      if (v <= 150.4) return ('Вредно', const Color(0xFFe74c3c));
      if (v <= 250.4) return ('Очень вредно', const Color(0xFF8e44ad));
      return ('Опасно', const Color(0xFF7f0000));
    }
  }

  double _dist(LatLng a, LatLng b) {
    final d = Distance();
    return d(a, b);
  }

  // Нормализация измерения к 0..1 для единой цветовой шкалы
  double _openaqNorm(String param, double val, String unit) {
    if (param.toLowerCase() == 'no2') {
      final ppb = unit.toLowerCase().contains('µg') ||
          unit.toLowerCase().contains('ug')
          ? val / 1.88
          : val;
      return (ppb / 200.0).clamp(0.0, 1.0);
    } else {
      // pm25
      return (val / 150.0).clamp(0.0, 1.0);
    }
  }

  // Оценка значения в точке по ближайшим измерениям (IDW)
  double? _estimateOpenAq(LatLng at, {int k = 6, double epsKm = 0.05}) {
    if (_openAq.isEmpty) return null;

    final withD = _openAq
        .map((p) => (p, Distance()(p.p, at) / 1000.0))
        .toList() // в км
      ..sort((a, b) => a.$2.compareTo(b.$2));

    if (withD.first.$2 <= epsKm) return withD.first.$1.value;

    double wSum = 0, vSum = 0;
    for (var i = 0; i < min(k, withD.length); i++) {
      final pt = withD[i].$1;
      final dKm = max(withD[i].$2, epsKm);
      final w = 1.0 / (dKm * dKm); // p=2
      wSum += w;
      vSum += w * pt.value;
    }
    if (wSum == 0) return null;
    return vSum / wSum;
  }

  // Построение цветной сетки поверх карты из OpenAQ
  List<fm.Polygon> _buildOpenAqHeatPolygons(LatLng center) {
    const kmPerDegLat = 110.574;
    final kmPerDegLng = 111.320 * cos(center.latitude * pi / 180.0);

    final dLat = _oaCellKm / kmPerDegLat;
    final dLng = _oaCellKm / kmPerDegLng;
    final latRadius = _oaRadiusKm / kmPerDegLat;
    final lngRadius = _oaRadiusKm / kmPerDegLng;

    final minLat = center.latitude - latRadius;
    final maxLat = center.latitude + latRadius;
    final minLng = center.longitude - lngRadius;
    final maxLng = center.longitude + lngRadius;

    final polys = <fm.Polygon>[];

    for (double lat = minLat; lat < maxLat; lat += dLat) {
      for (double lng = minLng; lng < maxLng; lng += dLng) {
        final cellCenter = LatLng(lat + dLat / 2, lng + dLng / 2);
        final est = _estimateOpenAq(cellCenter);
        if (est == null) continue;

        final t =
        _openaqNorm(_openAqParameter, est, _nearestUnit ?? '');
        final color =
        _aqiRamp((t * 300).round()).withOpacity(0.30);

        polys.add(
          fm.Polygon(
            points: [
              LatLng(lat, lng),
              LatLng(lat + dLat, lng),
              LatLng(lat + dLat, lng + dLng),
              LatLng(lat, lng + dLng),
            ],
            color: color,
            borderColor: color.withOpacity(.35),
            borderStrokeWidth: 0,
          ),
        );
      }
    }
    return polys;
  }

  // Маркерный цвет по величине (для режима "точки")
  Color _markerColor(String param, double val, String unit) {
    final t = _openaqNorm(param, val, unit);
    final idx = (t * 300).round();
    return _aqiRamp(idx).withOpacity(0.35);
  }

  // ---- Severity logic + short tips ----
  _Severity _currentSeverity() {
    final lbl = _label.toLowerCase();
    final aqi = _aqi ?? 0;
    if (lbl.contains('опасно') ||
        lbl.contains('очень вредно') ||
        (lbl.contains('вредно') && aqi >= 151)) {
      return _Severity.red;
    }
    if (lbl.contains('умеренно') ||
        lbl.contains('вредно для чувствительных') ||
        (aqi > 50 && aqi <= 150)) {
      return _Severity.yellow;
    }
    return _Severity.green;
  }

  List<String> _adviceFor(_Severity s) {
    switch (s) {
      case _Severity.red:
        return const [
          'Избегать прогулок',
          'Использовать маску (N95/FFP2)',
          'Перенести тренировки'
        ];
      case _Severity.yellow:
        return const [
          'Сократить время на улице',
          'Маска при длительном нахождении',
          'Перенести интенсивные тренировки'
        ];
      case _Severity.green:
        return const ['Можно гулять', 'Нет ограничений'];
    }
  }

  @override
  Widget build(BuildContext context) {
    final fallback = LatLng(51.2279, 51.3865);
    final center = _center ?? fallback;
    final app = AppStateProvider.of(context);

    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
            child: GlassContainer(
              borderRadius: 20,
              padding: const EdgeInsets.all(14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Индикатор цвета
                  Container(
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      color: _aqiColor,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                            color: _aqiColor.withOpacity(.6),
                            blurRadius: 12)
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),

                  // Вся остальная часть тянется и сама переносит строки
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _center == null
                              ? _status
                              : (_mode == _AirSource.tempo
                              ? 'TEMPO • AQI: ${_aqi ?? '—'} — $_label'
                              : 'OpenAQ • ${_openAqParameter.toUpperCase()}: '
                              '${_nearestValue?.toStringAsFixed(1) ?? '—'} ${_nearestUnit ?? ''} — $_label'),
                          style: const TextStyle(
                              fontWeight: FontWeight.w700),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          softWrap: true,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Шир: ${center.latitude.toStringAsFixed(4)}, Долг: ${center.longitude.toStringAsFixed(4)}',
                          style: TextStyle(
                              color: Colors.white.withOpacity(.8)),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 10),

                        // Управления
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            ChoiceChip(
                              label: const Text('TEMPO'),
                              selected: _mode == _AirSource.tempo,
                              onSelected: (v) {
                                if (v) setState(
                                        () => _mode = _AirSource.tempo);
                                _computeAqi();
                              },
                            ),
                            ChoiceChip(
                              label: const Text('OpenAQ'),
                              selected:
                              _mode == _AirSource.openaq,
                              onSelected: (v) async {
                                if (v) {
                                  setState(() =>
                                  _mode = _AirSource.openaq);
                                }
                                await _fetchOpenAQ();
                              },
                            ),
                            if (_mode == _AirSource.openaq)
                              FilterChip(
                                label: const Text('Heat overlay'),
                                selected: _openAqHeat,
                                onSelected: (v) =>
                                    setState(() => _openAqHeat = v),
                              ),
                            ElevatedButton.icon(
                              onPressed: () async {
                                try {
                                  var perm =
                                  await Geolocator.checkPermission();
                                  if (perm ==
                                      LocationPermission.denied ||
                                      perm ==
                                          LocationPermission
                                              .deniedForever) {
                                    perm = await Geolocator
                                        .requestPermission();
                                  }
                                  final pos =
                                  await Geolocator.getCurrentPosition(
                                    desiredAccuracy:
                                    LocationAccuracy.high,
                                  );
                                  final p = LatLng(
                                      pos.latitude, pos.longitude);
                                  setState(() => _center = p);
                                  _moveMap(p);
                                  if (_mode == _AirSource.tempo) {
                                    _computeAqi();
                                  } else {
                                    await _fetchOpenAQ();
                                  }
                                  app.recordTempoRefresh();
                                } catch (_) {
                                  ScaffoldMessenger.of(context)
                                      .showSnackBar(
                                    const SnackBar(
                                        content: Text(
                                            'Не удалось обновить позицию')),
                                  );
                                }
                              },
                              icon: const Icon(Icons.refresh),
                              label: const Text('Обновить'),
                              style: ElevatedButton.styleFrom(
                                minimumSize: const Size(0, 40),
                                padding:
                                const EdgeInsets.symmetric(
                                    horizontal: 12),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Цветовое предупреждение + быстрые советы
          Padding(
            padding:
            const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: _showAdvice
                  ? _AirAdviceCard(
                severity: _currentSeverity(),
                title: _label.isEmpty
                    ? (_center == null
                    ? '—'
                    : 'Оценка качества воздуха')
                    : _label,
                tips: _adviceFor(_currentSeverity()),
                onClose: () =>
                    setState(() => _showAdvice = false),
              )
                  : const SizedBox.shrink(),
            ),
          ),

          Expanded(
            child: Padding(
              padding:
              const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: GlassContainer(
                borderRadius: 20,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: fm.FlutterMap(
                    key: ValueKey(
                      'map_${center.latitude.toStringAsFixed(4)}_${center.longitude.toStringAsFixed(4)}',
                    ),
                    mapController: _mapController,
                    options: fm.MapOptions(
                      initialCenter: center,
                      initialZoom: 13,
                      interactionOptions:
                      const fm.InteractionOptions(),
                    ),
                    children: [
                      fm.TileLayer(
                        urlTemplate:
                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName:
                        'com.example.untitled8',
                        maxZoom: 19,
                      ),

                      // TEMPO heat
                      if (_mode == _AirSource.tempo &&
                          _center != null)
                        fm.PolygonLayer(
                          polygons: _buildHeatPolygons(center),
                          polygonCulling: false,
                        ),

                      // OpenAQ heat overlay
                      if (_mode == _AirSource.openaq &&
                          _openAqHeat &&
                          _openAq.isNotEmpty)
                        fm.PolygonLayer(
                          polygons:
                          _buildOpenAqHeatPolygons(center),
                          polygonCulling: false,
                        ),

                      // OpenAQ points (когда heat отключён)
                      if (_mode == _AirSource.openaq &&
                          !_openAqHeat &&
                          _openAq.isNotEmpty)
                        fm.CircleLayer(
                          circles: _openAq
                              .map((e) => fm.CircleMarker(
                            point: e.p,
                            radius: 12,
                            useRadiusInMeter: false,
                            color: _markerColor(e.parameter,
                                e.value, e.unit),
                            borderColor: _markerColor(
                                e.parameter,
                                e.value,
                                e.unit)
                                .withOpacity(.5),
                            borderStrokeWidth: 0,
                          ))
                              .toList(),
                        ),

                      fm.MarkerLayer(markers: [
                        fm.Marker(
                          point: center,
                          width: 42,
                          height: 42,
                          alignment: Alignment.center,
                          child: _UserMarker(color: _aqiColor),
                        ),
                      ]),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding:
            const EdgeInsets.fromLTRB(16, 6, 16, 96),
            child: Opacity(
              opacity: 1,
              child: GlassContainer(
                borderRadius: 14,
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 10),
                child: Row(
                  children: [
                    Text(
                      _mode == _AirSource.tempo
                          ? 'TEMPO  NO₂'
                          : 'OpenAQ  ${_openAqParameter.toUpperCase()}',
                      style:
                      const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: SizedBox(
                        height: 10,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.all(
                                Radius.circular(8)),
                            gradient: LinearGradient(
                              colors: [
                                Color(0xFF2ECC71),
                                Color(0xFFF1C40F),
                                Color(0xFFE67E22),
                                Color(0xFFE74C3C),
                                Color(0xFF8E44AD),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(_label.isEmpty ? '—' : _label),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OpenAqPoint {
  final LatLng p;
  final double value;
  final String unit;
  final String parameter;
  _OpenAqPoint({
    required this.p,
    required this.value,
    required this.unit,
    required this.parameter,
  });
}

class _UserMarker extends StatelessWidget {
  final Color color;
  const _UserMarker({required this.color});

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        Animate(
          effects: [
            ScaleEffect(
                begin: const Offset(.8, .8),
                end: const Offset(1, 1),
                duration: 300.ms),
            FadeEffect(duration: 600.ms),
            ScaleEffect(
                begin: const Offset(1, 1),
                end: const Offset(1.05, 1.05),
                delay: 200.ms,
                duration: 220.ms),
            ScaleEffect(
                begin: const Offset(1.05, 1.05),
                end: const Offset(1, 1),
                duration: 220.ms),
          ],
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withOpacity(.20),
              boxShadow: [
                BoxShadow(
                    color: color.withOpacity(.6),
                    blurRadius: 18,
                    spreadRadius: 2)
              ],
            ),
          ),
        ),
        Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            border: Border.all(color: color, width: 3),
          ),
        ),
      ],
    );
  }
}

// ---- Advice Card Widget ----
class _AirAdviceCard extends StatelessWidget {
  final _Severity severity;
  final List<String> tips;
  final VoidCallback onClose;
  final String title;
  const _AirAdviceCard({
    required this.severity,
    required this.tips,
    required this.onClose,
    required this.title,
  });

  @override
  Widget build(BuildContext context) {
    final (grad, icon, label) = severityStyle(severity);
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(gradient: grad),
        child: Stack(
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(.06),
                ),
              ),
            ),
            Padding(
              padding:
              const EdgeInsets.fromLTRB(14, 14, 48, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icon, color: Colors.white, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment:
                      CrossAxisAlignment.start,
                      children: [
                        Text('$label • $title',
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                              letterSpacing: .2,
                            )),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: tips.map((t) {
                            return Container(
                              padding:
                              const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 8),
                              decoration: BoxDecoration(
                                color: Colors.black
                                    .withOpacity(.15),
                                border: Border.all(
                                    color: Colors.white
                                        .withOpacity(.25),
                                    width: .8),
                                borderRadius:
                                BorderRadius.circular(22),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.task_alt,
                                      size: 16),
                                  const SizedBox(width: 6),
                                  Text(t,
                                      style: const TextStyle(
                                          fontWeight:
                                          FontWeight.w600)),
                                ],
                              ),
                            );
                          }).toList(),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              top: 6,
              right: 6,
              child: IconButton(
                tooltip: 'Скрыть',
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: onClose,
              ),
            ),
          ],
        ),
      ),
    )
        .animate()
        .fadeIn(duration: 300.ms)
        .slideY(begin: .12, end: 0, curve: Curves.easeOut);
  }
}

// =================== COSMIC BACKGROUND & UTILITIES ===================
class CosmicBackground extends StatelessWidget {
  const CosmicBackground({super.key});

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0B0F26), Color(0xFF0A0B14), Color(0xFF120A24)],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
              top: -120,
              left: -60,
              child:
              _NeonOrb(size: 280, color: Color(0x1F00E5FF))),
          Positioned(
              bottom: -140,
              right: -60,
              child:
              _NeonOrb(size: 320, color: Color(0x297D6BFF))),
        ],
      ),
    );
  }
}

class _NeonOrb extends StatelessWidget {
  final double size;
  final Color color;
  const _NeonOrb({required this.size, required this.color});
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
                color: color,
                blurRadius: size * .6,
                spreadRadius: size * .2)
          ],
        ),
      ),
    );
  }
}

Widget _neonOrb(double size, Color color) =>
    _NeonOrb(size: size, color: color);

class GlassContainer extends StatelessWidget {
  final double borderRadius;
  final EdgeInsetsGeometry padding;
  final Widget child;
  const GlassContainer(
      {super.key,
        this.borderRadius = 20,
        this.padding = EdgeInsets.zero,
        required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(.06),
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(
            color: Colors.white.withOpacity(.16), width: 1),
      ),
      child: ClipRRect(
        borderRadius:
        BorderRadius.circular(borderRadius - 0.5),
        child: Stack(
          children: [
            Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: 1,
                child: Container(
                    color: Colors.white.withOpacity(.06))),
            Padding(padding: padding, child: child),
          ],
        ),
      ),
    );
  }
}

// Animated starfield
class AnimatedStarfield extends StatefulWidget {
  const AnimatedStarfield({super.key});
  @override
  State<AnimatedStarfield> createState() =>
      _AnimatedStarfieldState();
}

class _AnimatedStarfieldState extends State<AnimatedStarfield>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late List<_Star> _stars;
  final _rnd = Random();

  @override
  void initState() {
    super.initState();
    _controller =
    AnimationController(vsync: this, duration: const Duration(seconds: 6))
      ..repeat();
    _stars = List.generate(140, (_) => _Star.random(_rnd));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => CustomPaint(
        painter: _StarfieldPainter(_stars, _controller.value),
        size: Size.infinite,
      ),
    );
  }
}

class _Star {
  final Offset pos;
  final double size;
  final double baseOpacity;
  final double phase;
  final double speed;
  _Star(
      this.pos, this.size, this.baseOpacity, this.phase, this.speed);
  factory _Star.random(Random rnd) => _Star(
    Offset(rnd.nextDouble(), rnd.nextDouble()),
    rnd.nextDouble() * 1.6 + 0.3,
    rnd.nextDouble() * .7 + .2,
    rnd.nextDouble() * pi * 2,
    rnd.nextDouble() * 2 + .6,
  );
}

class _StarfieldPainter extends CustomPainter {
  final List<_Star> stars;
  final double t;
  _StarfieldPainter(this.stars, this.t);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..blendMode = BlendMode.plus;
    for (final s in stars) {
      final x = s.pos.dx * size.width;
      final y = s.pos.dy * size.height;
      final twinkle =
          .5 + .5 * sin((t * 2 * pi * s.speed) + s.phase);
      paint.color = Colors.white.withOpacity(
          (s.baseOpacity * twinkle).clamp(0.0, 1.0));
      canvas.drawCircle(Offset(x, y), s.size, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _StarfieldPainter oldDelegate) =>
      oldDelegate.t != t;
}
