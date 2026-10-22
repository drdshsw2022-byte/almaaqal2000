import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../app_state.dart';
import '../../data/repo.dart';
import '../../models.dart';
import '../../services/nfc_service.dart';
import '../common/nfc_test_screen.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../common/reports_screen.dart';

enum _Mode { qr, nfc, id }

class _Result {
  final bool ok;
  final bool warn;
  final String title;
  final String body;
  final Student? overrideStudent; // لعرض زر "إضافة رغم ذلك"
  final String method;
  _Result(this.ok, this.title, this.body,
      {this.warn = false, this.overrideStudent, this.method = 'qr'});
}

/// شاشة المحاضرة الجارية: الدكتور يمسح هوية الطالب (QR) أو يقرؤها عبر NFC.
class LiveSessionScreen extends StatefulWidget {
  final LectureSession session;
  final Course course;
  const LiveSessionScreen(
      {super.key, required this.session, required this.course});

  @override
  State<LiveSessionScreen> createState() => _LiveSessionScreenState();
}

class _LiveSessionScreenState extends State<LiveSessionScreen> {
  _Mode _mode = _Mode.qr;
  // يُنشأ متحكم جديد للكاميرا عند كل عودة لوضع QR (ويُتلف عند الانتقال لـ NFC)
  MobileScannerController? _scanner = _newScanner();

  static MobileScannerController _newScanner() => MobileScannerController(
        detectionSpeed: DetectionSpeed.normal,
        detectionTimeoutMs: 600,
      );
  late final Stream<List<AttendanceRecord>> _attStream =
      repo.watchAttendance(widget.session.id);

  Map<String, Student> _byId = {};
  List<Student> _eligible = [];
  Set<String> _present = {};
  bool _nfcAvailable = false;
  bool _busy = false;
  String? _lastCode;
  DateTime _lastAt = DateTime(2000);
  _Result? _result;
  final _idCtrl = TextEditingController();
  Timer? _clock;
  DateTime _now = DateTime.now();

  LectureSession get _s => widget.session;

  @override
  void initState() {
    super.initState();
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
    _init();
  }

  Future<void> _init() async {
    try {
      final all = await repo.students();
      _byId = {for (final s in all) s.id: s};
      _eligible = all.where(_s.appliesTo).toList()
        ..sort((a, b) => a.name.compareTo(b.name));
      _nfcAvailable = await NfcService.isAvailable();
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e), error: true);
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _clock?.cancel();
    _idCtrl.dispose();
    _scanner?.dispose();
    NfcService.stopReading();
    super.dispose();
  }

  Future<void> _setMode(_Mode m) async {
    if (m == _mode) return;
    if (m == _Mode.nfc) _nfcAvailable = await NfcService.isAvailable();
    if (!mounted) return;
    if (m == _Mode.nfc && !_nfcAvailable) {
      showSnack(context, 'هذا الهاتف لا يدعم NFC أو أنه مطفأ من الإعدادات',
          error: true);
      return;
    }
    // إيقاف الوضع الحالي
    if (_mode == _Mode.nfc) await NfcService.stopReading();
    final old = _scanner;
    setState(() {
      _scanner = m == _Mode.qr ? _newScanner() : null;
      _mode = m;
    });
    if (m != _Mode.qr) await old?.dispose();
    if (m == _Mode.nfc) {
      await NfcService.startReading(
          _onNfc, (e) => _show(_Result(false, 'NFC', e)));
    }
  }

  Future<void> _openNfcTest() async {
    await NfcService.stopReading();
    if (!mounted) return;
    await Navigator.push(
        context, MaterialPageRoute(builder: (_) => const NfcTestScreen()));
    if (mounted && _mode == _Mode.nfc) {
      await NfcService.startReading(
          _onNfc, (e) => _show(_Result(false, 'NFC', e)));
    }
  }

  /// تسجيل بكتابة الرقم الجامعي (عند تعذّر QR و NFC).
  Future<void> _submitId() async {
    final id = _idCtrl.text.trim();
    if (id.isEmpty) return;
    final st = _byId[id] ?? await repo.student(id);
    if (st == null) {
      _show(_Result(false, 'رقم غير موجود',
          'الرقم الجامعي $id غير مسجّل في قاعدة البيانات'));
      return;
    }
    _idCtrl.clear();
    await _register(st, 'id');
  }

  // ---------------- القراءة ----------------
  void _onDetect(BarcodeCapture cap) {
    final raw =
        cap.barcodes.map((b) => b.rawValue).whereType<String>().firstOrNull;
    if (raw == null) return;
    // تجاهل تكرار نفس الرمز خلال 4 ثوانٍ
    final now = DateTime.now();
    if (raw == _lastCode && now.difference(_lastAt).inSeconds < 4) return;
    _lastCode = raw;
    _lastAt = now;
    _handleCode(raw, 'qr');
  }

  void _onNfc(NfcRead r) {
    if (r.phoneWithoutId) {
      _show(_Result(false, 'هاتف بلا هوية',
          'على هاتف الطالب: افتح تطبيق جامعة المعقل وسجّل الدخول برقمه المعرفي مرة واحدة، وأبقِ الشاشة مضاءة ثم قرّبه مجدداً'));
      return;
    }
    if (r.payload != null) {
      _handleCode(r.payload!, 'nfc');
    } else if (r.uid != null) {
      _handleCard(r.uid!);
    }
  }

  Future<void> _handleCode(String raw, String method) async {
    if (_busy) return;
    final p = StudentCode.parse(raw);
    Student? st;
    if (p.id != null) {
      st = _byId[p.id] ?? await repo.student(p.id!);
    } else if (p.email != null) {
      st = await repo.studentByEmail(p.email!);
    }
    if (st == null) {
      _show(_Result(false, 'رمز غير معروف',
          'هذا الرمز لا يطابق أي طالب في قاعدة البيانات'));
      return;
    }
    await _register(st, method);
  }

  Future<void> _handleCard(String uid) async {
    if (_busy) return;
    Student? st;
    for (final s in _byId.values) {
      if (s.nfcUid == uid) st = s;
    }
    st ??= await repo.studentByNfc(uid);
    if (st != null) {
      await _register(st, 'nfc');
      return;
    }
    // بطاقة غير مرتبطة: عرض ربطها بطالب من قائمة المحاضرة
    if (!mounted) return;
    final link = await confirmDialog(context, 'بطاقة غير مرتبطة',
        'هذه البطاقة غير مرتبطة بأي طالب بعد. هل تريد ربطها الآن بطالب ثم تسجيل حضوره؟',
        ok: 'ربط');
    if (!link || !mounted) return;
    final picked = await _pickStudent(_eligible, 'اختر صاحب البطاقة');
    if (picked == null || !mounted) return;
    final ok = await runBusy(context, () async {
      await repo.setStudentNfc(picked.id, uid);
      return true;
    });
    if (ok == true) {
      _byId[picked.id] = picked.copyWith(nfcUid: uid);
      await _register(picked, 'nfc');
    }
  }

  String? _whyNot(Student st) {
    if (st.stage != _s.stage) {
      return 'الطالب في ${stageName(st.stage)} والمحاضرة لـ${stageName(_s.stage)}';
    }
    if (st.deptId != null && st.deptId != _s.deptId) {
      return 'الطالب من قسم آخر';
    }
    if (_s.shift != 'all' && st.shift != _s.shift) {
      return 'الطالب في الدوام ${shiftName(st.shift)} والمحاضرة ${shiftName(_s.shift)}';
    }
    return null;
  }

  Future<void> _register(Student st, String method,
      {bool force = false}) async {
    if (_present.contains(st.id)) {
      _show(_Result(true, st.name,
          'الرقم الجامعي: ${st.id}\nمسجّل حضوره مسبقاً في هذه المحاضرة',
          warn: true));
      return;
    }
    final why = force ? null : _whyNot(st);
    if (why != null) {
      _show(_Result(false, st.name, 'الرقم الجامعي: ${st.id}\n$why',
          warn: true, overrideStudent: st, method: method));
      return;
    }
    setState(() => _busy = true);
    try {
      await repo.markAttendance(AttendanceRecord(
        sessionId: _s.id,
        courseId: _s.courseId,
        studentId: st.id,
        studentName: st.name,
        time: DateTime.now().millisecondsSinceEpoch,
        method: method,
      ));
      _present.add(st.id);
      HapticFeedback.mediumImpact();
      SystemSound.play(SystemSoundType.click);
      _show(_Result(true, st.name,
          'الرقم الجامعي: ${st.id}\n${shiftName(st.shift)} • تم تسجيل الحضور (${methodName(method)})'));
    } catch (e) {
      _show(_Result(false, st.name, friendlyError(e)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _show(_Result r) {
    if (!mounted) return;
    if (!r.ok) HapticFeedback.heavyImpact();
    setState(() => _result = r);
  }

  Future<Student?> _pickStudent(List<Student> list, String title) =>
      showModalBottomSheet<Student>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (c) => _StudentSearchSheet(students: list, title: title),
      );

  Future<void> _manualAdd() async {
    final candidates =
        _eligible.where((s) => !_present.contains(s.id)).toList();
    final picked = await _pickStudent(candidates, 'إضافة حضور يدوي');
    if (picked != null) await _register(picked, 'manual');
  }

  Future<void> _end() async {
    final ok = await confirmDialog(context, 'إنهاء المحاضرة',
        'بعد الإنهاء يُحسب غائباً كل من لم يُسجَّل. يبقى بإمكانك التعديل اليدوي من التقرير.',
        ok: 'إنهاء');
    if (!ok || !mounted) return;
    final r = await runBusy(context, () async {
      await repo.closeSession(_s.id);
      return true;
    }, success: 'تم إنهاء المحاضرة');
    if (r == true && mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => SessionDetailScreen(
              session: _s.copyWith(active: false), course: widget.course),
        ),
      );
    }
  }

  // ---------------- الواجهة ----------------
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<AttendanceRecord>>(
      stream: _attStream,
      builder: (context, snap) {
        final recs = snap.data ?? const <AttendanceRecord>[];
        _present = recs.map((r) => r.studentId).toSet();
        final total = _eligible.length;
        final elapsed = _now.difference(_s.startTime);
        return Scaffold(
          appBar: gradientAppBar('تسجيل الحضور', actions: [
            IconButton(
              tooltip: 'إضافة يدوية',
              onPressed: _manualAdd,
              icon: const Icon(Icons.person_add_alt),
            ),
          ]),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
            children: [
              Text(widget.course.nameAr,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 19, fontWeight: FontWeight.w900)),
              Text(
                  '${widget.course.code} • ${stageName(_s.stage)} • ${shiftName(_s.shift)}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.muted)),
              const SizedBox(height: 12),
              SegmentedButton<_Mode>(
                segments: const [
                  ButtonSegment(
                      value: _Mode.qr,
                      label: Text('QR'),
                      icon: Icon(Icons.qr_code_scanner)),
                  ButtonSegment(
                      value: _Mode.nfc,
                      label: Text('NFC'),
                      icon: Icon(Icons.nfc)),
                  ButtonSegment(
                      value: _Mode.id,
                      label: Text('الرقم'),
                      icon: Icon(Icons.dialpad)),
                ],
                selected: {_mode},
                onSelectionChanged: (v) => _setMode(v.first),
              ),
              const SizedBox(height: 12),
              _reader(),
              const SizedBox(height: 12),
              if (_result != null) _resultCard(_result!),
              const SizedBox(height: 12),
              Row(
                children: [
                  _stat('الحاضرون', '${_present.length}', Icons.how_to_reg,
                      AppColors.emerald),
                  const SizedBox(width: 8),
                  _stat('المتوقع', '$total', Icons.groups, AppColors.cyan),
                  const SizedBox(width: 8),
                  _stat(
                      'المدة',
                      '${elapsed.inMinutes}:${two(elapsed.inSeconds % 60)}',
                      Icons.timer_outlined,
                      AppColors.orange),
                ],
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: LinearProgressIndicator(
                  value: total == 0 ? 0 : (_present.length / total).clamp(0.0, 1.0).toDouble(),
                  minHeight: 9,
                  backgroundColor: AppColors.emerald.withOpacity(0.12),
                  valueColor: const AlwaysStoppedAnimation(AppColors.emerald),
                ),
              ),
              const SizedBox(height: 14),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.rose),
                onPressed: _end,
                icon: const Icon(Icons.stop_circle_outlined),
                label: const Text('إنهاء المحاضرة'),
              ),
              SectionTitle('آخر المسجّلين (${recs.length})'),
              if (recs.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('لم يُسجَّل أحد بعد',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.muted)),
                )
              else
                ...recs.take(40).map((r) => Card(
                      margin: const EdgeInsets.only(bottom: 6),
                      child: ListTile(
                        dense: true,
                        leading: Icon(
                            switch (r.method) {
                              'qr' => Icons.qr_code_2,
                              'nfc' => Icons.nfc,
                              'id' => Icons.dialpad,
                              _ => Icons.edit_note,
                            },
                            color: AppColors.royal),
                        title: Text(r.studentName,
                            style:
                                const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text(
                            'الرقم الجامعي: ${r.studentId}\n${fmtTime(r.dateTime)} • ${methodName(r.method)}'),
                        isThreeLine: true,
                      ),
                    )),
            ],
          ),
        );
      },
    );
  }

  Widget _reader() {
    if (_mode == _Mode.id) {
      return Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('تسجيل بالرقم الجامعي',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            const Text('عند تعذّر مسح الهوية أو قراءة NFC',
                style: TextStyle(color: AppColors.muted, fontSize: 12)),
            const SizedBox(height: 12),
            TextField(
              controller: _idCtrl,
              autofocus: true,
              keyboardType: TextInputType.number,
              textDirection: TextDirection.ltr,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: 2),
              onSubmitted: (_) => _submitId(),
              decoration: const InputDecoration(
                hintText: 'الرقم الجامعي',
                prefixIcon: Icon(Icons.badge_outlined),
              ),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: _busy ? null : _submitId,
              icon: const Icon(Icons.how_to_reg),
              label: const Text('تسجيل الحضور'),
            ),
          ],
        ),
      );
    }
    final scanner = _scanner;
    if (_mode == _Mode.nfc || scanner == null) {
      return Container(
        height: 240,
        decoration: BoxDecoration(
          gradient: AppColors.mainGradient,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.85, end: 1.1),
              duration: const Duration(milliseconds: 900),
              curve: Curves.easeInOut,
              builder: (_, v, child) => Transform.scale(scale: v, child: child),
              child: const Icon(Icons.nfc, color: Colors.white, size: 90),
            ),
            const SizedBox(height: 12),
            const Text('قرّب بطاقة الطالب أو هاتفه من ظهر هاتفك',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700)),
            const Text('القراءة مستمرة لكل الطلاب • ثبّتها ثانيتين',
                style: TextStyle(color: Colors.white70)),
            if (_mode == _Mode.nfc)
              TextButton.icon(
                onPressed: _openNfcTest,
                icon: const Icon(Icons.build_circle_outlined,
                    color: AppColors.gold),
                label: const Text('لا تعمل؟ اختبار NFC',
                    style: TextStyle(color: AppColors.gold)),
              ),
          ],
        ),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: SizedBox(
        height: 300,
        child: Stack(
          fit: StackFit.expand,
          children: [
            MobileScanner(
              key: ObjectKey(scanner),
              controller: scanner,
              onDetect: _onDetect,
              errorBuilder: (context, e, child) => Container(
                color: AppColors.night,
                alignment: Alignment.center,
                padding: const EdgeInsets.all(20),
                child: Text(
                  'تعذّر تشغيل الكاميرا. امنح التطبيق إذن الكاميرا من إعدادات الهاتف.\n(${e.errorCode.name})',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ),
            Center(
              child: Container(
                width: 200,
                height: 200,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: AppColors.gold, width: 3),
                ),
              ),
            ),
            Positioned(
              bottom: 10,
              left: 10,
              right: 10,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.45),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text('وجّه الكاميرا نحو رمز QR في هوية الطالب',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white)),
              ),
            ),
            Positioned(
              top: 8,
              left: 8,
              child: IconButton.filledTonal(
                onPressed: () => scanner.toggleTorch(),
                icon: const Icon(Icons.flashlight_on_outlined),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _resultCard(_Result r) {
    final color = r.ok && !r.warn
        ? AppColors.emerald
        : (r.warn ? AppColors.orange : AppColors.rose);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withOpacity(0.5), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                  r.ok && !r.warn
                      ? Icons.check_circle
                      : (r.warn ? Icons.info : Icons.cancel),
                  color: color,
                  size: 34),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(r.title,
                        style: const TextStyle(
                            fontSize: 17, fontWeight: FontWeight.w900)),
                    Text(r.body, style: const TextStyle(fontSize: 13)),
                  ],
                ),
              ),
            ],
          ),
          if (r.overrideStudent != null) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () {
                final st = r.overrideStudent!;
                setState(() => _result = null);
                _register(st, r.method, force: true);
              },
              icon: const Icon(Icons.how_to_reg),
              label: const Text('تسجيل حضوره رغم ذلك'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _stat(String label, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
            color: Colors.white, borderRadius: BorderRadius.circular(16)),
        child: Column(
          children: [
            Icon(icon, color: color),
            Text(value,
                style:
                    const TextStyle(fontSize: 19, fontWeight: FontWeight.w900)),
            Text(label,
                style: const TextStyle(color: AppColors.muted, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

class _StudentSearchSheet extends StatefulWidget {
  final List<Student> students;
  final String title;
  const _StudentSearchSheet({required this.students, required this.title});

  @override
  State<_StudentSearchSheet> createState() => _StudentSearchSheetState();
}

class _StudentSearchSheetState extends State<_StudentSearchSheet> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final list = widget.students
        .where((s) => _q.isEmpty || s.name.contains(_q) || s.id.contains(_q))
        .toList();
    return SafeArea(
      child: Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.75,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(widget.title,
                        style: const TextStyle(
                            fontSize: 17, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 8),
                    TextField(
                      onChanged: (v) => setState(() => _q = v.trim()),
                      decoration: const InputDecoration(
                          hintText: 'ابحث بالاسم أو الرقم',
                          prefixIcon: Icon(Icons.search)),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: list.isEmpty
                    ? const EmptyState(
                        icon: Icons.person_off, text: 'لا يوجد طلاب مطابقون')
                    : ListView.builder(
                        itemCount: list.length,
                        itemBuilder: (_, i) => ListTile(
                          leading: const Icon(Icons.person_outline),
                          title: Text(list[i].name),
                          subtitle: Text(
                              'الرقم الجامعي: ${list[i].id} • ${shiftName(list[i].shift)}'),
                          onTap: () => Navigator.pop(context, list[i]),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
