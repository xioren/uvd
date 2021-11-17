import std/[parseopt, strutils]
from os import commandLineParams

import vimeo, youtube


proc main() =
  const
    version = "2.0.0"
    help = """
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
      """

  var
    args = commandLineParams()
    iAudio = true
    iVideo = true
    iThumb: bool
    iSubtitles: bool
    debug: bool
    streams: bool
    aItag = "0"
    vItag = "0"
    format = "ogg"
    desiredLanguage: string
    unknownUrl: string

  const
    sNoVal = {'s', 'h', 'S'}
    lNoVal = @["audio-only", "video-only", "subtitles", "show", "help", "debug", "thumb"]
    acceptedFormats = ["aac", "flac", "m4a", "mp3", "ogg", "wav"]

  if args.len < 1:
    echo help
  else:
    for kind, key, val in getopt(shortNoVal=sNoVal, longNoVal=lNoVal):
      case kind
      of cmdEnd:
        return
      of cmdArgument:
        unknownUrl = key
      of cmdShortOption, cmdLongOption:
        case key
        of "h", "help":
          echo help
          return
        of "debug":
          debug = true
        of "a", "audio-only":
          iVideo = false
        of "v", "video-only":
          iAudio = false
        of "s", "show":
          streams = true
        of "t", "thumb":
          iThumb = true
        of "S", "subtitles":
          iSubtitles = true
        of "l", "language":
          desiredLanguage = val
        of "f", "format":
          if val in acceptedFormats:
            format = val
          else:
            echo "accepted audio formats: ", acceptedFormats
            return
        of "audio-id", "audio-itag":
          aItag = val
        of "video-id", "video-itag":
          vItag = val
        of "V", "version":
          echo version
          return
        else:
          echo "<invalid arguments>"
          return

    if unknownUrl.contains("vimeo"):
      vimeoDownload(unknownUrl, format, aItag, vItag, desiredLanguage, iAudio, iVideo, iThumb, iSubtitles, streams, debug)
    elif unknownUrl.contains("youtu"):
      youtubeDownload(unknownUrl, format, aItag, vItag, desiredLanguage, iAudio, iVideo, iThumb, iSubtitles, streams, debug)
    else:
      echo "<invalid url>"

when isMainModule:
  main()
