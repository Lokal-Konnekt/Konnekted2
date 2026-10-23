/// Formats metadata advertised by a provider, not the decoded audio output.
/// Never synthesizes 44.1/48/96 kHz for a bit-depth-only response.
String catalogueQualityLabel(String? value) {
  final text = value?.trim() ?? '';
  if (text.isEmpty) return '';
  final bits = RegExp(r'(?:^|[^0-9])(16|24|32)\s*-?\s*bits?', caseSensitive: false)
      .firstMatch(text)?.group(1);
  final khz = RegExp(
    r'(\d{2,3}(?:\.\d+)?)\s*k(?:hz)?',
    caseSensitive: false,
  ).firstMatch(text)?.group(1);
  if (bits != null || khz != null) {
    return [
      if (bits != null) '$bits-bit',
      if (khz != null) '${double.parse(khz).toStringAsFixed(khz.contains('.') ? 1 : 0)} kHz',
    ].join(' / ');
  }
  switch (text.toUpperCase()) {
    case 'HI_RES_LOSSLESS':
      return 'Hi-res lossless';
    case 'LOSSLESS':
      return 'Lossless';
    case 'HIGH':
      return 'High';
    case 'LOW':
      return 'Low';
  }
  return text.length < 42 ? text : '';
}
