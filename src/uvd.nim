import std/[parseopt, strutils]
from os import commandLineParams

import vimeo, youtube


proc main() =
  const
    version = "0.1.0"
    help = """
      usage: uvd [options] url

      options:
        -a, --audio-only                  audio only
        -v, --video-only                  video only
        -f, --format <format>             audio output format
        -s, --show                        show available streams
        -t, --thumb                       download thumbnail
        --silent                          suppress output
        -S, --subtitles                   download subtitles
        -l, --language <iso code>         desired subtitle language
        --audio-id, --audio-itag <itag>   audio stream id/itag
        --video-id, --video-itag <itag>   video stream id/itag
        -h, --help                        print this help
        -V, --version                     print version
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
    aItag = "0"
    vItag = "0"
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
        of "audio-id", "audio-itag":
          aItag = val
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
        of "s", "show":
          streams = true
        of "silent":
          silent = true
        of "S", "subtitles":
          iSubtitles = true
        of "t", "thumb":
          iThumb = true
        of "V", "version":
          echo version
          return
        of "video-id", "video-itag":
          vItag = val
        of "v", "video-only":
          iAudio = false
        else:
          echo "<invalid arguments>"
          return

    if unknownUrl.contains("vimeo"):
      vimeoDownload(unknownUrl, format, aItag, vItag, desiredLanguage,
                    iAudio, iVideo, iThumb, iSubtitles, streams, debug, silent)
    elif unknownUrl.contains("youtu"):
      youtubeDownload(unknownUrl, format, aItag, vItag, desiredLanguage,
                      iAudio, iVideo, iThumb, iSubtitles, streams, debug, silent)
    else:
      echo "<invalid url>"

when isMainModule:
  main()
