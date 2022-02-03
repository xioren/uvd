+ improve commenting (ongoing)
+ handle vimeo "channels" (playlists) -> eg: https://vimeo.com/channels/1186230
+ view available subtitle languages with --show? other flag?
+ more robust solution to bitrate/average bitrate comparations
+ windows support
+ handle 429 errors
+ correct malformed error message:
  [error] 0eceived length doesn't match expected length. Wanted 344325615 got: 95632688
  [error] failed to download video stream
  [error] no streams were downloaded
+ hls manifest parsing
 hls is for combined audio + videos streams (youtube premium downloads) while dash manifest
 is for single audio or videos streams.
+ fix segment content lengths reporting as 0
