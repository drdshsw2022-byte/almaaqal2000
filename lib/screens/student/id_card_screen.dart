import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../app_state.dart';
import '../../config.dart';
import '../../data/repo.dart';
import '../../models.dart';
import '../../services/nfc_service.dart';
import '../../theme.dart';
import '../../widgets/common.dart';

/// الهوية الجامعية الرقمية للطالب: الاسم والبريد والرقم ورمز QR يمسحه الدكتور.
class IdCardScreen extends StatefulWidget {
  final Student student;
  const IdCardScreen({super.key, required this.student});

  @override
  State<IdCardScreen> createState() => _IdCardScreenState();
}

class _IdCardScreenState extends State<IdCardScreen> {
  String? _deptName;
  bool _nfc = false;

  bool get _isMe => AppState.user.value?.student?.id == widget.student.id;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final depts = await repo.departments();
      _deptName = depts
          .where((d) => d.id == widget.student.deptId)
          .map((d) => d.name)
          .firstOrNull;
      if (_isMe) {
        await NfcService.setStudentPayload(StudentCode.encode(widget.student));
        _nfc = await NfcService.isAvailable();
      }
    } catch (_) {}
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: gradientAppBar('الهوية الجامعية'),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          StudentIdCard(student: widget.student, deptName: _deptName),
          const SizedBox(height: 18),
          _hint(Icons.qr_code_scanner,
              'اعرض رمز QR على الدكتور ليمسحه بهاتفه عند بدء المحاضرة.'),
          if (_isMe)
            _hint(
                Icons.nfc,
                _nfc
                    ? 'أو قرّب هاتفك (مفتوح القفل) من ظهر هاتف الدكتور لتسجيل حضورك عبر NFC.'
                    : 'هاتفك لا يدعم NFC أو أنه مطفأ؛ استخدم رمز QR أو بطاقتك الجامعية.'),
          if (widget.student.nfcUid != null)
            _hint(Icons.credit_card,
                'بطاقتك الجامعية مرتبطة بحسابك ويمكن قراءتها عبر NFC.'),
        ],
      ),
    );
  }

  Widget _hint(IconData i, String t) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
              color: Colors.white, borderRadius: BorderRadius.circular(16)),
          child: Row(
            children: [
              Icon(i, color: AppColors.royal),
              const SizedBox(width: 10),
              Expanded(child: Text(t, style: const TextStyle(fontSize: 13))),
            ],
          ),
        ),
      );
}

/// بطاقة الهوية (تُستخدم في الشاشة الكاملة وفي لوحة الطالب).
class StudentIdCard extends StatelessWidget {
  final Student student;
  final String? deptName;
  final bool compact;
  const StudentIdCard(
      {super.key, required this.student, this.deptName, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final s = student;
    final qrSize = compact ? 110.0 : 230.0;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(26),
        boxShadow: [
          BoxShadow(
              color: AppColors.royal.withOpacity(0.18),
              blurRadius: 24,
              offset: const Offset(0, 10))
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            decoration: const BoxDecoration(
              gradient: AppColors.mainGradient,
              borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
            ),
            child: Row(
              children: [
                const AppLogo(size: 38),
                const SizedBox(width: 10),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(AppConfig.universityName,
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800)),
                      Text('هوية طالب • ${AppConfig.city}',
                          style:
                              TextStyle(color: Colors.white70, fontSize: 12)),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                      gradient: AppColors.goldGradient,
                      borderRadius: BorderRadius.circular(12)),
                  child: Text(stageName(s.stage),
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w800)),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: compact
                ? Row(
                    children: [
                      Expanded(child: _info(s)),
                      const SizedBox(width: 10),
                      _qr(s, qrSize),
                    ],
                  )
                : Column(
                    children: [
                      _qr(s, qrSize),
                      const SizedBox(height: 16),
                      _info(s, center: true),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _qr(Student s, double size) => QrImageView(
        data: StudentCode.encode(s),
        version: QrVersions.auto,
        size: size,
        padding: EdgeInsets.zero,
        backgroundColor: Colors.white,
        eyeStyle: const QrEyeStyle(
            eyeShape: QrEyeShape.square, color: AppColors.night),
        dataModuleStyle: const QrDataModuleStyle(
            dataModuleShape: QrDataModuleShape.square, color: AppColors.night),
      );

  Widget _info(Student s, {bool center = false}) {
    final align = center ? CrossAxisAlignment.center : CrossAxisAlignment.start;
    final ta = center ? TextAlign.center : TextAlign.start;
    return Column(
      crossAxisAlignment: align,
      children: [
        Text(s.name,
            textAlign: ta,
            style: TextStyle(
                fontSize: compact ? 15 : 20, fontWeight: FontWeight.w900)),
        const SizedBox(height: 4),
        Text(s.email ?? '—',
            textAlign: ta,
            textDirection: TextDirection.ltr,
            style: const TextStyle(color: AppColors.royal, fontSize: 12)),
        const SizedBox(height: 6),
        Text('الرقم المعرفي: ${s.id}',
            textAlign: ta,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
        Text(
            '${deptName ?? 'القسم غير محدد'} • ${shiftName(s.shift)}',
            textAlign: ta,
            style: const TextStyle(color: AppColors.muted, fontSize: 12)),
      ],
    );
  }
}
