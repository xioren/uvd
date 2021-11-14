import std/[parseopt, strutils]
from os import commandLineParams

import vimeo, youtube


proc main() =
  const
    version = "1.9.0"
    help = """
      usage: uvd [options] url

      options:
        -a, --audio-only                audio only
        -v, --video-only                video only
        -f, --format                    audio output format
        -s, --show                      show available streams
        --audio-id, --audio-itag        audio stream id/itag
        --video-id, --video-itag        video stream id/itag
        -h, --help                      print this help
        --version                       print version
      """

  var
    args = commandLineParams()
    audio = true
    video = true
    debug: bool
    streams: bool
    aItag = "0"
    vItag = "0"
    format = "ogg"
    unknownUrl: string

  const
    sNoVal = {'a', 'v', 's', 'h'}
    lNoVal = @["audio-only", "video-only", "show", "help", "debug"]
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
          video = false
        of "v", "video-only":
          audio = false
        of "s", "show":
          streams = true
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
        of "version":
          echo version
          return
        else:
          echo "<invalid arguments>"
          return

    if unknownUrl.contains("vimeo"):
      vimeoDownload(unknownUrl, audio, video, streams, format, aItag, vItag, debug)
    elif unknownUrl.contains("youtu"):
      youtubeDownload(unknownUrl, audio, video, streams, format, aItag, vItag, debug)
    else:
      echo "<invalid url>"


when isMainModule:
  main()
