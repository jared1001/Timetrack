import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter_auth_practice/services/attendance_qr_payload.dart';

void main() {
  const token = '8f14e45f-ea2f-4f6a-9b12-a3c4d5e6f789';

  test('accepts a TimeTrack attendance token payload', () {
    expect(
      decodeAttendanceQrToken(
        '{"type":"timetrack_attendance","token":"$token"}',
      ),
      token,
    );
  });

  test('rejects non-attendance and malformed QR payloads', () {
    expect(decodeAttendanceQrToken('not json'), isNull);
    expect(
      decodeAttendanceQrToken('{"type":"other","token":"$token"}'),
      isNull,
    );
    expect(
      decodeAttendanceQrToken(
        '{"type":"timetrack_attendance","token":"not-a-uuid"}',
      ),
      isNull,
    );
  });
}
