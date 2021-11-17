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
  -c, --captions                  download captions
  --audio-id, --audio-itag        audio stream id/itag
  --video-id, --video-itag        video stream id/itag
  -h, --help                      print this help
  --version                       print version
```

### NOTE:
  a country code can be given as the argument to -c, --captions to select
  the desired language output of the subtitles.
