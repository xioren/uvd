import std/[parseopt, strutils]
from os import commandLineParams

import vimeo, youtube


proc main() =
  const help = """
    usage: uvd [options] url

    options:
      -a, --audio-only                audio only
      -v, --video-only                video only
      -f, --format                    audio output format
      -s, --show                      show available streams
      --audio-id, --audio-itag        audio stream id/itag
      --video-id, --video-itag        video stream id/itag
      -h, --help                      print this help
    """
  # WIP
  # NOTE: each encoder will require different ffmpeg settings
  # TODO: add logic to check if audio stream is already in the desired format
  # audioExtensions = {"aac": "aac", "flac": "flac", "mp3": "mp3", "m4a": "mp4a",
  #                    "mp4a": "mp4a", "opus": "opus", "vorbis": "ogg", "ogg": "ogg",
  #                    "wav": "wave", "wave": "wave"}.toTable()
  var
    args = commandLineParams()
    audio = true
    video = true
    streams: bool
    aItag = "0"
    vItag = "0"
    format = "mp3"
    unknownUrl: string

  const
    sNoVal = {'a', 'v', 's', 'h'}
    lNoVal = @["audio-only", "video-only", "show", "help"]
    acceptedFormats = ["aac", "ac3", "flac", "mp3", "ogg", "wave", "wav"]

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

    if unknownUrl.contains("vimeo"):
      vimeoDownload(unknownUrl, audio, video, streams, format, aItag, vItag)
    elif unknownUrl.contains("youtu"):
      youtubeDownload(unknownUrl, audio, video, streams, format, aItag, vItag)
    else:
      echo "<invalid url>"


when isMainModule:
  main()
