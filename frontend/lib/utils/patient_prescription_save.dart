import 'dart:typed_data';

import 'patient_prescription_save_stub.dart'
    if (dart.library.html) 'patient_prescription_save_web.dart'
    if (dart.library.io) 'patient_prescription_save_io.dart' as platform;

Future<String> savePatientPrescriptionPdf(Uint8List bytes, String filename) =>
    platform.savePatientPrescriptionPdf(bytes, filename);
