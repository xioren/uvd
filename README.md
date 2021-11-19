### uvd: yo[u]tube [v]imeo [d]ownloader


+ fast downloader for youtube and vimeo
+ requires ffmpeg
+ *nix only


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
  -a, --audio-only                audio only
  -v, --video-only                video only
  -f, --format                    audio output format
  -s, --show                      show available streams
  -t, --thumb                     download thumbnail
  -S, --subtitles                 download subtitles
  -l, --language                  desired subtitle language
  --audio-id, --audio-itag        audio stream id/itag
  --video-id, --video-itag        video stream id/itag
  -h, --help                      print this help
  -V, --version                   print version
```

#### USAGE NOTES:
  + a country (ISO) code is given as the argument to --language to select
  the desired language output of the subtitles; forgoing this argument selects the default
  subtitle language for a given video. for youtube, if the desired language
  does not exist natively, a translation is used instead (when available).
