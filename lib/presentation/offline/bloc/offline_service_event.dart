part of 'offline_service_bloc.dart';

sealed class OfflineServiceEvent {
  final _completed = Completer<void>();
}

final class OfflineServiceRefreshRequested extends OfflineServiceEvent {}

final class OfflineServiceAutomaticDownloadChanged extends OfflineServiceEvent {
  OfflineServiceAutomaticDownloadChanged(this.enabled);
  final bool enabled;
}

final class _OfflineServicePrepareRequested extends OfflineServiceEvent {}
