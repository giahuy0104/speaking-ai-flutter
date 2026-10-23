abstract final class MediaAudioKeys {
  static const h20SpeakerTest = 'system.h20.speaker_test';
  static const rewardStarTing = 'system.reward.star_ting';

  static const songA067T05 = 'song.A067_T05.full.en';
  static const songA067T07 = 'song.A067_T07.full.en';
  static const songA067T08 = 'song.A067_T08.full.en';
  static const songA0810T03 = 'song.A0810_T03.full.en';
  static const songA0810T04 = 'song.A0810_T04.full.en';

  static final Uri h20SpeakerTestUri = Uri(
    scheme: 'asset',
    path: 'assets/audio/A-3-5/GUIDE_RECORD/A035_GUIDE_RECORD_01.mp3',
  );
  static final Uri rewardStarTingUri = Uri(
    scheme: 'asset',
    path: '/assets/audio/MAIN/SFX_STAR_TING.mp3',
  );

  static final Map<String, String> _songKeyByContentId = <String, String>{
    'C35-L1-T02-B02_SONG': songA067T05,
    'C35-L3-T09-B02_SONG': songA067T08,
    'C35-L3-T10-B02_SONG': songA067T07,
    'C67-L3-T08-B01_SONG': songA0810T04,
    'C810-L1-T01-B02_SONG': songA0810T03,
  };

  static final Map<String, Uri> _songAssetByKey = <String, Uri>{
    songA067T05: Uri(
      scheme: 'asset',
      path: '/assets/audio/A-6-7/SONGS/A067_T05_SONG01_FULL_EN.mp3',
    ),
    songA067T07: Uri(
      scheme: 'asset',
      path: '/assets/audio/A-6-7/SONGS/A067_T07_SONG01_FULL_EN.mp3',
    ),
    songA067T08: Uri(
      scheme: 'asset',
      path: '/assets/audio/A-6-7/SONGS/A067_T08_SONG01_FULL_EN.mp3',
    ),
    songA0810T03: Uri(
      scheme: 'asset',
      path: '/assets/audio/A-8-10/SONGS/A0810_T03_SONG01_FULL_EN.mp3',
    ),
    songA0810T04: Uri(
      scheme: 'asset',
      path: '/assets/audio/A-8-10/SONGS/A0810_T04_SONG01_FULL_EN.mp3',
    ),
  };

  static String? songKeyForContentId(String? contentId) =>
      contentId == null ? null : _songKeyByContentId[contentId.trim()];

  static Uri? bundledSongUri(String? contentId) {
    final key = songKeyForContentId(contentId);
    return key == null ? null : _songAssetByKey[key];
  }
}
