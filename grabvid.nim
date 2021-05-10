from os import commandLineParams
from strutils import contains

import vimeo, youtube


when isMainModule:
  let args = commandLineParams()
  if args.len < 1:
    echo "<no argument>"
  else:
    let unknownUrl = args[0]
    if unknownUrl.contains("vimeo.com"):
      main(VimeoUri(url: unknownUrl))
    elif unknownUrl.contains("youtu"):
      main(YoutubeUri(url: unknownUrl))
    else:
      echo "[invalid url]"
