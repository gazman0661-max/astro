import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../game/live_events_config.dart';
import 'planet_merge_screen.dart' show PlanetMergeScreen, MergeMode;
import '../services/ad_service.dart';
import '../services/event_ticket_service.dart';
import '../services/player_progress.dart';
import '../widgets/reward_claim_dialog.dart';
import '../services/network_time_service.dart';
import '../services/localization.dart';
import '../services/sound_service.dart';
import '../services/tutorial_service.dart';
import '../theme/app_colors.dart';
import '../widgets/tutorial_overlay.dart';

/// BOTLU ETKINLIK LIDERLIK TABLOSU — Play Games'in yerini alir (herkese acik
/// Play Games skor tablosu gizli profillerde bos gorunuyordu). Burada veri
/// tamamen yereldir: botlar + oyuncunun kendi etkinlik puani.
///
/// TODO entegrasyon: [_playerScore] su an ornek/placeholder'dir.
///  - cometRace icin: mevcut "Kuyruklu Yildiz" (MergeChallenge comet) basari
///    puanini/skorunu buraya bagla (PlayerProgress'teki ilgili alan).
///  - pointRace icin: biriken 120sn-tur skorlarinin toplamini SharedPreferences'ta
///    'evt_points_<eventId>_v1' anahtari gibi bir yerde tut, burada oku.
class EventLeaderboardScreen extends StatefulWidget {
  /// true: SADECE siralama gosterilir (basliktaki 🏆 ikonu). Bilet, "Oyna",
  /// reklam ve odul talebi yok; bunlar Etkinlik ikonundaki ekranda (false).
  final bool rankingOnly;

  const EventLeaderboardScreen({super.key, this.rankingOnly = false});

  static Future<void> open(BuildContext context,
      {bool rankingOnly = false}) async {
    SoundService.instance.buttonTap();
    await Navigator.of(context).push(
      MaterialPageRoute(
          builder: (_) => EventLeaderboardScreen(rankingOnly: rankingOnly)),
    );
  }

  @override
  State<EventLeaderboardScreen> createState() => _EventLeaderboardScreenState();
}

class _EventLeaderboardScreenState extends State<EventLeaderboardScreen> {
  // Etkinlik dongusunun baslangic ani: ilk kurulumda SABIT bir tarih sec (ornek:
  // uygulamanin yayin tarihi) ve bunu degistirme — degistirirsen tum oyunculardaki
  // "hangi etkinlik su an acik" hesaplamasi kayar.
  static DateTime get _cycleStartUtc => LiveEventDef.cycleStartUtc; // tek kaynak (yerel 10:00)

  Timer? _refresh;
  double _playerScore = 0;

  /// Takimyildizi Savasi: oyuncunun sectigi takim (null = henuz secmedi).
  int? _myTeam;

  // v32: etkinlik ogreticisi (ilk giriste bir kez, etkinlik turu basina).
  final GlobalKey _kInfo = GlobalKey();
  final GlobalKey _kTicket = GlobalKey();
  final GlobalKey _kList = GlobalKey();
  TutorialHandle? _tutHandle;

  /// Listenin sadece ust kismini (ilk birkac satir) parlat; tum ekrani degil.
  static Rect _listHole(Rect r) =>
      Rect.fromLTWH(r.left, r.top, r.width, r.height > 190 ? 190 : r.height);

  bool _hasTarget(GlobalKey k) => k.currentContext != null;

  /// [steps]'i sirayla gosterir; oyuncu "Atla"ya basarsa kalani gosterilmez.
  /// Her tur bir kez gosterilir ([id] kalici isaretlenir).
  Future<void> _runTour(String id, List<TutorialStep> steps) async {
    final tut = TutorialService.instance;
    if (steps.isEmpty || await tut.isSeen(id)) return;
    await tut.markSeen(id);
    for (var i = 0; i < steps.length; i++) {
      if (!mounted) return;
      final st = steps[i];
      final h = TutorialOverlay.show(
        context,
        TutorialStep(
          target: st.target,
          textKey: st.textKey,
          holeBuilder: st.holeBuilder,
          holePadding: st.holePadding,
          counter: '${i + 1}/${steps.length}',
        ),
      );
      _tutHandle = h;
      final skipped = await h.done;
      if (skipped) return;
    }
  }

  Future<void> _maybeEventTour() async {
    if (!mounted || widget.rankingOnly) return;
    if (TutorialService.instance.isActive) return; // ana ogretici surerken karisma
    final now = NetworkTimeService.instance.nowUtc();
    final event = LiveEventDef.current(now, _cycleStartUtc);
    if (!event.isActive(now)) return;
    await Future<void>.delayed(const Duration(milliseconds: 700));
    if (!mounted) return;
    switch (event.kind) {
      case EventKind.cometRace:
        await _runTour('evt_comet', [
          TutorialStep(target: _kInfo, textKey: 'tut_evt_comet'),
          TutorialStep(target: _kList, textKey: 'tut_evt_list', holeBuilder: _listHole),
        ]);
      case EventKind.pointRace:
        await _runTour('evt_point', [
          TutorialStep(target: _kInfo, textKey: 'tut_evt_point'),
          if (_hasTarget(_kTicket)) TutorialStep(target: _kTicket, textKey: 'tut_evt_ticket'),
          TutorialStep(target: _kList, textKey: 'tut_evt_list', holeBuilder: _listHole),
        ]);
      case EventKind.teamWar:
        final picking = _myTeam == null;
        await _runTour('evt_team', [
          TutorialStep(target: _kInfo, textKey: 'tut_evt_team'),
          if (picking)
            TutorialStep(target: _kList, textKey: 'tut_evt_team_pick', holeBuilder: _listHole)
          else ...[
            if (_hasTarget(_kTicket)) TutorialStep(target: _kTicket, textKey: 'tut_evt_ticket'),
            TutorialStep(target: _kList, textKey: 'tut_evt_teamlist', holeBuilder: _listHole),
          ],
        ]);
        // Takim henuz secilmediyse bilet + takim listesi aciklamasi secimden sonra gelir.
        if (!picking) await TutorialService.instance.markSeen('evt_team_after');
    }
  }

  /// Takimyildizi Savasi: takim secildikten sonra bilet + takim listesi turu.
  Future<void> _teamAfterPickTour() async {
    if (!mounted || widget.rankingOnly) return;
    if (TutorialService.instance.isActive) return;
    await Future<void>.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;
    await _runTour('evt_team_after', [
      if (_hasTarget(_kTicket)) TutorialStep(target: _kTicket, textKey: 'tut_evt_ticket'),
      TutorialStep(target: _kList, textKey: 'tut_evt_teamlist', holeBuilder: _listHole),
    ]);
  }

  @override
  void initState() {
    super.initState();
    EventTicketService.instance.addListener(_onTick);
    _refresh = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    final nowInit = NetworkTimeService.instance.nowUtc();
    final event = LiveEventDef.current(nowInit, _cycleStartUtc);
    if (!widget.rankingOnly && event.usesTickets && event.isActive(nowInit)) {
      EventTicketService.instance.ensureStarted(event.id);
    }
    _loadPlayerScore(event.id, event.kind);
    if (!widget.rankingOnly) unawaited(_claimFinishedEvents(event));
    if (!widget.rankingOnly) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _maybeEventTour());
    }
  }

  @override
  void dispose() {
    EventTicketService.instance.removeListener(_onTick);
    _refresh?.cancel();
    _tutHandle?.close();
    super.dispose();
  }

  void _onTick() {
    if (mounted) setState(() {});
  }

  String _fmtDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    if (h > 0) return t('comet_timeHm', {'h': '$h', 'm': '$m'});
    if (m > 0) return t('time_ms', {'m': '$m', 's': '$s'});
    return t('time_s', {'s': '$s'});
  }

  Future<void> _watchAdForTicket(String eventId) async {
    // Gercek odullu reklam: sadece reklam BASARIYLA bitince bilet verilir.
    final granted = await AdService.instance.showRewardedAdFlow(
      context,
      icon: '🎟️',
      title: t('event_ticketAdTitle'),
      placementId: 'event_ticket',
      requireWatch: true, // v24: reklam izlenmeden bilet YOK
    );
    if (granted != true) return;
    final ok = await EventTicketService.instance.grantTicketFromAd(eventId);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t('event_ticketCooldown'))),
      );
    }
  }

  /// Bitmis etkinliklerin (en fazla son 3) odulunu verir. Her etkinlik icin
  /// sadece BIR KEZ ('evt_claimed_<id>_v1'). Katilmayanlara (skor 0) odul yok.
  /// Odulden sonra o etkinligin bilet/bekleme kayitlari temizlenir.
  Future<void> _claimFinishedEvents(LiveEventDef current) async {
    final prefs = await SharedPreferences.getInstance();
    var ev = current;
    for (var i = 0; i < 3; i++) {
      final prev = LiveEventDef.previousOf(ev, _cycleStartUtc); // v29: haftalik takvim
      ev = prev;
      final claimKey = 'evt_claimed_${prev.id}_v1';
      if (prefs.getBool(claimKey) == true) continue;
      if (NetworkTimeService.instance.nowUtc().isBefore(prev.endUtc)) continue;

      final score = _readScore(prefs, prev);

      if (prev.kind == EventKind.teamWar) {
        // Takimyildizi Savasi: TAKIM sirasi odulu + takim ici KISISEL odul.
        final team = prefs.getInt('evt_team_${prev.id}_v1');
        if (score > 0 && team != null) {
          final ts = buildTeamStandings(prev, prev.endUtc, team, score.toDouble());
          final teamRank = ts.indexWhere((x) => x.isPlayerTeam) + 1;
          final members = buildTeamMembers(prev, prev.endUtc, team, score.toDouble());
          final myRank = members.indexWhere((m) => m.isPlayer) + 1;
          EventRewardTier? pick(List<EventRewardTier> l, int rank) {
            for (final r in l) {
              if (rank >= r.minRank && rank <= r.maxRank) return r;
            }
            return null;
          }

          final t1 = pick(LiveEventDef.teamRewards, teamRank);
          final t2 = pick(LiveEventDef.teamPersonalRewards, myRank);
          final meteors = (t1?.meteors ?? 0) + (t2?.meteors ?? 0);
          final n = (t1?.boosters ?? 0) + (t2?.boosters ?? 0);
          final bomb = (n + 2) ~/ 3;
          final swap = (n + 1) ~/ 3;
          final shake = n ~/ 3;
          if (meteors > 0 || n > 0) {
            await PlayerProgress.instance.grantEventReward(
              meteorAmount: meteors,
              bomb: bomb,
              swap: swap,
              shake: shake,
              source: 'live_event_${prev.kind.name}',
            );
            await prefs.setBool(claimKey, true);
            await EventTicketService.instance.resetForNextEvent(prev.id);
            if (!mounted) return;
            await showRewardClaim(
              context,
              title: t('event_teamRewardTitle', {'rank': '$teamRank'}),
              heroIcon: EventTeams.all[team].emoji,
              items: [
                if (meteors > 0) RewardItem('☄️', meteors, t('reward_meteor')),
                if (bomb > 0) RewardItem('💥', bomb, t('power_bomb')),
                if (swap > 0) RewardItem('🔄', swap, t('power_swap')),
                if (shake > 0) RewardItem('🌀', shake, t('power_shake')),
              ],
            );
            continue;
          }
        }
        await prefs.setBool(claimKey, true);
        await EventTicketService.instance.resetForNextEvent(prev.id);
        continue;
      }

      if (score > 0) {
        final standings = buildStandings(prev, prev.endUtc, score.toDouble());
        final rank = standings.indexWhere((s) => s.isPlayer) + 1;
        EventRewardTier? tier;
        for (final r in prev.rewards) {
          if (rank >= r.minRank && rank <= r.maxRank) {
            tier = r;
            break;
          }
        }
        if (tier != null) {
          // boosters -> sil / degistir / salla arasinda sirayla dagitilir.
          final n = tier.boosters;
          final bomb = (n + 2) ~/ 3;
          final swap = (n + 1) ~/ 3;
          final shake = n ~/ 3;
          await PlayerProgress.instance.grantEventReward(
            meteorAmount: tier.meteors,
            bomb: bomb,
            swap: swap,
            shake: shake,
            source: 'live_event_${prev.kind.name}',
          );
          await prefs.setBool(claimKey, true);
          await EventTicketService.instance.resetForNextEvent(prev.id);
          if (!mounted) return;
          await showRewardClaim(
            context,
            title: t('event_rewardTitle', {'rank': '$rank'}),
            heroIcon: '🏆',
            items: [
              if (tier.meteors > 0)
                RewardItem('☄️', tier.meteors, t('reward_meteor')),
              if (bomb > 0) RewardItem('💥', bomb, t('power_bomb')),
              if (swap > 0) RewardItem('🔄', swap, t('power_swap')),
              if (shake > 0) RewardItem('🌀', shake, t('power_shake')),
            ],
          );
          continue;
        }
      }
      // Katilmadi / odul dilimi yok: sadece kapat ve bilet kayitlarini temizle.
      await prefs.setBool(claimKey, true);
      await EventTicketService.instance.resetForNextEvent(prev.id);
    }
  }

  Future<void> _startAttempt(String eventId) async {
    final consumed = await EventTicketService.instance.consumeTicket(eventId);
    if (!consumed) return;
    final result = await Navigator.of(context).push<int>(
      MaterialPageRoute(builder: (_) => const PlanetMergeScreen(mode: MergeMode.pointRace)),
    );
    final gained = result ?? 0;
    if (gained > 0) await _addPointsToEvent(eventId, gained);
    if (mounted) setState(() {}); // siralamayi hemen tazele
    // v24: 3 etkinlik oyununda 1 gecis reklami. Puan kaydedildikten SONRA
    // gosterilir (reklam sirasinda uygulama kapanirsa tur puani kaybolmasin).
    await AdService.instance.notifyEventGameCompleted();
  }

  /// Takimyildizi Savasi turu: 1 bilet harcar (Puan Toplama ile ayni bilet
  /// sistemi). Tur puani takimin toplamina eklenir.
  Future<void> _startTeamAttempt(String eventId) async {
    final consumed = await EventTicketService.instance.consumeTicket(eventId);
    if (!consumed) return;
    final result = await Navigator.of(context).push<int>(
      MaterialPageRoute(builder: (_) => const PlanetMergeScreen(mode: MergeMode.teamWar)),
    );
    final gained = result ?? 0;
    if (gained > 0) {
      final prefs = await SharedPreferences.getInstance();
      final key = 'evt_team_points_${eventId}_v1';
      final total = (prefs.getInt(key) ?? 0) + gained;
      await prefs.setInt(key, total);
      if (mounted) setState(() => _playerScore = total.toDouble());
    }
    if (mounted) setState(() {});
    await AdService.instance.notifyEventGameCompleted();
  }

  Future<void> _pickTeam(LiveEventDef event, EventTeam team) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('${team.emoji} ${t(team.nameKey)}',
            style: const TextStyle(color: AppColors.textPrimary)),
        content: Text(t('evt_teamConfirmBody'),
            style: const TextStyle(color: AppColors.textSecondary)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('shop_buyConfirmCancel'))),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t('evt_join'))),
        ],
      ),
    );
    if (ok != true) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('evt_team_${event.id}_v1', team.index);
    if (mounted) setState(() => _myTeam = team.index);
    WidgetsBinding.instance.addPostFrameCallback((_) => _teamAfterPickTour());
  }

  Widget _buildTeamPicker(LiveEventDef event, DateTime now) {
    final ts = buildTeamStandings(event, now, null, 0);
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(t('evt_pickTeam'),
              style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w900, fontSize: 16)),
        ),
        for (final team in EventTeams.all)
          Builder(builder: (_) {
            final rank = ts.indexWhere((x) => x.team.index == team.index) + 1;
            final score = ts[rank - 1].score;
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Color(team.color), width: 2),
              ),
              child: ListTile(
                onTap: () => _pickTeam(event, team),
                leading: Text(team.emoji, style: const TextStyle(fontSize: 30)),
                title: Text(t(team.nameKey),
                    style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w900)),
                subtitle: Text(t('evt_teamRankNow', {'rank': '$rank', 'score': score.toStringAsFixed(0)}),
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                trailing: const Icon(Icons.chevron_right, color: AppColors.textSecondary),
              ),
            );
          }),
      ],
    );
  }

  Widget _buildTeamBody(LiveEventDef event, DateTime now) {
    final team = _myTeam;
    if (team == null) return _buildTeamPicker(event, now);
    final ts = buildTeamStandings(event, now, team, _playerScore);
    final members = buildTeamMembers(event, now, team, _playerScore);
    final leader = ts.first.score <= 0 ? 1.0 : ts.first.score;
    final memberLeader = members.isNotEmpty && members.first.score > 0 ? members.first.score : 1.0;
    final my = EventTeams.all[team];
    final myRank = members.indexWhere((m) => m.isPlayer) + 1;
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      children: [
        for (var i = 0; i < ts.length; i++) _TeamRow(rank: i + 1, standing: ts[i], leaderScore: leader),
        const SizedBox(height: 6),
        const SizedBox(height: 6),
        Text(t('evt_myTeamLine', {'team': '${my.emoji} ${t(my.nameKey)}', 'score': '${_playerScore.round()}', 'rank': '$myRank'}),
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        for (var i = 0; i < members.length; i++)
          _StandingRow(rank: i + 1, standing: members[i], leaderScore: memberLeader),
        const SizedBox(height: 16),
      ],
    );
  }

  Future<void> _addPointsToEvent(String eventId, int gained) async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'evt_points_${eventId}_v1';
    final total = (prefs.getInt(key) ?? 0) + gained;
    await prefs.setInt(key, total);
    setState(() => _playerScore = total.toDouble());
  }

  /// Bir etkinlik icin oyuncunun puanini okur (pointRace: tur puanlari toplami,
  /// cometRace: ulasilan hedef sayisi).
  static int _readScore(SharedPreferences prefs, LiveEventDef ev) {
    if (ev.kind == EventKind.pointRace) {
      return prefs.getInt('evt_points_${ev.id}_v1') ?? 0;
    }
    if (ev.kind == EventKind.teamWar) {
      return prefs.getInt('evt_team_points_${ev.id}_v1') ?? 0;
    }
    return prefs.getInt('evt_comet_targets_${ev.id}_v1') ?? 0;
  }

  Future<void> _loadPlayerScore(String eventId, EventKind kind) async {
    final prefs = await SharedPreferences.getInstance();
    final event = LiveEventDef.current(
        NetworkTimeService.instance.nowUtc(), _cycleStartUtc);
    final score = _readScore(prefs, event);
    final team = prefs.getInt('evt_team_${event.id}_v1');
    if (!mounted) return;
    setState(() {
      _playerScore = score.toDouble();
      _myTeam = team;
    });
  }

  @override
  Widget build(BuildContext context) {
    final now = NetworkTimeService.instance.nowUtc();
    final event = LiveEventDef.current(now, _cycleStartUtc);
    final live = event.isActive(now); // v29: Car-Cum arasi etkinlik yok
    final isTeamWar = event.kind == EventKind.teamWar;
    final standings = (live && !isTeamWar) ? buildStandings(event, now, _playerScore) : <EventStanding>[];
    int teamRank = 0;
    if (live && isTeamWar && _myTeam != null) {
      teamRank = buildTeamStandings(event, now, _myTeam, _playerScore).indexWhere((x) => x.isPlayerTeam) + 1;
    }
    final leaderScore = standings.isNotEmpty ? standings.first.score : 1.0;
    final playerRank = standings.indexWhere((s) => s.isPlayer) + 1;
    final remaining = live ? event.endUtc.difference(now) : event.startUtc.difference(now);
    final isPointRace = event.kind == EventKind.pointRace;

    return Scaffold(
      backgroundColor: AppColors.spaceTop,
      appBar: AppBar(
        backgroundColor: AppColors.spaceMid,
        title: Text(t(event.titleKey)),
      ),
      body: Column(
        children: [
          Container(
            key: _kInfo,
            margin: const EdgeInsets.all(12),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.surfaceBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t(event.descKey),
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.timer_outlined, size: 16, color: AppColors.warning),
                    const SizedBox(width: 4),
                    Text(live ? t('evt_endsIn', {'time': _fmtDuration(remaining)}) : t('evt_startsIn', {'time': _fmtDuration(remaining)}),
                        style: const TextStyle(color: AppColors.warning, fontWeight: FontWeight.w700)),
                    const Spacer(),
                    if (teamRank > 0)
                      Text(t('evt_yourTeamRank', {'rank': '$teamRank'}),
                          style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w900))
                    else if (playerRank > 0)
                      Text(t('evt_yourRank', {'rank': '$playerRank'}),
                          style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w900)),
                  ],
                ),
                if (live && event.usesTickets && !widget.rankingOnly && (!isTeamWar || _myTeam != null)) ...[
                  const Divider(color: AppColors.surfaceBorder, height: 20),
                  KeyedSubtree(key: _kTicket, child: _buildTicketRow(event.id, team: isTeamWar)),
                ],
              ],
            ),
          ),
          Expanded(
            child: KeyedSubtree(
              key: _kList,
              child: (live && isTeamWar)
                  ? _buildTeamBody(event, now)
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      // v32: ekranda ILK 100 kisi (99 bot + oyuncu).
                      itemCount: standings.length > kLeaderboardRows ? kLeaderboardRows : standings.length,
                      itemBuilder: (context, i) {
                        final s = standings[i];
                        final rank = i + 1;
                        return _StandingRow(rank: rank, standing: s, leaderScore: leaderScore, isCometRace: event.kind == EventKind.cometRace);
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTicketRow(String eventId, {bool team = false}) {
    final tickets = EventTicketService.instance.ticketsRemaining(eventId);
    final cooldown = EventTicketService.instance.cooldownRemaining(eventId);
    final canWatch = cooldown <= Duration.zero;
    return Row(
      children: [
        const Icon(Icons.confirmation_number_outlined, color: AppColors.accentSoft, size: 20),
        const SizedBox(width: 6),
        Text(t('evt_ticketsCount', {'n': '$tickets'}), style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700)),
        const Spacer(),
        if (tickets > 0)
          ElevatedButton(
            onPressed: () => team ? _startTeamAttempt(eventId) : _startAttempt(eventId),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.accent),
            child: Text(t('evt_play120')),
          )
        else if (canWatch)
          ElevatedButton.icon(
            onPressed: () => _watchAdForTicket(eventId),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.success),
            icon: const Icon(Icons.play_circle_outline, size: 18),
            label: Text(t('evt_watchAdPlus1')),
          )
        else
          Text(t('evt_adAgainIn', {'time': _fmtDuration(cooldown)}),
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
      ],
    );
  }
}

class _StandingRow extends StatelessWidget {
  final int rank;
  final EventStanding standing;
  final double leaderScore;
  final bool isCometRace;
  const _StandingRow({
    required this.rank,
    required this.standing,
    required this.leaderScore,
    this.isCometRace = false,
  });

  Color _rankColor() {
    switch (rank) {
      case 1:
        return Colors.amber.shade600;
      case 2:
        return Colors.blueGrey.shade300;
      case 3:
        return Colors.brown.shade300;
      default:
        return AppColors.surfaceBorder;
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = standing.isPlayer;
    final p = standing.profile;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: me ? AppColors.accent.withOpacity(0.18) : AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: me ? AppColors.accent : AppColors.surfaceBorder, width: me ? 2 : 1),
      ),
      child: Row(
        children: [
          Container(
            width: 32, height: 28, alignment: Alignment.center,
            decoration: BoxDecoration(color: _rankColor(), borderRadius: BorderRadius.circular(10)),
            child: Text('$rank', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12)),
          ),
          const SizedBox(width: 10),
          CircleAvatar(
            radius: 15,
            backgroundColor: me ? AppColors.accent : Color(p?.avatarColor ?? 0xFF5C6BC0),
            child: me
                ? const Icon(Icons.star_rounded, color: Colors.white, size: 18)
                : Text(p?.avatarIcon.isNotEmpty == true ? p!.avatarIcon : standing.name.substring(0, 1).toUpperCase(),
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 13)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(me ? t('lb_you') : standing.name,
                style: TextStyle(color: AppColors.textPrimary, fontWeight: me ? FontWeight.w900 : FontWeight.w600)),
          ),
          Text(
              isCometRace
                  ? '${standing.score.round()} hedef'
                  : standing.score.toStringAsFixed(0),
              style: const TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}


/// Takimyildizi Savasi: tek bir takimin toplam puani satiri.
class _TeamRow extends StatelessWidget {
  final int rank;
  final TeamStanding standing;
  final double leaderScore;
  const _TeamRow({required this.rank, required this.standing, required this.leaderScore});

  @override
  Widget build(BuildContext context) {
    final team = standing.team;
    final me = standing.isPlayerTeam;
    final color = Color(team.color);
    final ratio = leaderScore <= 0 ? 0.0 : (standing.score / leaderScore).clamp(0.0, 1.0).toDouble();
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: me ? color.withOpacity(0.16) : AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: me ? color : AppColors.surfaceBorder, width: me ? 2 : 1),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Text('$rank.', style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w900)),
              const SizedBox(width: 8),
              Text(team.emoji, style: const TextStyle(fontSize: 22)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(t(team.nameKey) + (me ? ' (${t('lb_you')})' : ''),
                    style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w800)),
              ),
              Text(standing.score.toStringAsFixed(0),
                  style: const TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 6,
              backgroundColor: AppColors.surfaceBorder,
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ],
      ),
    );
  }
}
