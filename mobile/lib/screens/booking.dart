import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../api.dart';
import '../theme.dart';
import '../widgets.dart';
import 'payment.dart';

/// 6 · Slot booking (sport · date · court · duration · start time).
/// Also used to reschedule an existing booking when [reschedule] is given.
class BookingScreen extends StatefulWidget {
  final Json venue;
  final int? initialSportId;
  final Json? reschedule;
  final DateTime? initialDate;
  final int? initialStart;
  const BookingScreen({super.key, required this.venue, this.initialSportId, this.reschedule, this.initialDate, this.initialStart});

  static Future<void> openForVenueId(BuildContext context, int venueId,
      {int? sportId, Json? reschedule, DateTime? date, int? startHour}) async {
    try {
      final v = asMap(await api.get('/venues/$venueId/'));
      if (context.mounted) {
        await push(context,
            BookingScreen(venue: v, initialSportId: sportId, reschedule: reschedule, initialDate: date, initialStart: startHour));
      }
    } catch (e) {
      if (context.mounted) toast(context, e.toString());
    }
  }

  @override
  State<BookingScreen> createState() => _BookingScreenState();
}

class _BookingScreenState extends State<BookingScreen> {
  late final List<Json> sports = asList(widget.venue['venue_sports']);
  late final List<Json> allCourts = asList(widget.venue['courts']);
  late int sportIdx;
  int day = 0, courtIdx = 0, dur = 2;
  int? start;
  List<Json> slots = [];
  bool loading = true, busy = false;
  final today = DateTime.now();

  bool get isReschedule => widget.reschedule != null;
  Json get sport => sports[sportIdx];
  List<Json> get courts => allCourts.where((c) => (c['sport_ids'] as List).contains(sport['sport_id'])).toList();
  Json? get court => courts.isEmpty ? null : courts[courtIdx.clamp(0, courts.length - 1)];
  DateTime get date => DateTime(today.year, today.month, today.day).add(Duration(days: day));

  @override
  void initState() {
    super.initState();
    final rs = widget.reschedule;
    final wanted = rs != null ? rs['sport']['id'] : widget.initialSportId;
    sportIdx = sports.isEmpty ? 0 : sports.indexWhere((s) => s['sport_id'] == wanted).clamp(0, sports.length - 1);
    if (widget.initialDate != null) {
      final base = DateTime(today.year, today.month, today.day);
      day = widget.initialDate!.difference(base).inDays.clamp(0, 13);
    }
    start = widget.initialStart;
    if (widget.initialStart != null) dur = 1;
    if (rs != null) {
      dur = rs['duration'];
      courtIdx = courts.indexWhere((c) => c['id'] == rs['court']['id']).clamp(0, 99);
    }
    _load();
  }

  Future<void> _load() async {
    if (sports.isEmpty || court == null) return setState(() => loading = false);
    setState(() => loading = true);
    try {
      final r = asMap(await api.get('/venues/${widget.venue['id']}/availability/', {
        'date': DateFormat('yyyy-MM-dd').format(date),
        'sport': sport['sport_id'],
        'court': court!['id'],
      }));
      final s = asList(r['slots']);
      setState(() {
        slots = s;
        loading = false;
        // keep the chosen start if possible, otherwise preselect the first evening slot that fits
        if (start == null || !s.any((x) => x['hour'] == start)) {
          final free = s.where((x) => x['status'] == 'free').map((x) => x['hour'] as int).toList();
          start = free.firstWhere((h) => h >= 18, orElse: () => free.isEmpty ? (s.isEmpty ? 18 : s.first['hour']) : free.first);
        }
      });
    } catch (e) {
      setState(() => loading = false);
      if (mounted) toast(context, e.toString());
    }
  }

  Json? _slot(int h) => slots.where((s) => s['hour'] == h).firstOrNull;

  ({bool valid, int total, String error}) get check {
    if (start == null) return (valid: false, total: 0, error: 'Pick a start time.');
    var total = 0;
    final closes = widget.venue['closes_at'] as int;
    for (var k = 0; k < dur; k++) {
      final h = start! + k;
      if (h >= closes) {
        return (valid: false, total: 0, error: 'Venue closes at ${fmtHour(closes)}. Pick an earlier start or a shorter duration.');
      }
      final s = _slot(h);
      if (s == null || s['status'] != 'free') {
        return (valid: false, total: 0, error: 'The ${fmtHour(h)} slot is not available. Pick another start time or duration.');
      }
      total += s['price'] as int;
    }
    return (valid: true, total: total, error: '');
  }

  Future<void> _proceed() async {
    if (!await requireProfile(context)) return;
    setState(() => busy = true);
    try {
      if (isReschedule) {
        await api.post('/bookings/${widget.reschedule!['id']}/reschedule/', {
          'date': DateFormat('yyyy-MM-dd').format(date),
          'start_hour': start,
          'court': court!['id'],
        });
        if (!mounted) return;
        toast(context, 'Booking rescheduled');
        Navigator.of(context).pop(true);
        return;
      }
      final b = asMap(await api.post('/bookings/', {
        'venue': widget.venue['id'],
        'court': court!['id'],
        'sport': sport['sport_id'],
        'date': DateFormat('yyyy-MM-dd').format(date),
        'start_hour': start,
        'duration': dur,
      }));
      if (!mounted) return;
      await push(context, PaymentScreen(booking: b));
      _load();
    } catch (e) {
      if (mounted) toast(context, e.toString());
      _load();
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (sports.isEmpty || courts.isEmpty) {
      return Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const BackSquare(),
              const Spacer(),
              Center(
                child: Text('${widget.venue['name']} has no bookable courts yet. Please try another venue.',
                    textAlign: TextAlign.center, style: t(15, c: C.muted, h: 1.5)),
              ),
              const Spacer(flex: 2),
            ]),
          ),
        ),
      );
    }
    final c = check;
    final top = MediaQuery.of(context).padding.top;
    final dateLabel = '${DateFormat('EEE').format(date)}, ${date.day} ${DateFormat('MMM').format(date)}';
    final hrs = '$dur ${dur == 1 ? 'hr' : 'hrs'}';
    return Scaffold(
      body: Stack(children: [
        Column(children: [
          Padding(
            padding: EdgeInsets.fromLTRB(20, top + 8, 20, 12),
            child: Row(children: [
              const BackSquare(),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(isReschedule ? 'Reschedule slot' : 'Select your slot', style: d(20)),
                  Text('${widget.venue['name']} · ${widget.venue['area']}',
                      style: t(13, c: C.muted), maxLines: 1, overflow: TextOverflow.ellipsis),
                ]),
              ),
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white, width: 2),
                  boxShadow: const [BoxShadow(color: Color(0x2610231A), blurRadius: 12, offset: Offset(0, 4))],
                ),
                child: Img(widget.venue['image'], width: 48, height: 48, radius: BorderRadius.circular(12)),
              ),
            ]),
          ),
          Expanded(
            child: ListView(padding: const EdgeInsets.only(bottom: 190), children: [
              if (sports.length > 1 && !isReschedule)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                  child: Segmented(
                    bg: const Color(0xFFE6ECE3),
                    height: 44,
                    labels: [for (final s in sports) s['name'] as String],
                    index: sportIdx,
                    onChanged: (i) {
                      setState(() {
                        sportIdx = i;
                        courtIdx = 0;
                      });
                      _load();
                    },
                  ),
                ),
              Label(DateFormat('MMMM yyyy').format(date)),
              SizedBox(
                height: 72,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  itemCount: 14,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (_, i) {
                    final dd = DateTime(today.year, today.month, today.day).add(Duration(days: i));
                    final on = i == day;
                    return Semantics(
                      selected: on,
                      button: true,
                      label: DateFormat('EEEE d MMMM').format(dd),
                      child: GestureDetector(
                        onTap: () {
                          setState(() => day = i);
                          _load();
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          width: 60,
                          decoration: BoxDecoration(
                            color: on ? C.brand : Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: on ? C.brand : C.line),
                            boxShadow: on ? shadowBrandSm : null,
                          ),
                          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                            Text(i == 0 ? 'Today' : DateFormat('EEE').format(dd),
                                style: t(12, w: FontWeight.w500, c: (on ? Colors.white : C.ink).withValues(alpha: 0.85))),
                            const SizedBox(height: 2),
                            Text('${dd.day}', style: d(20, c: on ? Colors.white : C.ink)),
                          ]),
                        ),
                      ),
                    );
                  },
                ),
              ),
              const Label('Court'),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(children: [
                  for (var i = 0; i < courts.length && i < 4; i++) ...[
                    if (i > 0) const SizedBox(width: 8),
                    Expanded(
                      child: Choice(
                        selected: i == courtIdx,
                        height: 60,
                        onTap: () {
                          setState(() => courtIdx = i);
                          _load();
                        },
                        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Text(courts[i]['name'], style: t(14, w: FontWeight.w700, c: i == courtIdx ? Colors.white : C.ink)),
                          Text(courts[i]['meta'] ?? '', maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: t(11, c: (i == courtIdx ? Colors.white : C.ink).withValues(alpha: 0.85))),
                        ]),
                      ),
                    ),
                  ],
                ]),
              ),
              if (!isReschedule) ...[
                const Label('Duration'),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(children: [
                    for (final n in [1, 2, 3, 4]) ...[
                      if (n > 1) const SizedBox(width: 8),
                      Expanded(
                        child: Choice(
                          selected: n == dur,
                          height: 44,
                          radius: 12,
                          onTap: () => setState(() => dur = n),
                          child: Text('$n ${n == 1 ? 'hr' : 'hrs'}', style: t(14, w: FontWeight.w600, c: n == dur ? Colors.white : C.ink)),
                        ),
                      ),
                    ],
                  ]),
                ),
              ],
              Container(
                margin: const EdgeInsets.fromLTRB(20, 24, 20, 0),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: C.line)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Container(
                    height: 6,
                    margin: const EdgeInsets.fromLTRB(24, 0, 24, 6),
                    decoration: BoxDecoration(color: const Color(0xFFC9D4CC), borderRadius: BorderRadius.circular(999)),
                  ),
                  Text('PICK A START TIME', textAlign: TextAlign.center, style: t(11, w: FontWeight.w600, c: C.muted, ls: 1.2)),
                  const SizedBox(height: 14),
                  if (loading)
                    const Padding(padding: EdgeInsets.all(30), child: Center(child: CircularProgressIndicator(color: C.brand)))
                  else
                    ..._groups(c.valid),
                  Container(
                    margin: const EdgeInsets.only(top: 18),
                    padding: const EdgeInsets.only(top: 14),
                    decoration: const BoxDecoration(border: Border(top: BorderSide(color: C.line))),
                    child: Wrap(spacing: 14, runSpacing: 8, children: [
                      _legend(Container(width: 14, height: 14, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(4), border: Border.all(color: C.radioOff, width: 1.5))), 'Available'),
                      _legend(Container(width: 14, height: 14, decoration: BoxDecoration(color: C.brand, borderRadius: BorderRadius.circular(4))), 'Selected'),
                      _legend(Container(width: 14, height: 14, decoration: BoxDecoration(color: const Color(0xFFE9ECE6), borderRadius: BorderRadius.circular(4))), 'Booked'),
                      _legend(Container(width: 8, height: 8, decoration: const BoxDecoration(color: Color(0xFFB45309), shape: BoxShape.circle)), 'Peak price'),
                    ]),
                  ),
                ]),
              ),
            ]),
          ),
        ]),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Container(
            padding: EdgeInsets.fromLTRB(20, 14, 20, 16 + MediaQuery.of(context).padding.bottom),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              border: Border(top: BorderSide(color: C.line)),
            ),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (!c.valid && !loading)
                Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(color: C.warnBg, borderRadius: BorderRadius.circular(12)),
                  child: Text(c.error, style: t(13, c: C.warnInk, h: 1.4)),
                ),
              Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(
                        c.valid
                            ? '$dateLabel · ${fmtTime(start!)} – ${fmtTime(start! + dur)}'
                            : '$dateLabel · ${start == null ? '' : '${fmtHour(start!)} start'}',
                        style: t(14, w: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text('${court?['name'] ?? ''} · ${sport['name']} · $hrs', style: t(12, c: C.muted)),
                  ]),
                ),
                if (!isReschedule) Text(c.valid ? inr(c.total) : '₹—', style: d(22)),
              ]),
              const SizedBox(height: 12),
              PrimaryButton(isReschedule ? 'Confirm new slot' : 'Proceed to pay',
                  height: 56,
                  radius: 16,
                  shadow: false,
                  loading: busy,
                  trailing: c.valid ? const Icon(LucideIcons.arrowRight, color: Colors.white, size: 18) : null,
                  onTap: c.valid && !loading ? _proceed : null),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _legend(Widget box, String label) => Row(mainAxisSize: MainAxisSize.min, children: [
        box,
        const SizedBox(width: 6),
        Text(label, style: t(12, c: C.muted)),
      ]);

  List<Widget> _groups(bool valid) {
    const defs = [('Morning', 0, 11), ('Afternoon', 12, 15), ('Evening', 16, 19), ('Night', 20, 23)];
    final out = <Widget>[];
    for (final g in defs) {
      final hs = slots.where((s) => (s['hour'] as int) >= g.$2 && (s['hour'] as int) <= g.$3).toList();
      if (hs.isEmpty) continue;
      final first = hs.first['hour'] as int, last = hs.last['hour'] as int;
      out.add(Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text.rich(TextSpan(style: t(13, w: FontWeight.w600), children: [
            TextSpan(text: g.$1),
            TextSpan(text: ' · ${fmtHour(first)} – ${fmtHour(last + 1)}', style: t(13, c: C.muted)),
          ])),
          const SizedBox(height: 8),
          GridView.count(
            crossAxisCount: 4,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 1.45,
            children: [for (final s in hs) _slotTile(s, valid)],
          ),
        ]),
      ));
    }
    return out;
  }

  Widget _slotTile(Json s, bool valid) {
    final h = s['hour'] as int;
    final past = s['status'] == 'past', booked = s['status'] == 'booked';
    final sel = valid && start != null && h >= start! && h < start! + dur;
    final clash = !valid && h == start;
    Color bg = Colors.white, fg = C.ink;
    Border border = Border.all(color: C.radioOff, width: 1.5);
    if (past) {
      bg = C.ground;
      fg = const Color(0xFF57625A);
      border = Border.all(color: const Color(0xFFC9D4CC));
    } else if (booked) {
      bg = const Color(0xFFE9ECE6);
      fg = const Color(0xFF57625A);
      border = Border.all(color: const Color(0xFFE9ECE6));
    } else if (sel) {
      bg = C.brand;
      fg = Colors.white;
      border = Border.all(color: C.brand);
    } else if (clash) {
      fg = C.warnInk;
      border = Border.all(color: const Color(0xFFB45309), width: 2);
    }
    final peak = s['peak'] == true && !past && !booked && !sel;
    return Semantics(
      button: true,
      enabled: !past && !booked,
      selected: sel,
      label: '${s['label']}${past ? ', past' : booked ? ', booked' : ', ${inr(s['price'])}${s['peak'] == true ? ', peak price' : ''}'}',
      child: GestureDetector(
        onTap: past || booked ? null : () => setState(() => start = h),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(12),
            border: border,
            boxShadow: sel ? const [BoxShadow(color: Color(0x4716803C), blurRadius: 14, offset: Offset(0, 6))] : null,
          ),
          child: Stack(children: [
            Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(s['label'], style: t(13, w: FontWeight.w700, c: fg, deco: booked ? TextDecoration.lineThrough : null)),
                Text(past ? 'Past' : booked ? 'Booked' : inr(s['price']), style: t(10, w: FontWeight.w500, c: fg.withValues(alpha: 0.85))),
              ]),
            ),
            if (peak)
              Positioned(
                top: 5,
                right: 5,
                child: Container(width: 6, height: 6, decoration: const BoxDecoration(color: Color(0xFFB45309), shape: BoxShape.circle)),
              ),
          ]),
        ),
      ),
    );
  }
}
