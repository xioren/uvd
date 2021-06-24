from os import commandLineParams
from strutils import contains

import vimeo, youtube


when isMainModule:
  let args = commandLineParams()
  if args.len < 1:
    echo "<no argument>"
  else:
    let unknownUrl = args[0]
    if unknownUrl.contains("vimeo"):
      vimeoDownload(unknownUrl)
    elif unknownUrl.contains("youtu"):
      youtubeDownload(unknownUrl)
    else:
      echo "[invalid url]"
