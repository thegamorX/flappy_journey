
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:games_services/games_services.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await MobileAds.instance.initialize();
  runApp(const FlappyApp());
}

class FlappyApp extends StatelessWidget {
  const FlappyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Flappy Journey',
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.blue),
      home: const GamePage(),
    );
  }
}

enum GameState { ready, playing, gameOver }

class GamePage extends StatefulWidget {
  const GamePage({super.key});
  @override
  State<GamePage> createState() => _GamePageState();
}

class _GamePageState extends State<GamePage> with SingleTickerProviderStateMixin {
  static const gravity = 2400.0;
  static const flapImpulse = -760.0;
  static const birdRadius = 18.0;
  static const groundH = 84.0;
  static const pipeW = 74.0;
  static const pipeSpacing = 240.0;
  static const gapBase = 180.0;
  static const gapMin = 120.0;
  static const speedBase = 170.0;

  static const bannerId = 'ca-app-pub-3940256099942544/6300978111';
  static const interstitialId = 'ca-app-pub-3940256099942544/1033173712';
  static const rewardedId = 'ca-app-pub-3940256099942544/5224354917';
  static const leaderboardId = 'CgkIxxxxxxxxEAIQAQ';

  late final Ticker _ticker;
  double _lastT = 0;
  GameState state = GameState.ready;

  Size world = Size.zero;
  double bx = 110, by = 0, vy = 0;
  final rnd = Random();

  final List<double> pipeX = [];
  final List<double> pipeGapY = [];
  final Set<int> passed = {};
  int score = 0, best = 0;
  double difficulty = 0;
  int gameOvers = 0;

  BannerAd? banner;
  InterstitialAd? inter;
  RewardedAd? reward;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_tick);
    _loadAds();
    _signIn();
  }

  void _signIn() async { try { await GamesServices.signIn(); } catch (_) {} }
  void _submitScore() async { try { await GamesServices.submitScore(score: Score(androidLeaderboardID: leaderboardId, value: best)); } catch (_) {} }

  void _loadAds() {
    banner = BannerAd(adUnitId: bannerId, size: AdSize.banner, request: const AdRequest(), listener: const BannerAdListener())..load();
    InterstitialAd.load(adUnitId: interstitialId, request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(onAdLoaded: (a){ inter=a; }, onAdFailedToLoad: (_){ inter=null; }));
    RewardedAd.load(adUnitId: rewardedId, request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(onAdLoaded: (a){ reward=a; }, onAdFailedToLoad: (_){ reward=null; }));
  }

  void _primeWorld() {
    if (pipeX.isNotEmpty) return;
    for (int i=0;i<6;i++) {
      pipeX.add(world.width + i*pipeSpacing);
      pipeGapY.add(_randGapY());
    }
  }

  double _randGapY() {
    final top = 140.0, bottom = world.height - groundH - 140.0;
    return top + rnd.nextDouble()*(bottom-top);
  }

  void _start() {
    state = GameState.playing;
    score = 0; difficulty = 0; passed.clear();
    by = world.height*0.5; vy = 0;
    pipeX..clear(); pipeGapY..clear();
    for (int i=0;i<6;i++) { pipeX.add(world.width + i*pipeSpacing); pipeGapY.add(_randGapY()); }
    _lastT = 0;
    _ticker.start();
    setState((){});
  }

  void _gameOver() {
    state = GameState.gameOver;
    _ticker.stop();
    gameOvers++;
    if (score > best) { best = score; _submitScore(); }
    if (gameOvers % 2 == 0 && inter != null) {
      inter!.fullScreenContentCallback = FullScreenContentCallback(onAdDismissedFullScreenContent: (ad){ ad.dispose(); inter=null; InterstitialAd.load(adUnitId: interstitialId, request: const AdRequest(), adLoadCallback: InterstitialAdLoadCallback(onAdLoaded:(a){inter=a;}, onAdFailedToLoad:(_){inter=null;})); });
      inter!.show();
    }
    setState((){});
  }

  void _flap() {
    if (state == GameState.ready) { _start(); return; }
    if (state == GameState.gameOver) { _start(); return; }
    if (state != GameState.playing) return;
    vy = flapImpulse;
  }

  void _continueWithAd() {
    if (state != GameState.gameOver || reward == null) return;
    final r = reward!;
    r.fullScreenContentCallback = FullScreenContentCallback(onAdDismissedFullScreenContent: (_){ RewardedAd.load(adUnitId: rewardedId, request: const AdRequest(), rewardedAdLoadCallback: RewardedAdLoadCallback(onAdLoaded:(a){reward=a;}, onAdFailedToLoad:(_){reward=null;})); });
    r.show(onUserEarnedReward: (_, __) {
      state = GameState.playing;
      vy = -200;
      _ticker.start();
      setState((){});
    });
  }

  void _tick(Duration elapsed) {
    final t = elapsed.inMicroseconds/1e6;
    final dt = _lastT==0?0:(t-_lastT);
    _lastT = t;
    if (dt==0 || state!=GameState.playing) return;

    final speed = speedBase + (difficulty*14).clamp(0, 140);
    final gapNow = (gapBase - difficulty*8).clamp(gapMin, gapBase);

    vy += gravity*dt;
    by += vy*dt;

    for (var i=0;i<pipeX.length;i++) { pipeX[i] -= speed*dt; }
    for (var i=0;i<pipeX.length;i++) {
      if (pipeX[i] < -pipeW) {
        final maxX = pipeX.reduce(max);
        pipeX[i] = maxX + pipeSpacing;
        pipeGapY[i] = _randGapY();
        passed.remove(i);
      }
    }
    for (var i=0;i<pipeX.length;i++) {
      final centerX = pipeX[i] + pipeW/2;
      if (!passed.contains(i) && bx > centerX) {
        passed.add(i); score++; difficulty = score/10.0;
      }
    }

    if (by-birdRadius < 0 || by+birdRadius > world.height-groundH) { _gameOver(); return; }
    for (var i=0;i<pipeX.length;i++) {
      final x = pipeX[i];
      final gapC = pipeGapY[i];
      final gapTop = gapC - 160/2;
      final gapBot = gapC + 160/2;
      final left = x, right = x+pipeW;
      final birdLeft = bx-birdRadius, birdRight = bx+birdRadius;
      final overlapX = birdRight>left && birdLeft<right;
      final inGap = by>gapTop && by<gapBot;
      if (overlapX && !inGap) { _gameOver(); return; }
    }

    setState((){});
  }

  @override
  void dispose() {
    _ticker.dispose();
    banner?.dispose(); inter?.dispose(); reward?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      world = Size(c.maxWidth, c.maxHeight);
      if (by==0) by = world.height*0.5;
      _primeWorld();
      return GestureDetector(
        onTap: _flap,
        child: Scaffold(
          bottomNavigationBar: state==GameState.ready && banner!=null ? SizedBox(height: 50, child: AdWidget(ad: banner!)) : null,
          body: Stack(
            children: [
              CustomPaint(
                painter: _Painter(
                  state: state, size: world, bird: Offset(bx,by), r: birdRadius,
                  pipes: List.generate(pipeX.length, (i)=>_Pipe(pipeX[i], pipeGapY[i])),
                  pipeW: pipeW, score: score, best: best, groundH: groundH),
                child: const SizedBox.expand(),
              ),
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(state==GameState.playing? '$score' : 'Best: $best',
                        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white)),
                      Row(children: [
                        IconButton(onPressed: (){}, icon: const Icon(Icons.help_outline,color: Colors.white)),
                        IconButton(onPressed: (){ if (state==GameState.gameOver) _start(); }, icon: const Icon(Icons.refresh,color: Colors.white)),
                      ])
                    ],
                  ),
                ),
              ),
              if (state==GameState.ready) _center('Flappy Journey','Tap to start'),
              if (state==GameState.gameOver) _gameOverUI(),
            ],
          ),
        ),
      );
    });
  }

  Widget _center(String t, String s) => Center(
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(color: Colors.black.withOpacity(0.35), borderRadius: BorderRadius.circular(14)),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(t, style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: Colors.white)),
        const SizedBox(height: 6),
        Text(s, style: const TextStyle(fontSize: 16, color: Colors.white70)),
      ]),
    ),
  );

  Widget _gameOverUI() => Center(
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(color: Colors.black.withOpacity(0.35), borderRadius: BorderRadius.circular(14)),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('Game Over', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: Colors.white)),
        const SizedBox(height: 8),
        Text('Score $score  •  Best $best', style: const TextStyle(color: Colors.white70)),
        const SizedBox(height: 12),
        Row(mainAxisSize: MainAxisSize.min, children: [
          FilledButton(onPressed: _start, child: const Text('Play again')),
          const SizedBox(width: 12),
          FilledButton(onPressed: reward!=null ? _continueWithAd : null, child: const Text('Continue (Ad)')),
        ]),
      ]),
    ),
  );
}

class _Pipe { final double x; final double gapY; const _Pipe(this.x, this.gapY); }

class _Painter extends CustomPainter {
  final GameState state;
  final Size size;
  final Offset bird;
  final double r;
  final List<_Pipe> pipes;
  final double pipeW;
  final int score, best;
  final double groundH;

  _Painter({
    required this.state, required this.size, required this.bird, required this.r,
    required this.pipes, required this.pipeW, required this.score, required this.best, required this.groundH,
  });

  @override
  void paint(Canvas c, Size s) {
    final sky = Paint()..shader = const LinearGradient(
      colors: [Color(0xFF87CEEB), Color(0xFFB3E5FC)],
      begin: Alignment.topCenter, end: Alignment.bottomCenter).createShader(Rect.fromLTWH(0, 0, s.width, s.height));
    c.drawRect(Rect.fromLTWH(0, 0, s.width, s.height), sky);

    final hill = Paint()..color = const Color(0xFF9AD1F5).withOpacity(0.7);
    c.drawCircle(Offset(s.width*0.2, s.height*0.85), 160, hill);
    c.drawCircle(Offset(s.width*0.6, s.height*0.8), 220, hill);
    c.drawCircle(Offset(s.width*0.95, s.height*0.87), 140, hill);

    final topP = Paint()..color = const Color(0xFF3CB371);
    final botP = Paint()..color = const Color(0xFF2E8B57);
    const Radius rad = Radius.circular(8);

    for (final p in pipes) {
      const drawGap = 160.0;
      final gapTop = p.gapY - drawGap/2;
      final gapBot = p.gapY + drawGap/2;
      final topRect = RRect.fromRectAndCorners(Rect.fromLTWH(p.x, 0, pipeW, gapTop.clamp(0, s.height - groundH)), topLeft: rad, topRight: rad);
      final botRect = RRect.fromRectAndCorners(Rect.fromLTWH(p.x, gapBot, pipeW, (s.height-groundH-gapBot).clamp(0, s.height)), bottomLeft: rad, bottomRight: rad);
      c.drawRRect(topRect, topP);
      c.drawRRect(botRect, botP);
    }

    final ground = Paint()..color = const Color(0xFF795548);
    c.drawRect(Rect.fromLTWH(0, s.height-groundH, s.width, groundH), ground);
    final grass = Paint()..color = const Color(0xFF8BC34A);
    c.drawRect(Rect.fromLTWH(0, s.height-groundH, s.width, 8), grass);

    final birdPaint = Paint()..color = Colors.orangeAccent;
    c.drawCircle(bird, r, birdPaint);
    final eye = Paint()..color = Colors.white;
    final pupil = Paint()..color = Colors.black;
    c.drawCircle(Offset(bird.dx + 6, bird.dy - 6), 5, eye);
    c.drawCircle(Offset(bird.dx + 7, bird.dy - 6), 2.5, pupil);

    final tp = TextPainter(textDirection: TextDirection.ltr);
    tp.text = TextSpan(text: state==GameState.playing? '$score' : 'Best: $best',
      style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white));
    tp.layout();
    tp.paint(c, Offset(s.width/2 - tp.width/2, 12));
  }

  @override
  bool shouldRepaint(covariant _Painter old) => true;
}
