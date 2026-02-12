String? validateStrongPassword(String value) {
  final v = value;
  if (v.contains(RegExp(r'\s'))) {
    return 'Password must not contain spaces.';
  }
  if (v.length < 8) {
    return 'Password must be at least 8 characters.';
  }
  if (!RegExp(r'[A-Z]').hasMatch(v)) {
    return 'Include at least one uppercase letter.';
  }
  if (!RegExp(r'[a-z]').hasMatch(v)) {
    return 'Include at least one lowercase letter.';
  }
  if (!RegExp(r'\d').hasMatch(v)) {
    return 'Include at least one number.';
  }
  if (!RegExp(r'''[!@#$%^&*(),.?":{}|<>_\-+=/\\\[\];'`~]''').hasMatch(v)) {
    return 'Include at least one special character.';
  }
  return null;
}

String? validateKenyanPhone(String value) {
  final v = value.trim();
  if (v.isEmpty) {
    return 'Phone number is required.';
  }
  try {
    normalizeKenyanPhoneToE164(v);
    return null;
  } catch (_) {
    return 'Enter a valid Kenyan phone number.';
  }
}

String normalizeKenyanPhoneToE164(String value) {
  var v = value.replaceAll(RegExp(r'[\s\-]'), '');
  if (v.startsWith('+')) {
    v = v.substring(1);
  }
  if (!RegExp(r'^\d+$').hasMatch(v)) {
    throw const FormatException('Invalid phone number');
  }

  if (v.startsWith('2547') || v.startsWith('2541')) {
    if (v.length != 12) {
      throw const FormatException('Invalid phone number length');
    }
    return '+$v';
  }

  if (v.startsWith('07') || v.startsWith('01')) {
    if (v.length != 10) {
      throw const FormatException('Invalid phone number length');
    }
    return '+254${v.substring(1)}';
  }

  if (v.startsWith('7') || v.startsWith('1')) {
    if (v.length != 9) {
      throw const FormatException('Invalid phone number length');
    }
    return '+254$v';
  }

  throw const FormatException('Invalid phone number');
}

String? validateKenyanDrivingLicense(String value) {
  final v = value.trim();
  if (v.isEmpty) {
    return 'License number is required.';
  }
  if (!RegExp(r'^[A-Za-z0-9]{5,20}$').hasMatch(v)) {
    return 'Use 5-20 letters or numbers (no spaces).';
  }
  return null;
}
