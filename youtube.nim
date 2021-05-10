import std/[json, uri, algorithm, sequtils, parseutils]

import utils


type
  Stream = object
    name: string
    itag: int
    mime: string
    ext: string
    size: string
    quality: string
    url: string

  YoutubeUri* = object
    url*: string


const
  query = "&pbj=1"
  bypassUrl = "https://www.youtube.com/get_video_info?video_id="
  bypassQueryA = "&html5=1&eurl&ps=desktop-polymer&el=adunit&cbr=Chrome&cplatform=DESKTOP&break_type=1&autoplay=1&content_v&authuser=0"
  bypassQueryB = "&eurl=https%3A%2F%2Fyoutube.googleapis.com%2Fv%2F"


########################################################
# cipher logic
########################################################
# NOTE: thanks to https://github.com/pytube/pytube/blob/master/pytube/cipher.py
# as a reference

proc getParts(cipherSignature: string): tuple[url, sc, s: string] =
  ## break cipher string into (url, sc, s)
  let parts = cipherSignature.split('&')
  result = (decodeUrl(parts[2].split('=')[1]), parts[1].split('=')[1], decodeUrl(parts[0].split('=')[1]))


proc reverseIt(a: var seq[char]) =
  ## function(a, b){a.reverse()}
  a.reverse()


proc splice(a: var seq[char], b: Natural) =
  ## function(a, b){a.splice(0, b)}
  a.delete(0, -1 + b)


proc swap(a: var seq[char], b: Natural) =
  ## function(a,b){var c=a[0];a[0]=a[b%a.length];a[b%a.length]=c}
  let c = a[0]
  a[0] = a[b mod a.len]
  a[b mod a.len] = c


proc parseMainFunction(plan: seq[string]): string =
  ## get the name of the function containing the scramble functions
  ## ix.Nh(a,2) --> ix
  plan[0].parseIdent()


proc parseFunctionPlan(js: string): seq[string] =
  ## get the scramble functions
  ## @["ix.Nh(a,2)", "ix.ai(a,5)", "ix.wW(a,62)", "ix.Nh(a,1)", "ix.wW(a,39)",
  ## "ix.ai(a,41)", "ix.Nh(a,3)"]
  var matches: array[1, string]
  # NOTE: matches vy=function(a){a=a.split("");uy.bH(a,3);uy.Fg(a,7);uy.Fg(a,50);
  # uy.S6(a,71);uy.bH(a,2);uy.S6(a,80);uy.Fg(a,38);return a.join("")};
  let functionPatterns = [re"([a-z]{2}\=function\(a\)\{a\=a\.split\([^\(]+\);[a-z]{2}\.[^\n]+)"]
  for pattern in functionPatterns:
    discard js.find(pattern, matches)
  matches[0].split(';')[1..^3]


proc createFunctionMap(js, mainFunc: string): Table[string, string] =
  ## get which functions correspond which function names
  ## {"ai": "function(a,b){var c=a[0];a[0]=a[b%a.length];a[b%a.length]=c}",
  ## "wW": "function(a){a.reverse()}", "Nh": "function(a,b){a.splice(0,b)}"}
  var matches: array[1, string]
  let pattern = re("(?<=var $1={)(.+?)(?=};)" % mainFunc, flags={reDotAll})
  discard js.find(pattern, matches)
  for item in matches[0].split(",\n"):
    let parts = item.split(':')
    result[parts[0]] = parts[1]


proc parseFunction(function: string): tuple[name: string, argument: int] =
  ## returns function name and int argument
  ## ix.ai(a,5) --> (ai, 5)
  result.name = function.captureBetween('.', '(')
  result.argument = parseInt(function.captureBetween(',', ')'))


proc decipher(js, signature: string): string =
  ## decipher signature
  var splitSig = @signature
  let
    plan = parseFunctionPlan(js)
    mainFunc = parseMainFunction(plan)
    map = createFunctionMap(js, mainFunc)

  for item in plan:
    let (funcName, argument) = parseFunction(item)
    if map[funcName].contains("reverse"):
      reverseIt(splitSig)
    elif map[funcName].contains("splice"):
      splice(splitSig, argument)
    else:
      swap(splitSig, argument)
  result = splitSig.join("")


proc getSigCipherUrl(js, signatureCipher: string): string =
  ## produce url with deciphered signature
  let parts = getParts(signatureCipher)
  result = parts.url & "&" & parts.sc & "=" & encodeUrl(decipher(js, parts.s))


########################################################
# stream logic
########################################################


proc selectBestVideoStream(streams: JsonNode): JsonNode =
  # NOTE: zeroth stream always seems to be the best* quality
  result = streams[0]


proc selectBestAudioStream(streams: JsonNode): JsonNode =
  var largest = 0
  for stream in streams:
    if stream.contains("audioQuality"):
      if stream["bitrate"].getInt() > largest:
        largest = stream["bitrate"].getInt()
        result = stream


proc getVideoStreamInfo(stream: JsonNode): tuple[itag: int, mime, ext, size, qlt: string] =
  result.itag = stream["itag"].getInt()
  result.mime = stream["mimeType"].getStr().split(";")[0]
  result.ext = extensions[result.mime]
  result.size = formatSize(parseInt(stream["contentLength"].getStr()), includeSpace=true)
  result.qlt = stream["qualityLabel"].getStr()


proc getAudioStreamInfo(stream: JsonNode): tuple[itag: int, mime, ext, size, qlt: string] =
  result.itag = stream["itag"].getInt()
  result.mime = stream["mimeType"].getStr().split(";")[0]
  result.ext = extensions[result.mime]
  result.size = formatSize(parseInt(stream["contentLength"].getStr()), includeSpace=true)
  result.qlt = stream["audioQuality"].getStr()


proc urlOrCipher(youtubeUrl: string, stream: JsonNode): string =
  ## produce stream url, deciphering if necessary
  if stream.contains("url"):
    result = stream["url"].getStr()
  elif stream.contains("signatureCipher"):
    let
      webpage = get(youtubeUrl)
      jsUrl = "https://www.youtube.com" & webpage.captureBetween('"', '"', webpage.find("\"jsUrl\":\"") + 7)
      baseJs = get(jsUrl)
    result = getSigCipherUrl(baseJs, stream["signatureCipher"].getStr())


proc newVideoStream(youtubeUrl: string, stream: JsonNode): Stream =
  (result.itag, result.mime, result.ext, result.size, result.quality) = getVideoStreamInfo(stream)
  result.name = addFileExt("videostream", result.ext)
  result.url = urlOrCipher(youtubeUrl, stream)


proc newAudioStream(youtubeUrl: string, stream: JsonNode): Stream =
  (result.itag, result.mime, result.ext, result.size, result.quality) = getAudioStreamInfo(stream)
  result.name = addFileExt("audiostream", result.ext)
  result.url = urlOrCipher(youtubeUrl, stream)


proc tryBypass(bypassUrl: string): JsonNode =
  ## get new response using bypass url
  var matches: array[1, string]
  let bypassResponse = decodeUrl(get(bypassUrl))
  discard bypassResponse.find(re("({\"responseContext\".+})"), matches)
  result = parseJson(matches[0])


proc reportStreamInfo(stream: Stream) =
  echo "stream: ", stream.name, "\n",
       "itag: ", stream.itag, '\n',
       "size: ", stream.size, '\n',
       "quality: ", stream.quality, '\n',
       "mime: ", stream.mime


proc standardizeUrl(youtubeUrl: string): string =
  if youtubeUrl.contains("youtu.be"):
    result = "https://www.youtube.com/watch?v=" & youtubeUrl.captureBetween('/', '?', 8)
  else:
    result = "https://www.youtube.com/watch?v=" & youtubeUrl.captureBetween('=', '&')


proc main*(youtubeUrl: YoutubeUri) =
  let standardYoutubeUrl = standardizeUrl(youtubeUrl.url)
  var playerResponse = parseJson(post(standardYoutubeUrl & query))[2]["playerResponse"]
  let
    title = playerResponse["videoDetails"]["title"].getStr()
    safeTitle = title.multiReplace((".", ""), ("/", ""))
    id = playerResponse["videoDetails"]["videoId"].getStr()

  if fileExists(addFileExt(joinPath(getCurrentDir(), safeTitle), ".mkv")):
    echo "<file exists> ", safeTitle
  else:
    if playerResponse["playabilityStatus"]["status"].getStr() == "LOGIN_REQUIRED":
      echo "[attempting age-gate bypass]"
      playerResponse = tryBypass(bypassUrl & encodeUrl(id) & bypassQueryA)
      if playerResponse["playabilityStatus"]["status"].getStr() == "LOGIN_REQUIRED":
        playerResponse = tryBypass(bypassUrl & encodeUrl(id) & bypassQueryB & encodeUrl(id))
        if playerResponse["playabilityStatus"]["status"].getStr() == "LOGIN_REQUIRED":
          echo "<bypass failed>"
          return
    elif playerResponse["playabilityStatus"]["status"].getStr() != "OK":
      echo '<', playerResponse["playabilityStatus"]["reason"].getStr(), '>'
      return

    var
      videoStream = newVideoStream(standardYoutubeUrl, selectBestVideoStream(playerResponse["streamingData"]["adaptiveFormats"]))
      audioStream = newAudioStream(standardYoutubeUrl, selectBestAudioStream(playerResponse["streamingData"]["adaptiveFormats"]))

    echo "title: ", title
    reportStreamInfo(videoStream)
    if grab(videoStream.url, forceFilename=videoStream.name, saveLocation=getCurrentDir()) == "404 Not Found":
      echo "[trying alternate video stream]"
      videoStream = newVideoStream(standardYoutubeUrl, playerResponse["streamingData"]["adaptiveFormats"][1])

      reportStreamInfo(videoStream)
      if grab(videoStream.url, forceFilename=videoStream.name, saveLocation=getCurrentDir()) != "200 OK":
        echo "<failed to obtain a suitable video stream>"
    else:
      reportStreamInfo(audioStream)
      if grab(audioStream.url, forceFilename=audioStream.name, saveLocation=getCurrentDir()) == "200 OK":
        joinStreams(videoStream.name, audioStream.name, safeTitle)
      else:
        echo "<failed to obtain a suitable audio stream>"
