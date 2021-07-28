import std/[json, uri, algorithm, sequtils, parseutils]

import utils


const
  playerContext = """{
        "context": {
          "client": {
            "hl": "en",
            "clientName": "WEB",
            "clientVersion": "2.20210721.00.00",
            "mainAppWebInfo": {
              "graftUrl": "/watch?v=$1"
            }
          }
        },
        "videoId": "$1"
      }"""
  browseContext = """{
        "browseId": "$1",
        "context": {
          "client": {
            "hl": "en",
            "clientName": "WEB",
            "clientVersion": "2.20210721.00.00",
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
            "clientVersion": "2.20210721.00.00",
            "mainAppWebInfo": {
              "graftUrl": "/channel/$1/videos"
            }
          }
        },
        "continuation": "$2"
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
  bypassUrl = "https://www.youtube.com/get_video_info?html5=1&c=TVHTML5&cver=6.20180913&video_id=$1"
  playerUrl = "https://www.youtube.com/youtubei/v1/player?key=AIzaSyAO_FJ2SlqU8Q4STEHLGCilw_Y9_11qcW8"
  browseUrl = "https://www.youtube.com/youtubei/v1/browse?key=AIzaSyAO_FJ2SlqU8Q4STEHLGCilw_Y9_11qcW8"
  # contextUrl = "https://www.youtube.com/sw.js_data"

var
  plan: seq[string]
  mainFunc: string
  map: Table[string, string]


########################################################
# misc
########################################################


proc creatAuthenticationCookie(): string =
  import std/[sha1, times]
  const xOrigin = "https://www.youtube.com"
  let
    timeStamp = toUnix(getTime())
    sapisid = "" # NOTE: from cookies
  result = "SAPISIDHASH " & $timeStamp & '_' & $secureHash(timeStamp & ' ' & sapisid & ' ' & xOrigin)


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
    plan = parseFunctionPlan(js)
    mainFunc = parseParentFunctionName(plan[0])
    map = createFunctionMap(js, mainFunc)
  var splitSig = @signature

  for item in plan:
    let
      (funcName, argument) = parseChildFunction(item)
      jsFunction = map[funcName]
      index = parseIndex(jsFunction)
    if jsFunction.contains("reverse"):
      ## function(a, b){a.reverse()}
      splitSig.reverse()
    elif jsFunction.contains("splice"):
      ## function(a, b){a.splice(0, b)}
      splitSig.delete(index, pred(argument))
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


proc selectBestVideoStream(streams: JsonNode): JsonNode =
  # NOTE: zeroth stream always seems to be the overall best* quality
  result = streams[0]


proc selectBestAudioStream(streams: JsonNode): JsonNode =
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


proc urlOrCipher(youtubeUrl: string, stream: JsonNode): string =
  ## produce stream url, deciphering if necessary
  if stream.hasKey("url"):
    result = stream["url"].getStr()
  elif stream.hasKey("signatureCipher"):
    var
      code: HttpCode
      response: string
    once:
      echo "[deciphering urls]"
      (code, response) = doGet(youtubeUrl)
      let jsUrl = "https://www.youtube.com" & response.captureBetween('"', '"', response.find("\"jsUrl\":\"") + 7)
      (code, response) = doGet(jsUrl)
    result = getSigCipherUrl(response, stream["signatureCipher"].getStr())
  # WARNING: don't think this works.
  result.insert("&ratebypass=yes", result.find("requiressl") + 14)


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
    result.url = urlOrCipher(youtubeUrl, stream)


proc newAudioStream(youtubeUrl, title: string, stream: JsonNode): Stream =
  # QUESTION: will stream with no audio throw exception?
  # QUESTION: are audio streams ever in dash format?
  result.title = title
  (result.itag, result.mime, result.ext, result.size, result.quality) = getAudioStreamInfo(stream)
  result.filename = addFileExt("audiostream", result.ext)
  result.url = urlOrCipher(youtubeUrl, stream)


proc tryBypass(bypassUrl: string): JsonNode =
  ## get new response using bypass url
  let (code, bypassResponse) = doGet(bypassUrl)
  if code.is2xx:
    var match: array[1, string]
    discard decodeUrl(bypassResponse).find(re("({\"responseContext\".+})(?=&enable)"), match)
    result = parseJson(match[0])
  else:
    result = newJNull()


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
  if "/c/" in youtubeUrl:
    # NOTE: vanity
    let response = doGet(youtubeUrl)
    result = response[1].captureBetween('"', '"', response[1].find("""browseId":""") + 9)
  else:
    result = youtubeUrl.captureBetween('/', '/', youtubeUrl.find("channel"))


proc getVideo(youtubeUrl: string) =
  let
    id = isolateId(youtubeUrl)
    standardYoutubeUrl = "https://www.youtube.com/watch?v=" & id
  var
    playerResponse: JsonNode
    response: string
    code: HttpCode

  (code, response) = doPost(playerUrl, playerContext % id)
  if code.is2xx:
    playerResponse = parseJson(response)
    let
      # BUG: if bad url this will throw key not found error
      title = playerResponse["videoDetails"]["title"].getStr()
      safeTitle = title.multiReplace((".", ""), ("/", "-"), (": ", " - "), (":", "-"))
      finalPath = addFileExt(joinPath(getCurrentDir(), safeTitle), ".mkv")
      duration = parseInt(playerResponse["videoDetails"]["lengthSeconds"].getStr())

    if fileExists(finalPath):
      echo "<file exists> ", safeTitle
    else:
      if playerResponse["playabilityStatus"]["status"].getStr() == "LOGIN_REQUIRED":
        echo "[attempting age-gate bypass]"
        playerResponse = tryBypass(bypassUrl % id)
        if playerResponse.kind == JNull:
          echo "<bypass failed>"
          return
        elif playerResponse["playabilityStatus"]["status"].getStr() == "LOGIN_REQUIRED":
          # QUESTION: can this scenario happen with bypass url?
          echo '<', playerResponse["playabilityStatus"]["reason"].getStr(), '>'
          return
      elif playerResponse["playabilityStatus"]["status"].getStr() != "OK" or playerResponse["playabilityStatus"].hasKey("liveStreamability"):
        echo '<', playerResponse["playabilityStatus"]["reason"].getStr(), '>'
        return

      var dashManifestUrl: string
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


proc getChannel(youtubeUrl: string) =
  let channel = isolateChannel(youtubeUrl)
  var
    channelResponse: JsonNode
    response: string
    code: HttpCode
    token, lastToken: string
    ids: seq[string]

  (code, response) = doPost(browseUrl, browseContext % channel)
  if code.is2xx:
    echo "[collecting videos]"
    channelResponse = parseJson(response)
    for item in channelResponse["contents"]["twoColumnBrowseResultsRenderer"]["tabs"][1]["tabRenderer"]["content"]["sectionListRenderer"]["contents"][0]["itemSectionRenderer"]["contents"][0]["gridRenderer"]["items"]:
      if item.hasKey("continuationItemRenderer"):
        token = item["continuationItemRenderer"]["continuationEndpoint"]["continuationCommand"]["token"].getStr()
        lastToken = token
        while true:
          (code, response) = doPost(browseUrl, browseContinueContext % [channel, token])
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
  else:
    echo "<failed to obtain channel metadata>"

  echo '[', ids.len, " videos found]"
  for id in ids:
    getVideo("https://www.youtube.com/watch?v=" & id)


proc youtubeDownload*(youtubeUrl: string) =
  if "/channel/" in youtubeUrl or "/c/" in youtubeUrl:
    getChannel(youtubeUrl)
  else:
    getVideo(youtubeUrl)
