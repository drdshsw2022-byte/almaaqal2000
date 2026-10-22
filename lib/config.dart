/// إعدادات التطبيق العامة.
///
/// إعدادات Firebase تُمرَّر وقت البناء عبر --dart-define (انظر README).
/// إذا تُركت فارغة يعمل التطبيق في "الوضع التجريبي" المحلي على جهاز واحد.
class AppConfig {
  static const universityName = 'جامعة المعقل الأهلية';
  static const city = 'البصرة';
  static const appName = 'نظام الحضور الذكي';

  /// نطاق البريد الرسمي للجامعة: لا يُقبل الدخول إلا به.
  static const universityDomain = 'almaaqal.edu.iq';

  /// حسابات تملك صلاحية المدير العام دائماً (حتى من خارج نطاق الجامعة).
  static const superAdminEmails = <String>['drdsh.sw2022@gmail.com'];

  // ---------------- الدخول بكلمة المرور ----------------
  /// حساب مدير النظام الأول (يُطلب تغيير كلمة مروره عند أول دخول).
  static const bootstrapAdminUsername = 'admin';
  static const bootstrapAdminPassword = 'Almaaqal@2026';

  /// كلمة المرور الأولية الافتراضية للكادر (إن لم يحدد المدير غيرها).
  static const defaultStaffPassword = 'Almaaqal@2026';

  /// نطاقات داخلية لحسابات كلمة المرور في Firebase (لا تُستخدم كبريد حقيقي).
  static const staffAuthDomain = 'pw.almaaqal.app';
  static const studentAuthDomain = 'st.almaaqal.app';

  /// بادئة رمز هوية الطالب (QR / NFC).
  static const studentCodePrefix = 'ALMAQAL-ST';

  /// معرّف تطبيق NFC (AID) لهوية الطالب على الهاتف: F0 + "ALMAQAL".
  static const nfcAid = 'F0414C4D4151414C';

  // ---------------- Firebase ----------------
  static const fbApiKey = String.fromEnvironment('FB_API_KEY');
  static const fbAppId = String.fromEnvironment('FB_APP_ID');
  static const fbSenderId = String.fromEnvironment('FB_SENDER_ID');
  static const fbProjectId = String.fromEnvironment('FB_PROJECT_ID');
  static const fbStorageBucket = String.fromEnvironment('FB_STORAGE_BUCKET');
  static const googleWebClientId = String.fromEnvironment('GOOGLE_WEB_CLIENT_ID');

  static bool get firebaseEnabled =>
      fbApiKey.isNotEmpty && fbAppId.isNotEmpty && fbProjectId.isNotEmpty;

  // ---------------- الوضع التجريبي ----------------
  static const demoAdminEmail = 'admin@$universityDomain';
  static const demoDoctorEmail = 'doctor@$universityDomain';
  static const demoPresidentEmail = 'president@$universityDomain';
  static const demoDeanEmail = 'dean@$universityDomain';
  static const demoHeadEmail = 'head@$universityDomain';

  static bool isUniversityEmail(String email) =>
      email.toLowerCase().trim().endsWith('@$universityDomain');

  /// صيغة بريد صحيحة (لبريد الكادر الذي قد يكون خارج نطاق الجامعة).
  static bool isValidEmail(String email) =>
      RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email.trim());

  static bool isAllowedEmail(String email) {
    final e = email.toLowerCase().trim();
    return isUniversityEmail(e) || superAdminEmails.contains(e);
  }
}
