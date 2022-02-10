+ improve commenting (ongoing)
+ handle vimeo "channels" (playlists) -> eg: https://vimeo.com/channels/1186230
+ view available subtitle languages with --show? other flag?
+ more robust solution to bitrate/average bitrate comparations
+ handle 429 errors
+ correct malformed error message:
```
[error] 0eceived length doesn't match expected length. Wanted 344325615 got: 95632688
[error] failed to download video stream
[error] no streams were downloaded
```
+ fix segment content lengths reporting as 0 (youtube)
+ external vimeo https://vimeo.com/videoId
 --> https://player.vimeo.com/external/videoId.hd.mp4?s=44a9bc0663a3f0cd99fbee1877cc245f2d5878b5&profile_id=175
+ consider letting ffmpeg output to standard out when --debug flag is used
