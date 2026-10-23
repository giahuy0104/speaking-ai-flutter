import '../../features/conversation/application/conversation_settings_port.dart';
import '../../presentation/history/bloc/history_bloc.dart';

/// Creates one Bloc per history sheet. The sheet owns the Bloc; the existing
/// conversation owner retains ownership of backend and audio dependencies.
class HistoryDependencies {
  const HistoryDependencies({required this.history});
  final ConversationHistoryPort history;

  HistoryBloc createBloc() => HistoryBloc(history: history);
}
