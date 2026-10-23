import '../../presentation/app/bloc/app_bloc.dart';

/// Scoped constructor injection, owned by AiSpeakingApp; no global singleton.
class AppDependencies {
  AppDependencies({
    required AppStartupLoader initialize,
    required void Function() onResumed,
    void Function(Object, StackTrace)? onFailure,
  }) : bloc = AppBloc(
         initialize: initialize,
         onResumed: onResumed,
         onFailure: onFailure,
       );

  final AppBloc bloc;

  Future<void> dispose() => bloc.close();
}

/// Composition override for local app tests; returned scope is owned by the app.
typedef AppDependenciesFactory =
    AppDependencies Function({
      required AppStartupLoader initialize,
      required void Function() onResumed,
    });
