from os import commandLineParams
from sequtils import keepIF
from strutils import contains

import vimeo, youtube


when isMainModule:
  const
    acceptedOpts = ["-a", "--audio", "-v", "--video", "-h", "--help"]
    help = """
  Usage: uvd [options] url

  Options:
    -a, --audio                     Audio only
    -v, --video                     Video only
    -h, --help                      Print this help
  """
  var
    args = commandLineParams()
    audio = true
    video = true

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
      else:
        discard

    args.keepIf(filter)

    if args.len != 1:
      echo "<invalid arguments>"
    else:
      let unknownUrl = args[0]
      if unknownUrl.contains("vimeo"):
        vimeoDownload(unknownUrl, audio, video)
      elif unknownUrl.contains("youtu"):
        youtubeDownload(unknownUrl, audio, video)
      else:
        echo "<invalid url>"
