import std/[parseopt, strutils]
from os import commandLineParams

import vimeo, youtube


proc main() =
  const
    version = "0.1.3"
    help = """
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
      """

  var
    args = commandLineParams()
    iAudio = true
    iVideo = true
    iThumb: bool
    iSubtitles: bool
    debug: bool
    streams: bool
    silent: bool
    aId: string
    vId: string
    aCodec: string
    vCodec: string
    format = "ogg"
    desiredLanguage: string
    unknownUrl: string

  const
    sNoVal = {'a', 'v', 's', 'h', 'S'}
    lNoVal = @["audio-only", "debug", "help", "show", "silent", "subtitles", "thumb", "video-only"]
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
        of "a", "audio-only":
          iVideo = false
        of "audio-id":
          aId = val
        of "debug":
          debug = true
        of "f", "format":
          if val in acceptedFormats:
            format = val
          else:
            echo "accepted audio formats: ", acceptedFormats
            return
        of "h", "help":
          echo help
          return
        of "l", "language":
          desiredLanguage = val
        of "prefer-acodec":
          aCodec = val
        of "prefer-vcodec":
          vCodec = val
        of "s", "show":
          streams = true
        of "silent":
          silent = true
        of "S", "subtitles":
          iSubtitles = true
        of "t", "thumb":
          iThumb = true
        of "V", "version":
          echo "uvd ", version
          return
        of "video-id":
          vId = val
        of "v", "video-only":
          iAudio = false
        else:
          echo "invalid argument: ", key
          return

    if unknownUrl.contains("vimeo"):
      vimeoDownload(unknownUrl, format, aId, vId, aCodec, vCodec, desiredLanguage,
                    iAudio, iVideo, iThumb, iSubtitles, streams, debug, silent)
    elif unknownUrl.contains("youtu"):
      youtubeDownload(unknownUrl, format, aId, vId, aCodec, vCodec, desiredLanguage,
                      iAudio, iVideo, iThumb, iSubtitles, streams, debug, silent)
    else:
      echo "invalid url: ", unknownUrl

when isMainModule:
  main()
