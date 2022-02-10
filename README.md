### uvd: yo[u]tube [v]imeo [d]ownloader


+ fast downloader for youtube and vimeo
+ zero regex
+ requires ffmpeg


*youtube:*
  + videos
  + shorts
  + channels
  + playlists

*vimeo:*
  + videos
  + profiles


```
usage: uvd [options] url

options:
  -a, --audio-only                    audio only
  -v, --video-only                    video only
  --audio-id <id>                     audio stream id
  --video-id <id>                     video stream id
  -f, --format <format>               audio output format
  -h, --help                          print this help
  -l, --language <iso code>           desired subtitle language
  --prefer-acodec <acodec>            audio codec to prefer
  --prefer-vcodec <vcodec>            video codec to prefer
  -s, --show                          show available streams
  --silent                            suppress output
  -S, --subtitles                     download subtitles
  -t, --thumb                         download thumbnail
  -V, --version                       print version
```

#### USAGE NOTES:
  + requires ssl compile with: ```nim c -d:ssl -d:release uvd.nim```
  + a country (ISO) code is given as the argument to --language to select
  the desired language output of the subtitles; forgoing this option selects the default
  subtitle language for a given video. for youtube, if the desired language
  does not exist natively, a translation is used instead (when available).
