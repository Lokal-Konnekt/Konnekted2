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


// These are advertised source properties, not the actual decoder/output rate.
// Prefer explicit numerical fields over broad provider labels. Never substitute
// "24-bit / 96 kHz" merely because the catalogue says HI_RES_LOSSLESS.
String catalogueAudioDetails({
  String? quality,
  int? bitDepth,
  int? sampleRate,
  String? codec,
}) {
  final bits = bitDepth != null && bitDepth >= 8 && bitDepth <= 64
      ? bitDepth : null;
  final hz = sampleRate != null && sampleRate >= 8000 && sampleRate <= 768000
      ? sampleRate : null;
  final supplied = catalogueQualityLabel(quality);
  final bitText = bits == null ? null : '$bits-bit';
  String? rateText;
  if (hz != null) {
    final rate = hz / 1000;
    rateText = '${rate == rate.roundToDouble() ? rate.toStringAsFixed(0) : rate.toStringAsFixed(1)} kHz';
  }
  final resolved = <String>[
    if (bitText != null) bitText,
    if (rateText != null) rateText,
  ];
  // A string may contain one of the measurements without the other.
  if (supplied.isNotEmpty) {
    final hasBits = RegExp(r'\d+\s*-?\s*bit', caseSensitive: false).hasMatch(supplied);
    final hasRate = RegExp(r'\d+(?:\.\d+)?\s*kHz', caseSensitive: false).hasMatch(supplied);
    if (resolved.isEmpty || (bits == null && hasBits) || (hz == null && hasRate)) {
      if (resolved.isEmpty) {
        resolved.add(supplied);
      } else {
        final extra = <String>[];
        if (bits == null && hasBits) {
          final match = RegExp(r'\d+\s*-?\s*bit', caseSensitive: false).firstMatch(supplied);
          if (match != null) extra.add(match.group(0)!.replaceAll(RegExp(r'\s+'), ''));
        }
        if (hz == null && hasRate) {
          final match = RegExp(r'\d+(?:\.\d+)?\s*kHz', caseSensitive: false).firstMatch(supplied);
          if (match != null) extra.add(match.group(0)!.replaceAll(RegExp(r'\s+'), ' '));
        }
        resolved.addAll(extra);
      }
    }
  }
  final format = codec?.trim().toUpperCase() ?? '';
  if (format.isNotEmpty && format.length <= 12 &&
      !resolved.any((part) => part.toUpperCase() == format)) {
    return [format, ...resolved].join(' · ');
  }
  return resolved.join(' / ');
}
