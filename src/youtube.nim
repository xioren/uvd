import std/[json, uri, algorithm, sequtils, parseutils]
# import std/[sha1]

import utils

#[ NOTE:
  age gate tier 1: https://www.youtube.com/watch?v=HtVdAasjOgU
  age gate tier 2: https://www.youtube.com/watch?v=Tq92D6wQ1mg
  age gate tier 3: https://www.youtube.com/watch?v=7iAQCPmpSUI
  age gate tier 4: https://www.youtube.com/watch?v=Cr381pDsSsA
]#

type
  Stream = object
    itag: int
    mime: string
    ext: string
    codec: string
    size: string
    quality: string
    resolution: string
    bitrate: string
    url: string
    baseUrl: string
    urlSegments: seq[string]
    filename: string
    isDash: bool
    exists: bool

  Video = object
    title: string
    videoId: string
    url: string
    thumbnailUrl: string
    audioStream: Stream
    videoStream: Stream

# NOTE: clientVersion can be found in contextUrl response (along with api key)
# QUESTION: can language (hl) be set programatically? should it be?
const
  playerContext = """{
    "context": {
      "client": {
        "hl": "en",
        "clientName": "WEB",
        "clientVersion": "2.$3.00.00"
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
  playerBypassContextTier1 = """{
    "context": {
      "client": {
        "hl": "en",
        "clientName": "WEB_EMBEDDED_PLAYER",
        "clientVersion": "2.$3.00.00"
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
  playerBypassContextTier2 = """{
    "context": {
      "client": {
        "hl": "en",
        "clientName": "WEB",
        "clientVersion": "2.$3.00.00",
        "clientScreen": "EMBED"
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
  playerBypassContextTier3 = """{
    "context": {
      "client": {
        "hl": "en",
        "clientName": "WEB",
        "clientVersion": "2.$3.00.00",
        "clientScreen": "EMBED"
        },
      "thirdParty": {
        "embedUrl": "https://google.com"
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
        "clientVersion": "2.$2.00.00"
      }
    },
    "params": "$3"
  }"""
  browseContinueContext = """{
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
    "continuation": "$3"
  }"""
  playlistContext = """{
    "context": {
      "client": {
        "hl": "en",
        "clientName": "WEB",
        "clientVersion": "2.$2.00.00",
        "mainAppWebInfo": {
          "graftUrl": "/playlist?list=$1"
        }
      }
    },
    "playlistId": "$1"
  }"""
  apiKey = "AIzaSyAO_FJ2SlqU8Q4STEHLGCilw_Y9_11qcW8"
  baseUrl = "https://www.youtube.com"
  watchUrl = "https://www.youtube.com/watch?v="
  # channelUrl = "https://www.youtube.com/channel/"
  # channelVanityUrl = "https://www.youtube.com/c/"
  playlistUrl = "https://www.youtube.com/playlist?list="
  playerUrl = "https://youtubei.googleapis.com/youtubei/v1/player?key=" & apiKey
  browseUrl = "https://youtubei.googleapis.com/youtubei/v1/browse?key=" & apiKey
  nextUrl = "https://youtubei.googleapis.com/youtubei/v1/next?key=" & apiKey
  baseJsUrl = "https://www.youtube.com/s/player/$1/player_ias.vflset/$2/base.js"
  # contextUrl = "https://www.youtube.com/sw.js_data"
  videosTab = "EgZ2aWRlb3M%3D"
  playlistsTab = "EglwbGF5bGlzdHM%3D"
  # TODO: generate programmatically
  forwardH = ['A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J',
              'K', 'L', 'M', 'N', 'O', 'P', 'Q', 'R', 'S', 'T',
              'U', 'V', 'W', 'X', 'Y', 'Z', 'a', 'b', 'c', 'd',
              'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm', 'n',
              'o', 'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x',
              'y', 'z', '0', '1', '2', '3', '4', '5', '6', '7',
              '8', '9', '-', '_']
  reverseH = ['0', '1', '2', '3', '4', '5', '6', '7', '8', '9',
              'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j',
              'k', 'l', 'm', 'n', 'o', 'p', 'q', 'r', 's', 't',
              'u', 'v', 'w', 'x', 'y', 'z', 'A', 'B', 'C', 'D',
              'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N',
              'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X',
              'Y', 'Z', '-', '_']
  videoMetadataFailureMessage = "failed to obtain video metadata"
  channelMetadataFailureMessage = "failed to obtain channel metadata"
  playlistMetadataFailureMessage = "failed to obtain playlist metadata"

let date = now().format("yyyyMMdd")

var
  apiLocale: string
  includeAudio, includeVideo, includeThumb, includeSubtitles: bool
  subtitlesLanguage: string
  audioFormat: string
  showStreams: bool
  globalBaseJsVersion: string
  cipherPlan: seq[string]
  cipherFunctionMap: Table[string, string]
  nTransforms: Table[string, string]
  throttleArray: seq[string]
  throttlePlan: seq[seq[string]]


########################################################
# authentication (wip)
########################################################


# proc creatAuthenticationCookie(): string =
#   const xOrigin = "https://www.youtube.com"
#   let
#     timeStamp = toUnix(getTime())
#     sapisid = "" # NOTE: from cookies
#   result = "SAPISIDHASH " & $timeStamp & '_' & $secureHash(timeStamp & ' ' & sapisid & ' ' & xOrigin)


########################################################
# subtitles
########################################################


proc formatTime(time: string): string =
  ## convert timestamps to SubRip format
  var parts: seq[string]
  if time.contains('.'):
    parts = time.split('.')
  else:
    parts = @[time, "000"]

  # IDEA: the strformat module can probably do this better
  if parts[1].len > 3:
    # HACK: for floating point rounding errors
    parts[1] = parts[1][0..2]

  let td = initDuration(seconds=parseInt(parts[0]), milliseconds=parseInt(parts[1])).toParts()
  result = ($td[Hours]).zFill(2) & ':' & ($td[Minutes]).zFill(2) & ':' & ($td[Seconds]).zFill(2) & ',' & ($td[Milliseconds]).zFill(3)


proc asrToSrt(xml: string): string =
  ## convert youtube native asr captions to SubRip format
  let
    startTimes = xml.findAll(re"""(?<=start=")[^"]+""")
    durations = xml.findAll(re"""(?<=dur=")[^"]+""")
    text = xml.findAll(re"""(?<=>)[^<>]+(?=</text>)""")


  for idx in 0..startTimes.high:
    result.add($idx.succ & '\n')
    let
      startPoint = startTimes[idx]
      duration = durations[idx]
      endPoint = $(parseFloat(startPoint) + parseFloat(duration))

    if idx < startTimes.high:
      #[ NOTE: choose min between enpoint of current text and startpoint of next text to eliminate crowding
        i.e. only one subtitle entry on screen at a time ]#
      result.add(formatTime(startPoint) & " --> " & formatTime($min(parseFloat(endPoint), parseFloat(startTimes[idx.succ]))) & '\n')
      result.add(text[idx].replace("&amp;#39;", "'") & "\n\n")
    else:
      result.add(formatTime(startPoint) & " --> " & formatTime(endPoint) & '\n')
      result.add(text[idx].replace("&amp;#39;", "'"))


proc generateSubtitles(captions: JsonNode) =
  var
    doTranslate: bool
    captionTrack = newJNull()
    defaultAudioTrackIndex, defaultCaptionTrackIndex: int

  if subtitlesLanguage != "":
    # NOTE: check if desired language exists natively
    for track in captions["playerCaptionsTracklistRenderer"]["captionTracks"]:
      if track["languageCode"].getStr() == subtitlesLanguage:
        captionTrack = track
        break
    if captionTrack.kind == JNull:
      logNotice("subtitles not available natively in desired language...falling back to direct translation")

  if captionTrack.kind == JNull:
    defaultAudioTrackIndex = captions["playerCaptionsTracklistRenderer"]["defaultAudioTrackIndex"].getInt()
    if captions["playerCaptionsTracklistRenderer"]["audioTracks"][defaultAudioTrackIndex].hasKey("defaultCaptionTrackIndex"):
      defaultCaptionTrackIndex = captions["playerCaptionsTracklistRenderer"]["audioTracks"][defaultAudioTrackIndex]["defaultCaptionTrackIndex"].getInt()

    if subtitlesLanguage == "":
      # NOTE: subtitles desired but no language specified --> select default caption track
      captionTrack = captions["playerCaptionsTracklistRenderer"]["captionTracks"][defaultCaptionTrackIndex]
      subtitlesLanguage = captionTrack["languageCode"].getStr()
    else:
      # NOTE: check if desired language can be translated to
      if captions["playerCaptionsTracklistRenderer"]["captionTracks"][defaultCaptionTrackIndex]["isTranslatable"].getBool():
        for language in captions["playerCaptionsTracklistRenderer"]["translationLanguages"]:
          if language["languageCode"].getStr() == subtitlesLanguage:
            captionTrack = captions["playerCaptionsTracklistRenderer"]["captionTracks"][defaultCaptionTrackIndex]
            doTranslate = true
            break
      if captionTrack.kind == JNull:
        logError("subtitles not available for translation to desired language")

  if captionTrack.kind != JNull:
    var captionTrackUrl = captionTrack["baseUrl"].getStr()
    if doTranslate:
      captionTrackUrl.add("&tlang=" & subtitlesLanguage)

    let (code, response) = doGet(captionTrackUrl)
    if code.is2xx:
      includeSubtitles = save(asrToSrt(response), addFileExt(subtitlesLanguage, "srt"))
    else:
      includeSubtitles = false
      logError("error downloading subtitles")
  else:
    includeSubtitles = false
    logError("error obtaining subtitles")


########################################################
# throttle logic
########################################################
#[ NOTE: thanks to https://github.com/pytube/pytube/blob/master/pytube/cipher.py
  as a reference ]#


proc throttleModFunction(d: string | seq[string], e: int): int {.inline.} =
  # NOTE: function(d,e){e=(e%d.length+d.length)%d.length
  result = (e mod d.len + d.len) mod d.len


proc throttleUnshift(d: var (string | seq[string]), e: int) {.inline.} =
  ## handles prepend also
  #[ NOTE:
    function(d,e){e=(e%d.length+d.length)%d.length;d.splice(-e).reverse().forEach(function(f){d.unshift(f)})};
    function(d,e){for(e=(e%d.length+d.length)%d.length;e--;)d.unshift(d.pop())};
  ]#
  d.rotateLeft(d.len - throttleModFunction(d, e))


proc throttleCipher(d: var string, e: var string, f: array[64, char]) {.inline.} =
  #[ NOTE:
    generative forward h: function(d,e){for(var f=64,h=[];++f-h.length-32;){switch(f)
    {case 58:f-=14;case 91:case 92:case 93:continue;case 123:f=47;case 94:case 95:
    case 96:continue;case 46:f=95}h.push(String.fromCharCode(f))}
    d.forEach(function(l,m,n){this.push(n[m]=h[(h.indexOf(l)-h.indexOf(this[m])+m-32+f--)%h.length])}

    generative reverse h: function(d,e){for(var f=64,h=[];++f-h.length-32;){switch(f){case 91:f=44;continue;
    case 123:f=65;break;case 65:f-=18;continue;case 58:f=96;continue;case 46:f=95}
    h.push(String.fromCharCode(f))}d.forEach(function(l,m,n){this.push(n[m]
    =h[(h.indexOf(l)-h.indexOf(this[m])+m-32+f--)%h.length])},e.split(""))}

    non-generative: function(d,e,f){var h=f.length;d.forEach(function(l,m,n){this.push(n[m]=f[(f.indexOf(l)-f.indexOf(this[m])+m+h--)%f.length])},e.split(""))};

    +m-32+f-- == +m+h-- == +f.len == +64
  ]#
  var
    c: char
    n: string
  for m, l in d:
    c = f[(f.indexOf(l) - f.indexOf(e[m]) + 64) mod 64]
    e.add(c)
    n.add(c)
  d = n


proc throttleReverse(d: var (string | seq[string])) {.inline.} =
  #[ NOTE:
    function(d){d.reverse()};
    function(d){for(var e=d.length;e;)d.push(d.splice(--e,1)[0])};
  ]#
  d.reverse()


proc throttlePush(d: var (string | seq[string]), e: string) {.inline.} =
  d.add(e)


proc throttleSplice(d: var (string | seq[string]), e: int) {.inline.} =
  ## javascript splice
  # NOTE: function(d,e){e=(e%d.length+d.length)%d.length;d.splice(e,1)};
  let z = throttleModFunction(d, e)
  d.delete(z..z)


proc throttleSwap(d: var (string | seq[string]), e: int) {.inline.} =
  ## handles nested splice also
  #[ NOTE:
    swap: function(d,e){e=(e%d.length+d.length)%d.length;var f=d[0];d[0]=d[e];d[e]=f}
    nested splice: function(d,e){e=(e%d.length+d.length)%d.length;d.splice(0,1,d.splice(e,1,d[0])[0])}
  ]#
  let z = throttleModFunction(d, e)
  swap(d[0], d[z])


proc extractThrottleFunctionName(js: string): string =
  ## extract main throttle function
  # NOTE: a.C&&(b=a.get("n"))&&(b=kha(b),a.set("n",b)) --> kha
  let found = js.easyFind(re"(a\.[A-Z]&&\(b=a.[sg]et[^}]+)")
  result = found.captureBetween('=', '(', found.find("a.set") - 10)


proc extractThrottleCode(mainFunc, js: string): string =
  ## extract throttle code block from base.js
  # NOTE: mainThrottleFunction=function(a){.....}
  result = js.easyFind(re("($1=function\\(\\w\\){.+?})(?=;)" % mainFunc, flags={reDotAll}))


iterator splitThrottleArray(js: string): string =
  ## split c array into individual elements
  var
    step: string
    scope: int

  let found = js.easyFind(re("(?<=,c=\\[)(.+)(?=\\];\n?c)", flags={reDotAll}))

  for idx, c in found:
    #[ NOTE: commas separate function arguments and functions themselves.
      only yield if the comma is separating two functions in the base scope
      and not function arguments or child functions.
    ]#
    if (c == ',' and scope == 0 and '{' notin found[idx..min(idx + 5, found.high)]) or idx == found.high:
      if idx == found.high:
        step.add(c)
      yield step.multiReplace(("\x00", ""), ("\n", ""))
      step = ""
      continue
    elif c == '{':
      inc scope
    elif c == '}':
      dec scope
    step.add(c)


proc parseThrottleArray(js: string): seq[string] =
  ## parse c array and translate javascipt functions to nim equivalents
  for step in splitThrottleArray(js):
    if step.startsWith("\"") and step.endsWith("\""):
      result.add(step[1..^2])
    elif step.startsWith("function"):
      if step.contains("pop"):
        result.add("throttleUnshift")
      elif step.contains("case 65"):
        result.add("throttleCipherReverse")
      elif step.contains("case"):
        result.add("throttleCipherForward")
      elif step.contains("f.indexOf(l)-f.indexOf"):
        result.add("throttleCipherGeneric")
      elif step.contains("reverse") and step.contains("unshift"):
        result.add("throttlePrepend")
      elif step.contains("reverse") or (step.contains("push") and step.contains("splice")):
        result.add("throttleReverse")
      elif step.contains("push"):
        result.add("throttlePush")
      elif step.contains("var"):
        result.add("throttleSwap")
      elif step.count("splice") == 2:
        result.add("throttleNestedSplice")
      elif step.contains("splice"):
        result.add("throttleSplice")
    else:
      result.add(step)


proc parseThrottlePlan(js: string): seq[seq[string]] =
  ## parse steps and indexes of throttle plan
  # NOTE: (c[4](c[52])...) --> @[@[4, 52],...]
  let parts = js.captureBetween('{', '}', js.find("try"))
  for part in parts.split("),"):
    result.add(part.findAll(re"(?<=\[)(\d+)(?=\])"))


proc transformN(initialN: string): string =
  ## calculate new n throttle value
  var
    tempArray = throttleArray
    firstArg, secondArg, currFunc: string
    n = initialN
    k, e: string

  for step in throttlePlan:
    currFunc = tempArray[parseInt(step[0])]
    firstArg = tempArray[parseInt(step[1])]

    if step.len > 2:
      secondArg = tempArray[parseInt(step[2])]
      if secondArg.contains('E'):
        # NOTE: arg (may be) in exponential notation
        (k, e) = secondArg.split('E')
        if k.all(isDigit) and e.all(isDigit):
          secondArg = k & '0'.repeat(parseInt(e))

    # TODO: im sure there is a clever way to compact this
    if firstArg == "null":
      # NOTE: modifying entire array
      case currFunc
      of "throttleUnshift", "throttlePrepend":
        throttleUnshift(tempArray, parseInt(secondArg))
      of "throttleReverse":
        throttleReverse(tempArray)
      of "throttlePush":
        throttlePush(tempArray, secondArg)
      of "throttleSwap", "throttleNestedSplice":
        throttleSwap(tempArray, parseInt(secondArg))
      of "throttleSplice":
        throttleSplice(tempArray, parseInt(secondArg))
      else:
        doAssert false
    else:
      # NOTE: modifying n value
      case currFunc
      of "throttleUnshift", "throttlePrepend":
        throttleUnshift(n, parseInt(secondArg))
      of "throttleCipherForward":
        throttleCipher(n, secondArg, forwardH)
      of "throttleCipherReverse":
        throttleCipher(n, secondArg, reverseH)
      of "throttleCipherGeneric":
        let thirdArg = tempArray[parseInt(step[3])]
        if thirdArg == "throttleCipherForward":
          throttleCipher(n, secondArg, forwardH)
        else:
          throttleCipher(n, secondArg, reverseH)
      of "throttleReverse":
        throttleReverse(n)
      of "throttlePush":
        throttlePush(n, secondArg)
      of "throttleSwap", "throttleNestedSplice":
        throttleSwap(n, parseInt(secondArg))
      of "throttleSplice":
        throttleSplice(n, parseInt(secondArg))
      else:
        doAssert false

  result = n


########################################################
# cipher logic
########################################################
#[ NOTE: thanks to https://github.com/pytube/pytube/blob/master/pytube/cipher.py
  as a reference ]#

proc getParts(cipherSignature: string): tuple[url, sc, s: string] =
  ## break cipher string into (url, sc, s)
  let parts = cipherSignature.split('&')
  result = (decodeUrl(parts[2].split('=')[1]), parts[1].split('=')[1], decodeUrl(parts[0].split('=')[1]))


proc extractFunctionPlan(js: string): seq[string] =
  ## get the scramble functions
  ## returns: @["ix.Nh(a,2)", "ix.ai(a,5)"...]

  #[ NOTE: matches vy=function(a){a=a.split("");uy.bH(a,3);uy.Fg(a,7);uy.Fg(a,50);
    uy.S6(a,71);uy.bH(a,2);uy.S6(a,80);uy.Fg(a,38);return a.join("")}; ]#
  let found = js.easyFind(re"""[a-zA-Z]{1,3}=function\(a\){a=a\.split\(""\);([^}]+);return""")
  result = found.split(';')


proc extractParentFunctionName(jsFunction: string): string =
  ## get the name of the function containing the scramble functions
  ## ix.Nh(a,2) --> ix
  escapeRe(jsFunction.split('.')[0])


proc parseChildFunction(function: string): tuple[name: string, argument: int] =
  ## returns child function name and second argument
  ## ix.ai(a,5) --> (ai, 5)
  result.name = escapeRe(function.captureBetween('.', '('))
  result.argument = parseInt(function.captureBetween(',', ')'))


proc extractIndex(jsFunction: string): int =
  if jsFunction.contains("splice"):
    # NOTE: function(a,b){a.splice(0,b)} --> 0
    result = parseInt(jsFunction.captureBetween('(', ',', jsFunction.find("splice")))
  elif jsFunction.contains("%"):
    # NOTE: function(a,b){var c=a[0];a[0]=a[b%a.length];a[b%a.length]=c} --> 0
    result = parseInt(jsFunction.captureBetween('[', ']', jsFunction.find("var")))


proc createFunctionMap(js, mainFunc: string): Table[string, string] =
  ## map functions to corresponding function names
  ## {"wW": "function(a){a.reverse()}", "Nh": "function(a,b){a.splice(0,b)}"...}
  let found = js.easyFind(re("(?<=var $1={)(.+?)(?=};)" % mainFunc, flags={reDotAll}))
  for item in found.split(",\n"):
    let parts = item.split(':')
    result[parts[0]] = parts[1]


proc decipher(signature: string): string =
  ## decipher signature
  var a = @signature

  for step in cipherPlan:
    let
      (funcName, b) = parseChildFunction(step)
      jsFunction = cipherFunctionMap[funcName]
      index = extractIndex(jsFunction)
    if jsFunction.contains("reverse"):
      # NOTE: function(a, b){a.reverse()}
      a.reverse()
    elif jsFunction.contains("splice"):
      # NOTE: function(a, b){a.splice(0, b)}
      a.delete(index..index + b.pred)
    else:
      # NOTE: function(a,b){var c=a[0];a[0]=a[b%a.length];a[b%a.length]=c}
      swap(a[index], a[b mod a.len])

  result = a.join()


proc getSigCipherUrl(signatureCipher: string): string =
  ## produce url with deciphered signature
  let parts = getParts(signatureCipher)
  result = parts.url & "&" & parts.sc & "=" & encodeUrl(decipher(parts.s))


########################################################
# stream logic
########################################################


proc hasItag(streams: JsonNode, itag: int): bool =
  ## check if set of streams contains given itag
  if itag == 0:
    result = true
  else:
    for stream in streams:
      if stream["itag"].getInt() == itag:
        return true


proc urlOrCipher(stream: JsonNode): string =
  ## produce stream url, deciphering if necessary and tranform n throttle string
  if stream.hasKey("url"):
    result = stream["url"].getStr()
  elif stream.hasKey("signatureCipher"):
    result = getSigCipherUrl(stream["signatureCipher"].getStr())

  let n = result.captureBetween('=', '&', result.find("&n="))
  if nTransforms.haskey(n):
    result = result.replace(n, nTransforms[n])
  else:
    let transformedN = transformN(n)
    nTransforms[n] = transformedN
    if n != transformedN:
      result = result.replace(n, transformedN)
    logDebug("initial n: ", n)
    logDebug("transformed n: ", transformedN)
  logDebug("download url: ", result)


proc produceDashSegments(baseUrl, segmentList: string): seq[string] =
  ## extract individual from dash entry
  let base = parseUri(baseUrl)
  for segment in segmentList.findAll(re("""(?<=\")([a-z\d/\.-]+)(?=\")""")):
    result.add($(base / segment))


proc extractDashInfo(dashManifestUrl, itag: string): tuple[baseUrl, segmentList: string] =
  ## parse itag's dash entry from xml
  let (_, xml) = doGet(dashManifestUrl)
  let found = xml.easyFind(re("""(?<=<Representation\s)(id="$1".+?)(?=</Representation>)""" % itag))
  result.baseUrl = found.captureBetween('>', '<', found.find("<BaseURL>") + 8)
  result.segmentList = found.easyFind(re("(?<=<SegmentList>)(.+)(?=</SegmentList>)"))


proc getBitrate(stream: JsonNode): int =
  ## extract bitrate value from json. prefers average bitrate.
  if stream.kind == JNull:
    result = 0
  elif stream.hasKey("averageBitrate"):
    # NOTE: not present in DASH streams metadata
    result = stream["averageBitrate"].getInt()
  else:
    result = stream["bitrate"].getInt()


proc selectVideoByBitrate(streams: JsonNode, codec: string): JsonNode =
  ## select $codec video stream with highest bitrate (and resolution)
  var
    thisBitrate, maxBitrate, idx, thisSemiperimeter, maxSemiperimeter: int
    select = -1
  result = newJNull()

  for stream in streams:
    if stream["mimeType"].getStr().contains(codec):
      thisSemiperimeter = stream["width"].getInt() + stream["height"].getInt()
      if thisSemiperimeter >= maxSemiperimeter:
        if thisSemiperimeter > maxSemiperimeter:
          maxSemiperimeter = thisSemiperimeter

        thisBitrate = getBitrate(stream)
        if thisBitrate > maxBitrate:
          maxBitrate = thisBitrate
          select = idx
    inc idx

  if select > -1:
    result = streams[select]


proc selectAudioByBitrate(streams: JsonNode, codec: string): JsonNode =
  ## select $codec audo stream with highest bitrate
  var
    thisBitrate, maxBitrate, idx: int
    select = -1
  result = newJNull()

  for stream in streams:
    if stream["mimeType"].getStr().contains(codec):
      thisBitrate = getBitrate(stream)
      if thisBitrate > maxBitrate:
        maxBitrate = thisBitrate
        select = idx
    inc idx

  if select > -1:
    result = streams[select]


proc selectVideoStream(streams: JsonNode, itag: int, codec: string): JsonNode =
  #[ NOTE: in tests, when adding up all samples where (subjectively) vp9 looked better, the average
    weight (vp9 bitrate/avc1 bitrate) was 0.92; this is fine in most cases. however a strong vp9 bias is preferential so
    a value of 0.8 is used. ]#
  const threshold = 0.8
  var vp9Semiperimeter, avc1Semiperimeter, av1Semiperimeter: int
  result = newJNull()

  if itag != 0:
    # NOTE: select by user itag choice
    for stream in streams:
      if stream["itag"].getInt() == itag:
        result = stream
        break
  elif codec != "":
    # NOTE: select by user codec preference
    result = selectVideoByBitrate(streams, codec)
  else:
    #[ NOTE: auto stream selection

       av1, vp9 and avc1 are not directly comparable. avc1 requires higher
       bitrate / larger filesize to obtain comparable quality to vp9/av1. scenarios
       can occur where lower resolution avc1 streams are selected because they have
       higher bitrate but are not necessarily the most desireable stream.
       order of selection: highest resolution stream (any codec) --> av1 if bitrate >= others --> vp9 if vp9/avc1 >= 0.8 --> avc1
      ]#
    # NOTE: first select best stream from each codec
    let
      bestVP9 = selectVideoByBitrate(streams, "vp9")
      bestAVC1 = selectVideoByBitrate(streams, "avc1")
      bestAV1 = selectVideoByBitrate(streams, "av01")
    # NOTE: caclulate semiperimeter for each
    if bestVP9.kind != JNull:
      vp9Semiperimeter = bestVP9["width"].getInt() + bestVP9["height"].getInt()
    if bestAVC1.kind != JNull:
      avc1Semiperimeter = bestAVC1["width"].getInt() + bestAVC1["height"].getInt()
    if bestAV1.kind != JNull:
      av1Semiperimeter = bestAV1["width"].getInt() + bestAV1["height"].getInt()

    # NOTE: if any codec has a larger semiperimeter than the others, select it.
    if (vp9Semiperimeter > avc1Semiperimeter and vp9Semiperimeter > av1Semiperimeter) or
       (bestAVC1.kind == JNull and bestAV1.kind == JNull):
      result = bestVP9
    elif (avc1Semiperimeter > vp9Semiperimeter and avc1Semiperimeter > av1Semiperimeter) or
         (bestVP9.kind == JNull and bestAV1.kind == JNull):
      result = bestAVC1
    elif (av1Semiperimeter > avc1Semiperimeter and av1Semiperimeter > vp9Semiperimeter) or
         (bestAVC1.kind == JNull and bestVP9.kind == JNull):
      result = bestAV1
    else:
      # NOTE: no semiperimeter > others condidate --> compare by bitrates
      let
        avc1Bitrate = getBitrate(bestAVC1)
        vp9Bitrate = getBitrate(bestVP9)
        av1Bitrate = getBitrate(bestAV1)
      # QUESTION: should av1 just be defaulted to if it exists and is the same resolution as others?
      if (av1Bitrate >= vp9Bitrate) and (av1Bitrate / avc1Bitrate >= threshold):
        result = bestAV1
      elif vp9Bitrate / avc1Bitrate >= threshold:
        result = bestVP9
      else:
        result = bestAVC1

  if result.kind == JNull:
    # NOTE: the itag/codec does not exist --> select zoroth stream
    result = streams[0]


proc selectAudioStream(streams: JsonNode, itag: int, codec: string): JsonNode =
  #[ NOTE: in tests, it seems youtube videos "without audio" still contain empty
    audio streams; furthermore aac streams seem to have a minimum bitrate as "empty"
    streams still have non trivial bitrate and filesizes.
  + "audio-less" video: https://www.youtube.com/watch?v=fW2e0CZjnFM
  + prefer opus
  + the majority of (all?) the time there are 4 audio streams:
    - itag 140 --> m4a
    - itag 251 --> opus
    + two low quality options (1 m4a and 1 opus) ]#
  result = newJNull()
  if itag != 0:
    # NOTE: select by user itag choice
    for stream in streams:
      if stream["itag"].getInt() == itag:
        return stream
  elif codec != "":
    # NOTE: select by user codec preference
    result = selectAudioByBitrate(streams, codec)
  else:
    # NOTE: fallback selection
    result = selectAudioByBitrate(streams, "opus")

  if result.kind == JNull:
    # NOTE: the itag/codec do not exist or there were no opus streams to fall back to.
    result = selectAudioByBitrate(streams, "mp4a")


proc getVideoStreamInfo(stream: JsonNode, duration: int): tuple[itag: int, mime, codec, ext, size, qlt, resolution, bitrate: string] =
  ## compile all relevent video stream metadata
  result.itag = stream["itag"].getInt()
  let mimeAndCodec = stream["mimeType"].getStr().split("; codecs=\"")
  result.mime = mimeAndCodec[0]
  result.codec = mimeAndCodec[1].strip(chars={'"'})
  result.ext = extensions[result.mime]
  result.qlt = stream["qualityLabel"].getStr()
  result.resolution = $stream["width"].getInt() & 'x' & $stream["height"].getInt()

  let rawBitrate = getBitrate(stream)
  result.bitrate = formatSize(rawBitrate, includeSpace=true) & "/s"

  if stream.hasKey("contentLength"):
    result.size = formatSize(parseInt(stream["contentLength"].getStr()), includeSpace=true)
  else:
    # NOTE: estimate from bitrate
    # WARNING: this is innacurate when the average bitrate it not available
    result.size = formatSize(int(rawBitrate * duration / 8), includeSpace=true)


proc getAudioStreamInfo(stream: JsonNode, duration: int): tuple[itag: int, mime, codec, ext, size, qlt, bitrate: string] =
  ## compile all relevent audio stream metadata
  result.itag = stream["itag"].getInt()
  let mimeAndCodec = stream["mimeType"].getStr().split("; codecs=\"")
  result.mime = mimeAndCodec[0]
  result.codec = mimeAndCodec[1].strip(chars={'"'})
  result.ext = extensions[result.mime]
  result.qlt = stream["audioQuality"].getStr().replace("AUDIO_QUALITY_").toLowerAscii()

  let rawBitrate = getBitrate(stream)
  result.bitrate = formatSize(rawBitrate, includeSpace=true) & "/s"

  if stream.hasKey("contentLength"):
    result.size = formatSize(parseInt(stream["contentLength"].getStr()), includeSpace=true)
  else:
    # NOTE: estimate from bitrate
    # WARNING: this is innacurate when the average bitrate it not available
    result.size = formatSize(int(rawBitrate * duration / 8), includeSpace=true)


proc newVideoStream(youtubeUrl, dashManifestUrl, videoId: string, duration: int, stream: JsonNode): Stream =
  if stream.kind != JNull:
    # NOTE: should NEVER be JNull but go through the motions anyway for parity with newAudioStream
    (result.itag, result.mime, result.codec, result.ext, result.size, result.quality, result.resolution, result.bitrate) = getVideoStreamInfo(stream, duration)
    result.filename = addFileExt(videoId, result.ext)
    # QUESTION: are all DASH segment streams denoted with "FORMAT_STREAM_TYPE_OTF"?
    if stream.hasKey("type") and stream["type"].getStr() == "FORMAT_STREAM_TYPE_OTF":
      # QUESTION: are DASH urls or manifest urls ever ciphered?
      var segmentList: string
      result.isDash = true
      logDebug("DASH manifest: ", dashManifestUrl)
      (result.baseUrl, segmentList) = extractDashInfo(dashManifestUrl, $result.itag)
      result.urlSegments = produceDashSegments(result.baseUrl, segmentList)
      # TODO: add len check here and fallback to stream[0] or similar if needed.
      # IDEA: consider taking all streams as argument which will allow redoing of selectVideoStream as needed.
    else:
      result.url = urlOrCipher(stream)
    result.exists = true


proc newAudioStream(youtubeUrl, dashManifestUrl, videoId: string, duration: int, stream: JsonNode): Stream =
  if stream.kind != JNull:
    (result.itag, result.mime, result.codec, result.ext, result.size, result.quality, result.bitrate) = getAudioStreamInfo(stream, duration)
    result.filename = addFileExt(videoId, result.ext)
    # QUESTION: are all dash segment stream denoted with "FORMAT_STREAM_TYPE_OTF"?
    if stream.hasKey("type") and stream["type"].getStr() == "FORMAT_STREAM_TYPE_OTF":
      # QUESTION: are dash urls or manifest urls ever ciphered?
      # QUESTION: are audio streams ever FORMAT_STREAM_TYPE_OTF?
      var segmentList: string
      result.isDash = true
      (result.baseUrl, segmentList) = extractDashInfo(dashManifestUrl, $result.itag)
      result.urlSegments = produceDashSegments(result.baseUrl, segmentList)
    else:
      result.url = urlOrCipher(stream)
    result.exists = true


proc newVideo(youtubeUrl, dashManifestUrl, thumbnailUrl, title, videoId: string, duration: int,
              streamingData: JsonNode, aItag, vItag: int, aCodec, vCodec: string): Video =
  result.title = title
  result.url = youtubeUrl
  result.videoId = videoId
  result.thumbnailUrl = thumbnailUrl
  if streamingData.hasKey("adaptiveFormats") and streamingData["adaptiveFormats"].hasItag(vItag):
    result.videoStream = newVideoStream(youtubeUrl, dashManifestUrl, videoId, duration,
                                        selectVideoStream(streamingData["adaptiveFormats"], vItag, vCodec))
    result.audioStream = newAudioStream(youtubeUrl, dashManifestUrl, videoId, duration,
                                        selectAudioStream(streamingData["adaptiveFormats"], aItag, aCodec))
  else:
    result.videoStream = newVideoStream(youtubeUrl, dashManifestUrl, videoId, duration,
                                        selectVideoStream(streamingData["formats"], vItag, vCodec))


proc reportStreamInfo(stream: Stream) =
  ## echo metadata for single stream
  logInfo("stream: ", stream.filename)
  logInfo("itag: ", stream.itag)
  logInfo("size: ", stream.size)
  logInfo("quality: ", stream.quality)
  logInfo("mime: ", stream.mime)
  logInfo("codec: ", stream.codec)
  if stream.isDash:
    logInfo("segments: ", stream.urlSegments.len)


proc reportStreams(playerResponse: JsonNode, duration: int) =
  ## echo metadata for all streams
  var
    itag: int
    mime, codec, ext, size, quality, resolution, bitrate: string

  if playerResponse["streamingData"].hasKey("adaptiveFormats"):
    # NOTE: streaming formats
    for item in playerResponse["streamingData"]["adaptiveFormats"]:
      if item.hasKey("audioQuality"):
        (itag, mime, codec, ext, size, quality, bitrate) = getAudioStreamInfo(item, duration)
        echo "[audio]", " itag: ", itag,
             " quality: ", quality,
             " bitrate: ", bitrate,
             " mime: ", mime,
             " codec: ", codec,
             " size: ", size
      else:
        (itag, mime, codec, ext, size, quality, resolution, bitrate) = getVideoStreamInfo(item, duration)
        echo "[video]", " itag: ", itag,
             " quality: ", quality,
             " resolution: ", resolution,
             " bitrate: ", bitrate,
             " mime: ", mime,
             " codec: ", codec,
             " size: ", size

  if playerResponse["streamingData"].hasKey("formats"):
    # NOTE: youtube premium download formats
    for n in countdown(playerResponse["streamingData"]["formats"].len.pred, 0):
      (itag, mime, codec, ext, size, quality, resolution, bitrate) = getVideoStreamInfo(playerResponse["streamingData"]["formats"][n], duration)
      echo "[combined]", " itag: ", itag,
           " quality: ", quality,
           " resolution: ", resolution,
           " bitrate: ", bitrate,
           " mime: ", mime,
           " codec: ", codec,
           " size: ", size


########################################################
# misc
########################################################


proc parseBaseJS() =
  ## extract cipher and throttle javascript code from youtube base.js
  logDebug("baseJS version: ", globalBaseJsVersion)
  logDebug("api locale: ", apiLocale)
  let (code, response) = doGet(baseJsUrl % [globalBaseJsVersion, apiLocale])
  if code.is2xx:
    # NOTE: cipher code
    cipherPlan = extractFunctionPlan(response)
    cipherFunctionMap = createFunctionMap(response, extractParentFunctionName(cipherPlan[0]))
    # NOTE: throttle code
    let throttleCode = extractThrottleCode(extractThrottleFunctionName(response), response)
    throttlePlan = parseThrottlePlan(throttleCode)
    throttleArray = parseThrottleArray(throttleCode)


proc isolateVideoId(youtubeUrl: string): string =
  if youtubeUrl.contains("youtu.be"):
    result = youtubeUrl.captureBetween('/', '?', youtubeUrl.find(".be"))
  elif youtubeUrl.contains("/shorts/"):
    result = youtubeUrl.captureBetween('/', '?', youtubeUrl.find("shorts/"))
  elif youtubeUrl.contains("/embed/"):
    result = youtubeUrl.captureBetween('/', '?', youtubeUrl.find("embed/"))
  else:
    result = youtubeUrl.captureBetween('=', '&')


proc isolateChannel(youtubeUrl: string): string =
  if "/c/" in youtubeUrl:
    # NOTE: vanity
    let (_, response) = doGet(youtubeUrl)
    result = response.captureBetween('"', '"', response.find("""browseId":""") + 9)
  else:
    result = youtubeUrl.captureBetween('/', '/', youtubeUrl.find("channel"))


proc isolatePlaylist(youtubeUrl: string): string =
  result = youtubeUrl.captureBetween('=', '&', youtubeUrl.find("list="))


proc giveReasons(reason: JsonNode) =
  ## iterate over and echo youtube reason
  if reason.hasKey("runs"):
    stdout.write("<error> ")
    for run in reason["runs"]:
      stdout.write(run["text"])
    stdout.write('\n')
  elif reason.hasKey("simpleText"):
    logError(reason["simpleText"].getStr().strip(chars={'"'}))


proc walkErrorMessage(playabilityStatus: JsonNode) =
  #[ FIXME: some (currently playing) live streams have error messages that do not fall in any of these catagories
    and the program exits with no output ]#
  if playabilityStatus.hasKey("reason"):
    logError(playabilityStatus["reason"].getStr().strip(chars={'"'}))
  elif playabilityStatus.hasKey("messages"):
    for message in playabilityStatus["messages"]:
      logError(message.getStr().strip(chars={'"'}))

  # if playabilityStatus.hasKey("errorScreen"):
  #   if playabilityStatus["errorScreen"]["playerErrorMessageRenderer"].hasKey("reason"):
  #     giveReasons(playabilityStatus["errorScreen"]["playerErrorMessageRenderer"]["reason"])
    # if playabilityStatus["errorScreen"]["playerErrorMessageRenderer"].hasKey("subreason"):
    #   giveReasons(playabilityStatus["errorScreen"]["playerErrorMessageRenderer"]["subreason"])


########################################################
# main
########################################################


proc getVideo(youtubeUrl: string, aItag, vItag: int, aCodec, vCodec: string) =
  let
    videoId = isolateVideoId(youtubeUrl)
    standardYoutubeUrl = watchUrl & videoId
  var
    code: HttpCode
    response: string
    playerResponse: JsonNode
    dashManifestUrl: string
    captions: string

  logGeneric(lvlInfo, "youtube", videoId)

  # NOTE: make initial request to get base.js version, timestamp, and api locale
  (code, response) = doGet(standardYoutubeUrl)
  if code.is2xx:
    apiLocale = response.captureBetween('\"', '\"', response.find("GAPI_LOCALE\":") + 12)
    let
      sigTimeStamp = response.captureBetween(':', ',', response.find("\"STS\""))
      thisBaseJsVersion = response.captureBetween('/', '/', response.find("""jsUrl":"/s/player/""") + 11)
    if thisBaseJsVersion != globalBaseJsVersion:
      globalBaseJsVersion = thisBaseJsVersion
      parseBaseJS()

    (code, response) = doPost(playerUrl, playerContext % [videoId, sigTimeStamp, date])
    if code.is2xx:
      playerResponse = parseJson(response)
      if playerResponse["playabilityStatus"]["status"].getStr() != "OK" and not playerResponse.hasKey("videoDetails"):
        walkErrorMessage(playerResponse["playabilityStatus"])
        return

      let
        title = playerResponse["videoDetails"]["title"].getStr()
        safeTitle = makeSafe(title)
        fullFilename = addFileExt(safeTitle & " [" & videoId & ']', ".mkv")
        duration = parseInt(playerResponse["videoDetails"]["lengthSeconds"].getStr())
        thumbnailUrl = playerResponse["videoDetails"]["thumbnail"]["thumbnails"][^1]["url"].getStr().dequery().multiReplace(("_webp", ""), (".webp", ".jpg"))

      if fileExists(fullFilename) and not showStreams:
        logError("file exists: ", fullFilename)
      else:
        # NOTE: age gate and unplayable video handling
        if playerResponse["playabilityStatus"]["status"].getStr() == "LOGIN_REQUIRED":
          for idx, ctx in [playerBypassContextTier1, playerBypassContextTier2, playerBypassContextTier3]:
            logNotice("attempting age-gate bypass tier $1" % $idx.succ)
            (code, response) = doPost(playerUrl, ctx % [videoId, sigTimeStamp, date])
            playerResponse = parseJson(response)
            if playerResponse["playabilityStatus"]["status"].getStr() != "OK":
              walkErrorMessage(playerResponse["playabilityStatus"])
              if idx == 2:
                return
            else:
              break
        elif playerResponse["videoDetails"].hasKey("isLive") and playerResponse["videoDetails"]["isLive"].getBool():
          if playerResponse["videoDetails"]["isLiveContent"].getBool():
            logError("this video is currently live")
          else:
            logError("this video is currently premiering")
          return
        elif playerResponse["playabilityStatus"]["status"].getStr() != "OK":
          walkErrorMessage(playerResponse["playabilityStatus"])
          return

        if showStreams:
          reportStreams(playerResponse, duration)
          return

        # QUESTION: hlsManifestUrl seems to be for live streamed videos but is it ever needed?
        if playerResponse["streamingData"].hasKey("dashManifestUrl"):
          dashManifestUrl = playerResponse["streamingData"]["dashManifestUrl"].getStr()
        let video = newVideo(standardYoutubeUrl, dashManifestUrl, thumbnailUrl, title, videoId, duration,
                             playerResponse["streamingData"], aItag, vItag, aCodec, vCodec)
        logInfo("title: ", video.title)

        if includeThumb:
          if not grab(video.thumbnailUrl, fullFilename.changeFileExt("jpeg"), forceDl=true).is2xx:
            logError("failed to download thumbnail")

        if includeSubtitles:
          if playerResponse.hasKey("captions"):
            generateSubtitles(playerResponse["captions"])
          else:
            includeSubtitles = false
            logError("video does not contain subtitles")

        var attempt: HttpCode
        if includeVideo:
          reportStreamInfo(video.videoStream)
          if video.videoStream.isDash:
            attempt = grab(video.videoStream.urlSegments, video.videoStream.filename, forceDl=true)
          else:
            attempt = grab(video.videoStream.url, video.videoStream.filename, forceDl=true)
          if not attempt.is2xx:
            logError("failed to download video stream")
            includeVideo = false
            # NOTE: remove empty file
            discard tryRemoveFile(video.videoStream.filename)

        if includeAudio and video.audioStream.exists:
          reportStreamInfo(video.audioStream)
          if video.audioStream.isDash:
            attempt = grab(video.audioStream.urlSegments, video.audioStream.filename, forceDl=true)
          else:
            attempt = grab(video.audioStream.url, video.audioStream.filename, forceDl=true)
          if not attempt.is2xx:
            logError("failed to download audio stream")
            includeAudio = false
            # NOTE: remove empty file
            discard tryRemoveFile(video.audioStream.filename)
        else:
          includeAudio = false

        # QUESTION: should we abort if either audio or video streams failed to download?
        if includeAudio and includeVideo:
          joinStreams(video.videoStream.filename, video.audioStream.filename, fullFilename, subtitlesLanguage, includeSubtitles)
        elif includeAudio and not includeVideo:
          convertAudio(video.audioStream.filename, safeTitle & " [" & videoId & ']', audioFormat)
        elif includeVideo:
          moveFile(video.videoStream.filename, fullFilename.changeFileExt(video.videoStream.ext))
          logGeneric(lvlInfo, "complete", addFileExt(safeTitle, video.videoStream.ext))
        else:
          logError("no streams were downloaded")
    else:
      logError(code)
      logError(videoMetadataFailureMessage)
  else:
    logError(code)
    logError(videoMetadataFailureMessage)


proc getPlaylist(youtubeUrl: string, aItag, vItag: int, aCodec, vCodec: string) =
  var ids: seq[string]
  let playlistId = isolatePlaylist(youtubeUrl)

  logDebug("playlist id: ", playlistId)

  let (code, response) = doPost(nextUrl, playlistContext % [playlistId, date])
  if code.is2xx:
    let
      playlistResponse = parseJson(response)
      title = playlistResponse["contents"]["twoColumnWatchNextResults"]["playlist"]["playlist"]["title"].getStr()
    logInfo("collecting videos: ", title)

    if playlistResponse["contents"]["twoColumnWatchNextResults"]["playlist"]["playlist"]["isInfinite"].getBool():
      logError("infinite playlist...aborting")
    else:
      for item in playlistResponse["contents"]["twoColumnWatchNextResults"]["playlist"]["playlist"]["contents"]:
        ids.add(item["playlistPanelVideoRenderer"]["videoId"].getStr())

      logInfo(ids.len, " videos queued")
      for idx, id in ids:
        logInfo(idx.succ, " of ", ids.len)
        getVideo(watchUrl & id, aItag, vItag, aCodec, vCodec)
  else:
    logError(code)
    logError(playlistMetadataFailureMessage)


proc getChannel(youtubeUrl: string, aItag, vItag: int, aCodec, vCodec: string) =
  let channel = isolateChannel(youtubeUrl)
  var
    channelResponse: JsonNode
    response: string
    code: HttpCode
    thisToken, lastToken: string
    videoIds: seq[string]
    playlistIds: seq[string]
    tabIdx = 1

  logDebug("channel: ", channel)

  iterator gridRendererExtractor(renderer: string): string =
    let capRenderer = capitalizeAscii(renderer)
    for section in channelResponse["contents"]["twoColumnBrowseResultsRenderer"]["tabs"][tabIdx]["tabRenderer"]["content"]["sectionListRenderer"]["contents"]:
      if section["itemSectionRenderer"]["contents"][0].hasKey("messageRenderer"):
        logError(section["itemSectionRenderer"]["contents"][0]["messageRenderer"]["text"]["simpleText"].getStr())
      else:
        for item in section["itemSectionRenderer"]["contents"][0]["gridRenderer"]["items"]:
          if item.hasKey("continuationItemRenderer"):
            thisToken = item["continuationItemRenderer"]["continuationEndpoint"]["continuationCommand"]["token"].getStr()
            lastToken = thisToken

            while true:
              (code, response) = doPost(browseUrl, browseContinueContext % [channel, date, thisToken])
              if code.is2xx:
                channelResponse = parseJson(response)
                for continuationItem in channelResponse["onResponseReceivedActions"][0]["appendContinuationItemsAction"]["continuationItems"]:
                  if continuationItem.hasKey("continuationItemRenderer"):
                    thisToken = continuationItem["continuationItemRenderer"]["continuationEndpoint"]["continuationCommand"]["token"].getStr()
                  else:
                    yield continuationItem["grid" & capRenderer & "Renderer"][renderer & "Id"].getStr()
                if thisToken == lastToken:
                  break
                else:
                  lastToken = thisToken
              else:
                logError(channelMetadataFailureMessage)
          else:
            yield item["grid" & capRenderer & "Renderer"][renderer & "Id"].getStr()

  (code, response) = doPost(browseUrl, browseContext % [channel, date, videosTab])
  if code.is2xx:
    logInfo("collecting videos")
    channelResponse = parseJson(response)
    let title = channelResponse["metadata"]["channelMetadataRenderer"]["title"].getStr()
    if channelResponse["contents"]["twoColumnBrowseResultsRenderer"]["tabs"][tabIdx]["tabRenderer"]["title"].getStr() == "Videos":
      for id in gridRendererExtractor("video"):
        videoIds.add(id)
      inc tabIdx

    if title.endsWith(" - Topic"):
      # NOTE: for now only get playlists for topic channels (youtube music)
      (code, response) = doPost(browseUrl, browseContext % [channel, date, playlistsTab])
      if code.is2xx:
        logInfo("collecting playlists")
        channelResponse = parseJson(response)
        if channelResponse["contents"]["twoColumnBrowseResultsRenderer"]["tabs"][tabIdx]["tabRenderer"]["title"].getStr() == "Playlists":
          for section in channelResponse["contents"]["twoColumnBrowseResultsRenderer"]["tabs"][tabIdx]["tabRenderer"]["content"]["sectionListRenderer"]["contents"]:
            if section["itemSectionRenderer"]["contents"][0].hasKey("messageRenderer"):
              logError(section["itemSectionRenderer"]["contents"][0]["messageRenderer"]["text"]["simpleText"].getStr())
            else:
              if section["itemSectionRenderer"]["contents"][0].hasKey("gridRenderer"):
                # NOTE: gridRenderer
                for id in gridRendererExtractor("playlist"):
                  playlistIds.add(id)
              elif section["itemSectionRenderer"]["contents"][0].hasKey("shelfRenderer"):
                if section["itemSectionRenderer"]["contents"][0]["shelfRenderer"]["content"].hasKey("expandedShelfContentsRenderer"):
                  # NOTE: expandedShelfContentsRenderer
                  for item in section["itemSectionRenderer"]["contents"][0]["shelfRenderer"]["content"]["expandedShelfContentsRenderer"]["items"]:
                    playlistIds.add(item["playlistRenderer"]["playlistId"].getStr())
                elif section["itemSectionRenderer"]["contents"][0]["shelfRenderer"]["content"].hasKey("horizontalListRenderer"):
                  # NOTE: horizontalListRenderer
                  for item in section["itemSectionRenderer"]["contents"][0]["shelfRenderer"]["content"]["horizontalListRenderer"]["items"]:
                    playlistIds.add(item["gridPlaylistRenderer"]["playlistId"].getStr())
                else:
                  logError(channelMetadataFailureMessage)
              else:
                logError(channelMetadataFailureMessage)
        else:
          logError(channelMetadataFailureMessage)
      else:
        logError(code)
        logError(channelMetadataFailureMessage)
  else:
    logError(code)
    logError(channelMetadataFailureMessage)

  logInfo(videoIds.len, " videos queued")
  logInfo(playlistIds.len, " playlists queued")
  for idx, id in videoIds:
    logInfo(idx.succ, " of ", videoIds.len)
    getVideo(watchUrl & id, aItag, vItag, aCodec, vCodec)
  for id in playlistIds:
    getPlaylist(playlistUrl & id, aItag, vItag, aCodec, vCodec)


proc youtubeDownload*(youtubeUrl, aFormat, aItag, vItag, aCodec, vCodec, sLang: string,
                      iAudio, iVideo, iThumb, iSubtitles, sStreams, debug, silent: bool) =
  includeAudio = iAudio
  includeVideo = iVideo
  includeThumb = iThumb
  includeSubtitles = iSubtitles
  subtitlesLanguage = sLang
  audioFormat = aFormat
  showStreams = sStreams

  if debug:
    globalLogLevel = lvlDebug
  elif silent:
    globalLogLevel = lvlNone

  # QUESTION: make codecs and itags global?
  if "/channel/" in youtubeUrl or "/c/" in youtubeUrl:
    getChannel(youtubeUrl, parseInt(aItag), parseInt(vItag), aCodec, vCodec)
  elif "/playlist?" in youtubeUrl:
    getPlaylist(youtubeUrl, parseInt(aItag), parseInt(vItag), aCodec, vCodec)
  else:
    getVideo(youtubeUrl, parseInt(aItag), parseInt(vItag), aCodec, vCodec)
