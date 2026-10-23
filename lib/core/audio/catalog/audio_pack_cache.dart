import 'audio_pack_cache_base.dart';
import 'audio_pack_cache_stub.dart'
    if (dart.library.io) 'audio_pack_cache_native.dart'
    if (dart.library.js_interop) 'audio_pack_cache_web.dart'
    as platform;

export 'audio_pack_cache_base.dart';
export 'audio_pack_cache_web.dart' show MemoryAudioPackCache;

AudioPackCache createAudioPackCache() => platform.createAudioPackCache();
