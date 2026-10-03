// 验证移除 YouTube 功能后，保留层仍满足播放器依赖的强类型契约。

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:history_manager/history_manager.dart';
import 'package:playlist_manager/playlist_manager.dart';

import 'package:namida/core/enums.dart';
import 'package:namida/youtube/class/youtube_id.dart';
import 'package:namida/youtube/controller/youtube_controller.dart';
import 'package:namida/youtube/controller/youtube_playlist_controller.dart';

// 覆盖播放器直接依赖的 YouTube 占位契约。
void main() {
  test('空流结果暴露稳定的强类型字段', () {
    const result = VideoStreamsResult();

    expect(result.audioStreams, isEmpty);
    expect(result.videoStreams, isEmpty);
    expect(result.mixedStreams, isEmpty);
    expect(result.info, isNull);
    expect(result.loudnessDBData, isNull);
    expect(result.hlsManifestUrl, isNull);
    expect(result.dashManifestUrl, isNull);
    expect(result.hasExpired(), isTrue);
    expect(result.playability.status.name, isNotEmpty);
  });

  test('流选择方法接受播放器当前使用的命名参数', () {
    const audioStreams = <AudioStream>[];
    const videoStreams = <VideoStream>[];

    final AudioStream? audio = YoutubeController.getPreferredAudioStream(audioStreams);
    final AudioStream? matchedAudio = YoutubeController.matchAudioStreamOrSimilar(audioStreams, null, prefferedItag: '140');
    final VideoStream? video = YoutubeController.getPreferredStreamQuality(videoStreams, preferIncludeWebm: false);
    final VideoStream? matchedVideo = YoutubeController.matchVideoStreamOrSimilar(videoStreams, null, prefferedItag: '137');

    expect([audio, matchedAudio, video, matchedVideo], everyElement(isNull));
  });

  test('缩略图占位接口保留异步命名参数', () async {
    const item = YoutubeID(id: 'video-id');

    final File? thumbnail = await item.getThumbnail(temp: false);

    expect(thumbnail, isNull);
  });

  test('已知空标识会被识别为占位视频', () {
    expect(YoutubeID.fake.id.isDummyVideoId, isTrue);
  });

  test('收藏占位接口接受通知刷新参数', () {
    final bool? changed = YoutubePlaylistController.inst.favouriteButtonOnPressed('video-id', refreshNotification: false);

    expect(changed, isNull);
  });

  test('远端播放列表来源保留服务器和远端标识', () {
    const source = PlaylistRemoteSource(sourceKey: 'server', remoteId: 'remote');

    expect(source.sourceKey, 'server');
    expect(source.remoteId, 'remote');
    expect(PlaylistRemoteSource.none, isNull);
  });

  test('YouTube 空壳保留页面、音轨和枚举契约', () {
    const audioTrack = AudioTrack(id: 'en', langCode: 'en', displayName: 'English', isDefault: true);
    const playlistInfo = PlaylistBasicInfo(id: 'p', title: 'Playlist', videosCountText: '1', videosCount: 1, thumbnails: []);

    expect(audioTrack.langCode, 'en');
    expect(playlistInfo.videosCount, 1);
    expect(const YouTubeHomeView(), isA<Widget>());
    expect(const VideoInfoDialog(videoId: 'v'), isA<Widget>());
    expect(const YTChannelSubpage(channelID: 'c'), isA<Widget>());
    expect(
      const YTPlaylistDownloadPage(ids: [YoutubeID(id: 'v')], playlistName: 'p', infoLookup: {}, playlistInfo: playlistInfo),
      isA<Widget>(),
    );
    expect(
      SponsorBlockAction.values,
      [
        SponsorBlockAction.showInSeekbar,
        SponsorBlockAction.showSkipButton,
        SponsorBlockAction.autoSkip,
        SponsorBlockAction.autoSkipOnce,
        SponsorBlockAction.disabled,
      ],
    );
    expect(CommentsSortType.values, [CommentsSortType.top, CommentsSortType.newest]);
  });

  test('YouTube 控制器满足剩余通用管理器类型', () {
    expect(YoutubePlaylistController.inst, isA<PlaylistManager<YoutubeID, String, YTSortType>>());
    expect(YoutubeHistoryController.inst, isA<HistoryManager<YoutubeID, String>>());
  });
}
