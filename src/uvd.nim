from os import commandLineParams
from sequtils import keepIF
from strutils import contains
# import tables

import vimeo, youtube


proc main() =
  const
    acceptedOpts = ["-a", "--audio", "-v", "--video", "-h", "--help",
                    "-f", "--format", "-s", "--show", "-i", "--id"]
    help = """
  Usage: uvd [options] url

  Options:
    -a, --audio                     Audio Only
    -v, --video                     Video Only
    -f, --format                    Audio Output Format
    -s, --show                      Show Available Streams
    -i, --id                        Stream Id
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
    id: string
    format = "mp3"

  proc filter(x: string): bool =
    ## filter out parsed options
    not acceptedOpts.contains(x)

  if args.len < 1:
    echo help
  else:
    for arg in args:
      case arg
      of "-a", "--audio":
        video = false
      of "-v", "--video":
        audio = false
      of "-f", "--format":
        format = arg
        # WIP
        # if audioExtensions.contains(arg):
        #   format = audioExtensions[arg]
        # else:
        #   echo "<invalid audio format>"
        #   return
      of "-s", "--show":
        streams = true
      of "-i", "--id":
        id = arg
      of "-h", "--help":
        echo help
        return
      else:
        discard

    args.keepIf(filter)

    if args.len != 1:
      echo "<invalid arguments>"
    else:
      let unknownUrl = args[0]
      if unknownUrl.contains("vimeo"):
        vimeoDownload(unknownUrl, audio, video, streams, format)
      elif unknownUrl.contains("youtu"):
        youtubeDownload(unknownUrl, audio, video, streams, format)
      else:
        echo "<invalid url>"


when isMainModule:
  main()
