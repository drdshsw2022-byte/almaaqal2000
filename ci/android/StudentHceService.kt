package iq.edu.almaqal.almaqal_attendance

import android.content.Context
import android.nfc.cardemulation.HostApduService
import android.os.Bundle

/**
 * يجعل هاتف الطالب يتصرف كبطاقة NFC: عندما يقرّبه من هاتف الدكتور
 * يرسل رمز هويته (ALMAQAL-ST|<الرقم المعرفي>) المحفوظ من تطبيق Flutter.
 */
class StudentHceService : HostApduService() {

    private val aid = byteArrayOf(
        0xF0.toByte(), 0x41, 0x4C, 0x4D, 0x41, 0x51, 0x41, 0x4C
    )
    private val ok = byteArrayOf(0x90.toByte(), 0x00)
    private val notFound = byteArrayOf(0x6A.toByte(), 0x82.toByte())
    private val unknown = byteArrayOf(0x6D.toByte(), 0x00)

    override fun processCommandApdu(apdu: ByteArray?, extras: Bundle?): ByteArray {
        if (apdu == null || apdu.size < 5) return unknown
        val isSelect = apdu[0] == 0x00.toByte() && apdu[1] == 0xA4.toByte() && apdu[2] == 0x04.toByte()
        if (!isSelect) return unknown
        val len = apdu[4].toInt() and 0xFF
        if (apdu.size < 5 + len) return unknown
        val requested = apdu.copyOfRange(5, 5 + len)
        if (!requested.contentEquals(aid)) return notFound
        val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val payload = prefs.getString("flutter.hce_payload", null) ?: return notFound
        return payload.toByteArray(Charsets.UTF_8) + ok
    }

    override fun onDeactivated(reason: Int) {}
}
