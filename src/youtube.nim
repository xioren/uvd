import std/[json, uri, algorithm, sequtils, parseutils]
# import std/[sha1]

import utils

# NOTE: test age gate video https://www.youtube.com/watch?v=HtVdAasjOgU

# NOTE: clientVersion can be found in contextUrl response (along with api key)
const
  playerContext = """{
    "context": {
      "client": {
        "hl": "en",
        "clientName": "WEB",
        "clientVersion": "2.$3.00.00",
        "mainAppWebInfo": {
          "graftUrl": "/watch?v=$1"
        }
      }
    },
    "playbackContext": {
      "contentPlaybackContext": {
        "signatureTimestamp": $2
      }
    },
    "contentCheckOk": true,
    "racyCheckOk": true,
    "videoId": "$1"
  }"""
  playerBypassContext = """{
    "context": {
      "client": {
        "hl": "en",
        "clientName": "WEB_EMBEDDED_PLAYER",
        "clientVersion": "2.$3.00.00",
        "mainAppWebInfo": {
          "graftUrl": "/watch?v=$1"
        }
      }
    },
    "playbackContext": {
      "contentPlaybackContext": {
        "signatureTimestamp": $2
      }
    },
    "contentCheckOk": true,
    "racyCheckOk": true,
    "videoId": "$1"
  }"""
  browseContext = """{
    "browseId": "$1",
    "context": {
      "client": {
        "hl": "en",
        "clientName": "WEB",
        "clientVersion": "2.$2.00.00",
        "mainAppWebInfo": {
          "graftUrl": "/channel/$1/videos"
        }
      }
    },
    "params": "EgZ2aWRlb3M%3D"
  }"""
  browseContinueContext = """{
    "context": {
      "client": {
        "hl": "en",
        "clientName": "WEB",
        "clientVersion": "2.$3.00.00",
        "mainAppWebInfo": {
          "graftUrl": "/channel/$1/videos"
        }
      }
    },
    "continuation": "$2"
  }"""
  playlistContext = """{
    "context": {
      "client": {
        "hl": "en",
        "clientName": "WEB",
        "clientVersion": "2.$1.00.00",
        "mainAppWebInfo": {
          "graftUrl": "/playlist?list=$2"
        }
      }
    },
    "playlistId": "$2"
  }"""

type
  Stream = object
    title: string
    filename: string
    itag: int
    mime: string
    ext: string
    size: string
    quality: string
    url: string
    baseUrl: string
    urlSegments: seq[string]
    dash: bool

const
  playerUrl = "https://youtubei.googleapis.com/youtubei/v1/player?key=AIzaSyAO_FJ2SlqU8Q4STEHLGCilw_Y9_11qcW8"
  browseUrl = "https://youtubei.googleapis.com/youtubei/v1/browse?key=AIzaSyAO_FJ2SlqU8Q4STEHLGCilw_Y9_11qcW8"
  nextUrl = "https://youtubei.googleapis.com/youtubei/v1/next?key=AIzaSyAO_FJ2SlqU8Q4STEHLGCilw_Y9_11qcW8"
  # contextUrl = "https://www.youtube.com/sw.js_data"

let date = now().format("yyyyMMdd")

var
  jsUrl: string
  cipherPlan: seq[string]
  cipherFucntionMap: Table[string, string]
  lastN: string
  calculatedN: string
  throttleCode: string
  throttleArray: seq[string]
  throttlePlan: seq[seq[string]]


########################################################
# misc
########################################################


# proc creatAuthenticationCookie(): string =
#   const xOrigin = "https://www.youtube.com"
#   let
#     timeStamp = toUnix(getTime())
#     sapisid = "" # NOTE: from cookies
#   result = "SAPISIDHASH " & $timeStamp & '_' & $secureHash(timeStamp & ' ' & sapisid & ' ' & xOrigin)


########################################################
# throttle logic
########################################################
# NOTE: thanks to https://github.com/pytube/pytube as a reference

proc index[T](d: seq[T], item: T): int =
  ## provide index of item
  for idx, c in d:
    if c == item:
      return idx


proc throttleModFunction(d: string, e: int): int =
  ## function(d,e){e=(e%d.length+d.length)%d.length
  result = e mod (d.len + d.len) mod d.len


proc throttleModFunction(d: seq[string], e: int): int =
  ## function(d,e){e=(e%d.length+d.length)%d.length
  result = e mod (d.len + d.len) mod d.len


proc throttleUnshift(d: var string, e: int) =
  ## handled prepend also
  d.rotateLeft(d.len - throttleModFunction(d, e))


proc throttleUnshift(d: var seq[string], e: int) =
  ## handled prepend also
  d.rotateLeft(d.len - throttleModFunction(d, e))


proc throttleCipher(d: var string, e: string) =
  const
    h = @"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
  var
    f = 96
    this = e
    temp = d
    bVal: int
  for idx, c in temp:
    bVal = (h.index(c) - h.index(this[idx]) + idx - 32 + f) mod h.len
    this.add(h[bVal])
    d[idx] = h[bVal]
    dec f


proc throttleCipher(d: var seq[string], e: string) =
  # NOTE: needed to compile
  doAssert false


proc throttleReverse(d: var string) =
  d.reverse()


proc throttleReverse(d: var seq[string]) =
  d.reverse()


proc throttlePush(d: var string, e: string) =
  # NOTE: needed to compile
  doAssert false


proc throttlePush(d: var seq[string], e: string) =
  d.add(e)


proc splice(d: var string, fromIdx: int, toIdx=0): string =
  ## javascript splice analogue*
  var idx = fromIdx
  if fromIdx < 0 or fromIdx > d.len:
    return
  if toIdx <= 0:
    result = d[idx..d.high]
    d.delete(idx, d.high)
  else:
    result = d[idx..min(idx + pred(toIdx), d.high)]
    d.delete(idx, min(idx + pred(toIdx), d.high))


proc splice(d: var seq[string], fromIdx: int, toIdx=0): seq[string] =
  # NOTE: needed to compile
  doAssert false


proc throttleSwap(d: var string, e: int) =
  ## handled nested splice also
  let z = throttleModFunction(d, e)
  if z < 0:
    swap(d[0], d[d.len + z])
  else:
    swap(d[0], d[z])


proc throttleSwap(d: var seq[string], e: int) =
  ## handled nested splice also
  let z = throttleModFunction(d, e)
  if z < 0:
    swap(d[0], d[d.len + z])
  else:
    swap(d[0], d[z])


proc parseThrottleFunctionName(js: string): string =
  # # parse main throttle function
  # a.C&&(b=a.get("n"))&&(b=kha(b),a.set("n",b))
  # --> kha
  var match: array[1, string]
  let functionPatterns = [re"(a\.C&&\(b=a.get[^}]+)"]
  for pattern in functionPatterns:
    discard js.find(pattern, match)
  result = match[0].captureBetween('=', '(', match[0].find("a.set") - 10)


proc parseThrottleCode(mainFunc, js: string): string =
  ## parse throttle code block
  # mainThrottleFunction=function(a){.....}
  var match: array[1, string]
  let pattern = re("($1=function\\(\\w\\){.+?})(?=;)" % mainFunc, flags={reDotAll})
  discard js.find(pattern, match)
  result = match[0]


iterator splitThrottleArray(js: string): string =
  ## split the throttle array into individual components
  var
    match: array[1, string]
    item: string
    context: seq[char]

  discard js.find(re("(?<=,c=\\[)(.+)(?=\\];c)", flags={reDotAll}), match)
  item = newString(1)
  for idx, c in match[0]:
    if (c == ',' and context.len == 0 and match[0][idx + 3] != '{') or
       idx == match[0].high:
      if idx == match[0].high:
        item.add(c)
      yield item.multiReplace(("\x00", ""), ("\n", ""))
      item = newString(1)
      continue
    elif c == '{':
      context.add(c)
    elif c == '}':
      discard context.pop()
    item.add(c)


proc parseThrottleFunctionArray(js: string): seq[string] =
  ## parse c array
  for item in splitThrottleArray(js):
    if item.startsWith("\"") and item.endsWith("\""):
      result.add(item[1..^2])
    elif item.startsWith("function"):
      if item.contains("pop"):
        result.add("throttleUnshift")
      elif item.contains("case"):
        result.add("throttleCipher")
      elif item.contains("reverse") and item.contains("unshift"):
        result.add("throttlePrepend")
      elif item.contains("reverse"):
        result.add("throttleReverse")
      elif item.contains("push") and item.contains("splice"):
        result.add("throttleReverse")
      elif item.contains("push"):
        result.add("throttlePush")
      elif item.contains("var"):
        result.add("throttleSwap")
      elif item.count("splice") == 2:
        result.add("throttleNestedSplice")
      elif item.contains("splice"):
        result.add("splice")
    else:
      result.add(item)


proc parseThrottlePlan(js: string): seq[seq[string]] =
  ## parse elements of c array
  # (c[4](c[52])...) --> @[@[4, 52],...]
  let parts = js.captureBetween('{', '}', js.find("try"))
  for part in parts.split("),"):
    result.add(part.findAll(re"(?<=\[)(\d+)(?=\])"))


proc calculateN(n, js: string): string =
  ## calculate new n value to prevent throttling
  once:
    throttleCode = parseThrottleCode(parseThrottleFunctionName(js), js)
    throttlePlan = parseThrottlePlan(throttleCode)
  var
    throttleArray = parseThrottleFunctionArray(throttleCode)
    firstArg, secondArg, currFunc: string
    initialN = n

  for step in throttlePlan:
      currFunc = throttleArray[parseInt(step[0])]
      firstArg = throttleArray[parseInt(step[1])]

      if step.len == 3:
        secondArg = throttleArray[parseInt(step[2])]
      if firstArg == "null":
        if currFunc == "throttleUnshift" or currFunc == "throttlePrepend":
          throttleUnshift(throttleArray, parseInt(secondArg))
        elif currFunc == "throttleCipher":
          throttleCipher(throttleArray, secondArg)
        elif currFunc == "throttleReverse":
          throttleReverse(throttleArray)
        elif currFunc == "throttlePush":
          throttlePush(throttleArray, secondArg)
        elif currFunc == "throttleSwap" or currFunc == "throttleNestedSplice":
          throttleSwap(throttleArray, parseInt(secondArg))
        elif currFunc == "splice":
          discard splice(throttleArray, parseInt(secondArg))
      else:
        if currFunc == "throttleUnshift" or currFunc == "throttlePrepend":
          throttleUnshift(initialN, parseInt(secondArg))
        elif currFunc == "throttleCipher":
          throttleCipher(initialN, secondArg)
        elif currFunc == "throttleReverse":
          throttleReverse(initialN)
        elif currFunc == "throttlePush":
          throttlePush(initialN, secondArg)
        elif currFunc == "throttleSwap" or currFunc == "throttleNestedSplice":
          throttleSwap(initialN, parseInt(secondArg))
        elif currFunc == "splice":
          discard splice(initialN, parseInt(secondArg))

  result = initialN


########################################################
# cipher logic
########################################################
# NOTE: thanks to https://github.com/pytube/pytube/blob/master/pytube/cipher.py
# as a reference

proc getParts(cipherSignature: string): tuple[url, sc, s: string] =
  ## break cipher string into (url, sc, s)
  let parts = cipherSignature.split('&')
  result = (decodeUrl(parts[2].split('=')[1]), parts[1].split('=')[1], decodeUrl(parts[0].split('=')[1]))


proc parseFunctionPlan(js: string): seq[string] =
  ## get the scramble functions
  ## @["ix.Nh(a,2)", "ix.ai(a,5)", "ix.wW(a,62)", "ix.Nh(a,1)", "ix.wW(a,39)",
  ## "ix.ai(a,41)", "ix.Nh(a,3)"]
  var match: array[1, string]
  # NOTE: matches vy=function(a){a=a.split("");uy.bH(a,3);uy.Fg(a,7);uy.Fg(a,50);
  # uy.S6(a,71);uy.bH(a,2);uy.S6(a,80);uy.Fg(a,38);return a.join("")};
  let functionPatterns = [re"([a-zA-Z]{2}\=function\(a\)\{a\=a\.split\([^\(]+\);[a-zA-Z]{2}\.[^\n]+)"]
  for pattern in functionPatterns:
    discard js.find(pattern, match)
  match[0].split(';')[1..^3]


proc parseParentFunctionName(jsFunction: string): string =
  ## get the name of the function containing the scramble functions
  ## ix.Nh(a,2) --> ix
  jsFunction.parseIdent()


proc parseChildFunction(function: string): tuple[name: string, argument: int] {.inline.} =
  ## returns function name and int argument
  ## ix.ai(a,5) --> (ai, 5)
  result.name = function.captureBetween('.', '(')
  result.argument = parseInt(function.captureBetween(',', ')'))


proc parseIndex(jsFunction: string): int {.inline.} =
  if jsFunction.contains("splice"):
    # NOTE: function(a,b){a.splice(0,b)} --> 0
    result = parseInt(jsFunction.captureBetween('(', ',', jsFunction.find("splice")))
  elif jsFunction.contains("%"):
    # NOTE: function(a,b){var c=a[0];a[0]=a[b%a.length];a[b%a.length]=c} --> 0
    result = parseInt(jsFunction.captureBetween('[', ']', jsFunction.find("var")))


proc createFunctionMap(js, mainFunc: string): Table[string, string] =
  ## map functions to corresponding function names
  ## {"ai": "function(a,b){var c=a[0];a[0]=a[b%a.length];a[b%a.length]=c}",
  ## "wW": "function(a){a.reverse()}", "Nh": "function(a,b){a.splice(0,b)}"}
  var match: array[1, string]
  let pattern = re("(?<=var $1={)(.+?)(?=};)" % mainFunc, flags={reDotAll})
  discard js.find(pattern, match)
  for item in match[0].split(",\n"):
    let parts = item.split(':')
    result[parts[0]] = parts[1]


proc decipher(js, signature: string): string =
  ## decipher signature
  once:
    cipherPlan = parseFunctionPlan(js)
    cipherFucntionMap = createFunctionMap(js, parseParentFunctionName(cipherPlan[0]))
  var splitSig = @signature

  for item in cipherPlan:
    let
      (funcName, argument) = parseChildFunction(item)
      jsFunction = cipherFucntionMap[funcName]
      index = parseIndex(jsFunction)
    if jsFunction.contains("reverse"):
      ## function(a, b){a.reverse()}
      splitSig.reverse()
    elif jsFunction.contains("splice"):
      ## function(a, b){a.splice(0, b)}
      splitSig.delete(index, index + pred(argument))
    else:
      ## function(a,b){var c=a[0];a[0]=a[b%a.length];a[b%a.length]=c}
      swap(splitSig[index], splitSig[argument mod splitSig.len])
  result = splitSig.join()


proc getSigCipherUrl(js, signatureCipher: string): string =
  ## produce url with deciphered signature
  let parts = getParts(signatureCipher)
  result = parts.url & "&" & parts.sc & "=" & encodeUrl(decipher(js, parts.s))


########################################################
# stream logic
########################################################


proc selectBestVideoStream(streams: JsonNode, itag=0): JsonNode =
  # NOTE: zeroth stream always seems to be the overall best* quality
  if itag > 0:
    for stream in streams:
      if stream["itag"].getInt() == itag:
        result = stream
  else:
    result = streams[0]


proc selectBestAudioStream(streams: JsonNode, itag=0): JsonNode =
  if itag > 0:
    for stream in streams:
      if stream["itag"].getInt() == itag:
        result = stream
  else:
    var largest = 0
    for stream in streams:
      if stream.contains("audioQuality"):
        if stream["bitrate"].getInt() > largest:
          largest = stream["bitrate"].getInt()
          result = stream


proc getVideoStreamInfo(stream: JsonNode, duration: int): tuple[itag: int, mime, ext, size, qlt: string] =
  result.itag = stream["itag"].getInt()
  result.mime = stream["mimeType"].getStr().split(";")[0]
  result.ext = extensions[result.mime]
  if stream.hasKey("contentLength"):
    result.size = formatSize(parseInt(stream["contentLength"].getStr()), includeSpace=true)
  else:
    # NOTE: estimate from bitrate
    result.size = formatSize((stream["bitrate"].getInt() * duration / 8).int, includeSpace=true)
  result.qlt = stream["qualityLabel"].getStr()


proc getAudioStreamInfo(stream: JsonNode): tuple[itag: int, mime, ext, size, qlt: string] =
  result.itag = stream["itag"].getInt()
  result.mime = stream["mimeType"].getStr().split(";")[0]
  result.ext = extensions[result.mime]
  result.size = formatSize(parseInt(stream["contentLength"].getStr()), includeSpace=true)
  result.qlt = stream["audioQuality"].getStr()


proc urlOrCipher(stream: JsonNode): string =
  ## produce stream url, deciphering if necessary
  var
    code: HttpCode
    response: string
    n: string

  echo "[deciphering url]"
  once:
    (code, response) = doGet(jsUrl)
  if stream.hasKey("url"):
    result = stream["url"].getStr()
  elif stream.hasKey("signatureCipher"):
    result = getSigCipherUrl(response, stream["signatureCipher"].getStr())

  n = result.captureBetween('=', '&', result.find("&n="))
  if n != lastN:
    calculatedN = calculateN(n, response)
    lastN = n
  result = result.replace(n, calculatedN)


proc produceUrlSegments(baseUrl, segmentList: string): seq[string] =
  let base = parseUri(baseUrl)
  for segment in segmentList.findAll(re("""(?<=\")([a-z\d/\.]+)(?=\")""")):
    result.add($(base / segment))


proc newVideoStream(youtubeUrl, dashManifestUrl, title: string, duration: int, stream: JsonNode): Stream =
  result.title = title
  (result.itag, result.mime, result.ext, result.size, result.quality) = getVideoStreamInfo(stream, duration)
  result.filename = addFileExt("videostream", result.ext)

  if stream.hasKey("type") and stream["type"].getStr() == "FORMAT_STREAM_TYPE_OTF":
    # QUESTION: are dash urls or manifest urls ever ciphered?
    result.dash = true
    let (_, xml) = doGet(dashManifestUrl)
    var match: array[1, string]
    discard xml.find(re("""(?<=<Representation\s)(id="$1".+?)(?=</Representation>)""" % $result.itag), match)
    result.baseUrl = match[0].captureBetween('>', '<', match[0].find("<BaseURL>") + 8)
    discard match[0].find(re("(?<=<SegmentList>)(.+)(?=</SegmentList>)"), match)
    result.urlSegments = produceUrlSegments(result.baseUrl, match[0])
  else:
    result.url = urlOrCipher(stream)


proc newAudioStream(youtubeUrl, title: string, stream: JsonNode): Stream =
  # QUESTION: will stream with no audio throw exception?
  # QUESTION: are audio streams ever in dash format?
  result.title = title
  (result.itag, result.mime, result.ext, result.size, result.quality) = getAudioStreamInfo(stream)
  result.filename = addFileExt("audiostream", result.ext)
  result.url = urlOrCipher(stream)


proc reportStreamInfo(stream: Stream) =
  once:
    echo "title: ", stream.title
  echo "stream: ", stream.filename, "\n",
       "itag: ", stream.itag, '\n',
       "size: ", stream.size, '\n',
       "quality: ", stream.quality, '\n',
       "mime: ", stream.mime
  if stream.dash:
    echo "segments: ", stream.urlSegments.len


proc isolateId(youtubeUrl: string): string =
  if youtubeUrl.contains("youtu.be"):
    result = youtubeUrl.captureBetween('/', '?', 8)
  else:
    result = youtubeUrl.captureBetween('=', '&')


proc isolateChannel(youtubeUrl: string): string =
  # NOTE: vanity
  if "/c/" in youtubeUrl:
    let response = doGet(youtubeUrl)
    result = response[1].captureBetween('"', '"', response[1].find("""browseId":""") + 9)
  else:
    result = youtubeUrl.captureBetween('/', '/', youtubeUrl.find("channel"))


proc isolatePlaylist(youtubeUrl: string): string =
  result = youtubeUrl.captureBetween('=', '&', youtubeUrl.find("list="))


proc getVideo(youtubeUrl: string) =
  let
    id = isolateId(youtubeUrl)
    standardYoutubeUrl = "https://www.youtube.com/watch?v=" & id
  var
    playerResponse: JsonNode
    response: string
    code: HttpCode
    dashManifestUrl: string

  # NOTE: make initial request to get variable youtube values
  (code, response) = doGet(standardYoutubeUrl)
  let sigTimeStamp = response.captureBetween(':', ',', response.find("\"STS\""))
  jsUrl = "https://www.youtube.com" & response.captureBetween('"', '"', response.find("\"jsUrl\":\"") + 7)

  (code, response) = doPost(playerUrl, playerContext % [id, sigTimeStamp, date])
  if code.is2xx:
    playerResponse = parseJson(response)
    if playerResponse["playabilityStatus"]["status"].getStr() == "ERROR":
      echo '<', playerResponse["playabilityStatus"]["reason"].getStr(), '>'
      return
    let
      title = playerResponse["videoDetails"]["title"].getStr()
      safeTitle = title.multiReplace((".", ""), ("/", "-"), (": ", " - "), (":", "-"))
      finalPath = addFileExt(joinPath(getCurrentDir(), safeTitle), ".mkv")
      duration = parseInt(playerResponse["videoDetails"]["lengthSeconds"].getStr())

    if fileExists(finalPath):
      echo "<file exists> ", safeTitle
    else:
      if playerResponse["playabilityStatus"]["status"].getStr() == "LOGIN_REQUIRED":
        echo "[attempting age-gate bypass]"
        (code, response) = doPost(playerUrl, playerBypassContext % [id, sigTimeStamp, date])
        playerResponse = parseJson(response)
        if playerResponse["playabilityStatus"]["status"].getStr() != "OK":
          echo '<', playerResponse["playabilityStatus"]["reason"].getStr(), '>'
          return
      elif playerResponse["playabilityStatus"]["status"].getStr() != "OK" or playerResponse["playabilityStatus"].hasKey("liveStreamability"):
        echo '<', playerResponse["playabilityStatus"]["reason"].getStr(), '>'
        return

      if playerResponse["streamingData"].hasKey("dashManifestUrl"):
        dashManifestUrl = playerResponse["streamingData"]["dashManifestUrl"].getStr()
      let
        videoStream = newVideoStream(standardYoutubeUrl, dashManifestUrl, title, duration,
                                     selectBestVideoStream(playerResponse["streamingData"]["adaptiveFormats"]))
        audioStream = newAudioStream(standardYoutubeUrl, title, selectBestAudioStream(playerResponse["streamingData"]["adaptiveFormats"]))

      reportStreamInfo(videoStream)
      var attempt: HttpCode
      if videoStream.dash:
        attempt = grabMulti(videoStream.urlSegments, forceFilename=videoStream.filename,
                            saveLocation=getCurrentDir(), forceDl=true)
      else:
        attempt = grab(videoStream.url, forceFilename=videoStream.filename,
                       saveLocation=getCurrentDir(), forceDl=true)
      if attempt.is2xx:
        reportStreamInfo(audioStream)
        if grab(audioStream.url, forceFilename=audioStream.filename, saveLocation=getCurrentDir(), forceDl=true).is2xx:
          joinStreams(videoStream.filename, audioStream.filename, safeTitle)
        else:
          echo "<failed to download audio stream>"
      else:
        echo "<failed to download video stream>"
  else:
    echo "<failed to obtain channel metadata>"


proc getChannel(youtubeUrl: string) =
  let channel = isolateChannel(youtubeUrl)
  var
    channelResponse: JsonNode
    response: string
    code: HttpCode
    token, lastToken: string
    ids: seq[string]

  (code, response) = doPost(browseUrl, browseContext % [channel, date])
  if code.is2xx:
    echo "[collecting videos]"
    channelResponse = parseJson(response)

    for item in channelResponse["contents"]["twoColumnBrowseResultsRenderer"]["tabs"][1]["tabRenderer"]["content"]["sectionListRenderer"]["contents"][0]["itemSectionRenderer"]["contents"][0]["gridRenderer"]["items"]:
      if item.hasKey("continuationItemRenderer"):
        token = item["continuationItemRenderer"]["continuationEndpoint"]["continuationCommand"]["token"].getStr()
        lastToken = token
        while true:
          (code, response) = doPost(browseUrl, browseContinueContext % [channel, token, date])
          if code.is2xx:
            channelResponse = parseJson(response)
            for item in channelResponse["onResponseReceivedActions"][0]["appendContinuationItemsAction"]["continuationItems"]:
              if item.hasKey("continuationItemRenderer"):
                token = item["continuationItemRenderer"]["continuationEndpoint"]["continuationCommand"]["token"].getStr()
              else:
                ids.add(item["gridVideoRenderer"]["videoId"].getStr())
            if token == lastToken:
              break
            else:
              lastToken = token
          else:
            echo "<failed to obtain channel metadata>"
      else:
        ids.add(item["gridVideoRenderer"]["videoId"].getStr())

    echo '[', ids.len, " videos queued]"
    for id in ids:
      getVideo("https://www.youtube.com/watch?v=" & id)
  else:
    echo "<failed to obtain channel metadata>"


proc getPlaylist(youtubeUrl: string) =
  let playlist = isolatePlaylist(youtubeUrl)
  var
    playlistResponse: JsonNode
    response: string
    code: HttpCode
    ids: seq[string]
    title: string

  (code, response) = doPost(nextUrl, playlistContext % [date, playlist])
  if code.is2xx:
    playlistResponse = parseJson(response)
    title = playlistResponse["contents"]["twoColumnWatchNextResults"]["playlist"]["playlist"]["title"].getStr()
    echo "[collecting videos] ", title

    if playlistResponse["contents"]["twoColumnWatchNextResults"]["playlist"]["playlist"]["isInfinite"].getBool():
      echo "<infinite playlist...aborting>"
      return
    for item in playlistResponse["contents"]["twoColumnWatchNextResults"]["playlist"]["playlist"]["contents"]:
      ids.add(item["playlistPanelVideoRenderer"]["videoId"].getStr())

    for id in ids:
      getVideo("https://www.youtube.com/watch?v=" & id)
  else:
    echo "<failed to obtain playlist metadata>"


proc youtubeDownload*(youtubeUrl: string) =
  if "/channel/" in youtubeUrl or "/c/" in youtubeUrl:
    getChannel(youtubeUrl)
  elif "list=" in youtubeUrl and "/watch?" notin youtubeUrl:
    getPlaylist(youtubeUrl)
  else:
    getVideo(youtubeUrl)
