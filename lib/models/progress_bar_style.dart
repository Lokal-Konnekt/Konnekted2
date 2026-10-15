enum ProgressBarStyle { waveform, line }

extension ProgressBarStyleX on ProgressBarStyle {
  String get storageValue {
    switch (this) {
      case ProgressBarStyle.waveform:
        return 'waveform';
      case ProgressBarStyle.line:
        return 'line';
    }
  }

  static ProgressBarStyle fromStorageValue(String? value) {
    switch (value) {
      case 'line':
        return ProgressBarStyle.line;
      case 'waveform':
      default:
        return ProgressBarStyle.waveform;
    }
  }
}
