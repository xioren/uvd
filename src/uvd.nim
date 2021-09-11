import std/[parseopt, strutils]
from os import commandLineParams

import vimeo, youtube


proc main() =
  const help = """
    Usage: uvd [options] url

    Options:
      -a, --audio                     Audio Only
      -v, --video                     Video Only
      -f, --format                    Audio Output Format
      -s, --show                      Show Available Streams
      -ai, -aid, --aitag              Audio Stream id/itag
      -vi, -vid, --vitag              Video Stream id/itag
      -h, --help                      Print This Help
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
    lNoVal = @["audio", "video", "show", "help"]

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
        of "a", "audio":
          video = false
        of "v", "video":
          audio = false
        of "s", "show":
          streams = true
        of "f", "format":
          format = val
        of "ai", "aid", "aitag":
          aItag = val
        of "vi", "vid", "vitag":
          vItag = val

    if unknownUrl.contains("vimeo"):
      vimeoDownload(unknownUrl, audio, video, streams, format, aItag, vItag)
    elif unknownUrl.contains("youtu"):
      youtubeDownload(unknownUrl, audio, video, streams, format, aItag, vItag)
    else:
      echo "<invalid url>"


when isMainModule:
  main()
