part of 'offline_service_bloc.dart';

class OfflineServiceState {
  const OfflineServiceState({
    required this.isAndroid,
    this.consent = AndroidOfflineSpeechModelConsent.undecided,
    this.status,
    this.preparation,
    this.busy = true,
    this.preparingIosModels = false,
    this.noticeRevision = 0,
    this.saveFailed = false,
  });
  final bool isAndroid;
  final AndroidOfflineSpeechModelConsent consent;
  final AndroidOfflineSpeechModelStatus? status;
  final AndroidOfflineSpeechModelPreparationResult? preparation;
  final bool busy;
  final bool preparingIosModels;
  final int noticeRevision;
  final bool saveFailed;

  OfflineServiceState copyWith({
    AndroidOfflineSpeechModelConsent? consent,
    AndroidOfflineSpeechModelStatus? status,
    AndroidOfflineSpeechModelPreparationResult? preparation,
    bool clearPreparation = false,
    bool? busy,
    bool? preparingIosModels,
    bool notify = false,
    bool saveFailed = false,
  }) => OfflineServiceState(
    isAndroid: isAndroid,
    consent: consent ?? this.consent,
    status: status ?? this.status,
    preparation: clearPreparation ? null : preparation ?? this.preparation,
    busy: busy ?? this.busy,
    preparingIosModels: preparingIosModels ?? this.preparingIosModels,
    noticeRevision: noticeRevision + (notify ? 1 : 0),
    saveFailed: notify ? saveFailed : this.saveFailed,
  );
}
