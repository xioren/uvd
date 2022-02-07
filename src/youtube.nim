# import std/[sha1]

import common

#[ NOTE:
  age gate tier 1: https://www.youtube.com/watch?v=HtVdAasjOgU
  age gate tier 2: https://www.youtube.com/watch?v=Tq92D6wQ1mg
  age gate tier 3: https://www.youtube.com/watch?v=7iAQCPmpSUI
  age gate tier 4: https://www.youtube.com/watch?v=Cr381pDsSsA
]#

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
  # QUESTION: should this table be cleared if the js version is changed while running?
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
  ## convert times to SubRip format
  var parts: seq[string]
  if time.contains('.'):
    # NOTE: float seconds.milliseconds
    parts = time.split('.')
  else:
    # NOTE: int seconds
    parts = @[time, "000"]


  let td = initDuration(seconds=parseInt(parts[0]), milliseconds=parseInt(&"""{parts[1]:.3}""")).toParts()
  result = ($td[Hours]).align(2, '0') & ':' & ($td[Minutes]).align(2, '0') & ':' & ($td[Seconds]).align(2, '0') & ',' & ($td[Milliseconds]).align(3, '0')


proc asrToSrt(xml: string): string =
  ## convert youtube native asr captions to SubRip format
  #[ IDEA: this can be done without splitting. consider parsing each entry out entirely
    and then parsing meta data from that entry. ]#
  var entries: string
  discard xml.parseUntil(entries, "</transcript>", xml.find("<transcript>"))
  let splitEntries = entries.split("/text>")
  var
    startPoint: string
    nextStartPoint: string
    endPoint: string
    duration: string
    text: string
    parseIdx: int

  for idx, entry in splitEntries[0..^2]:
    result.add($idx.succ & '\n')
    parseIdx = entry.skipUntil('"')
    parseIdx.inc(entry.parseUntil(startPoint, '"', parseIdx.succ) + 2)
    parseIdx.inc(entry.skipUntil('"', parseIdx) + 1)
    parseIdx.inc(entry.parseUntil(duration, '"', parseIdx))
    text = entry.captureBetween('>', '<', parseIdx)
    endPoint = $(parseFloat(startPoint) + parseFloat(duration))

    if idx < splitEntries.high.pred:
      #[ NOTE: choose min between enpoint of current text and startpoint of next text to eliminate crowding
        i.e. only one subtitle entry on screen at a time ]#
      nextStartPoint = splitEntries[idx.succ].captureBetween('"', '"')
      result.add(formatTime(startPoint) & " --> " & formatTime($min(parseFloat(endPoint), parseFloat(nextStartPoint))) & '\n')
      result.add(text.replace("&amp;#39;", "'") & "\n\n")
    else:
      result.add(formatTime(startPoint) & " --> " & formatTime(endPoint) & '\n')
      result.add(text.replace("&amp;#39;", "'"))


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
    logDebug("requesting captions")
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
# youtube specific hls / dash manifest parsing
########################################################


proc extractDashInfo(dashEntry: string): tuple[itag, resolution, fps, codecs: string] =
  ## parse meta data for given dash entry
  let
    width = dashEntry.captureBetween('"', '"', dashEntry.find("width="))
    height = dashEntry.captureBetween('"', '"', dashEntry.find("height="))
  result.itag = dashEntry.captureBetween('"', '"', dashEntry.find("id="))
  result.resolution = width & 'x' & height
  result.fps = dashEntry.captureBetween('"', '"', dashEntry.find("frameRate="))
  result.codecs = dashEntry.captureBetween('"', '"', dashEntry.find("codecs="))


proc extractDashEntry(dashManifestUrl, id: string): string =
  ## parse specific itag's dash entry from xml
  logDebug("requesting dash manifest")
  let (_, xml) = doGet(dashManifestUrl)
  discard xml.parseUntil(result, "</Representation>", xml.find("""<Representation id="$1""" % id))


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
    unshift: function(d,e){for(e=(e%d.length+d.length)%d.length;e--;)d.unshift(d.pop())};
    prepend: function(d,e){e=(e%d.length+d.length)%d.length;d.splice(-e).reverse().forEach(function(f){d.unshift(f)})};
  ]#
  d.rotateLeft(d.len - throttleModFunction(d, e))


proc throttleCipher(d, e: var string, f: array[64, char]) {.inline.} =
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
  # NOTE: function(d,e){d.push(e)}
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
  # NOTE: iha=function(a){var b=a.split("") --> iha
  discard js.parseUntil(result, "=", js.find("""a.split(""),c=[""") - 22)


proc extractThrottleCode(mainFunc, js: string): string =
  ## extract throttle code block from base.js
  # NOTE: iha=function(a){var b=a.split("").....a.join("")}
  discard js.parseUntil(result, "catch(d)", js.find("\n" & mainFunc) + 1)


iterator splitThrottleArray(js: string): string =
  ## split c array into individual elements
  var
    code: string
    step: string
    scope: int

  if js.contains("];\nc["):
    discard js.parseUntil(code, "];\nc[", js.find(",c=[") + 4)
  else:
    discard js.parseUntil(code, "];c[", js.find(",c=[") + 4)

  for idx, c in code:
    #[ NOTE: commas separate function arguments and functions themselves.
      only yield if the comma is separating two functions in the base scope
      and not function arguments or child functions.
    ]#
    if (c == ',' and scope == 0 and '{' notin code[idx..min(idx + 5, code.high)]) or idx == code.high:
      if idx == code.high:
        step.add(c)
      yield step.multiReplace(("\x00", ""), ("\n", ""))
      step = ""
    else:
      if c == '{':
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
  let plan = js.captureBetween('{', '}', js.find("try"))
  var step: seq[string]
  var last: char
  for idx, c in plan:
    if c == 'c':
      step.add(plan.captureBetween('[', ']', idx))
    elif c == ',' and last == ')':
      result.add(step)
      step = @[]
    elif idx == plan.high:
      result.add(step)
    last = c


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
  var functions: string
  discard js.parseUntil(functions, ";return", js.find("""=function(a){a=a.split("");""") + 27)
  result = functions.split(';')


proc extractParentFunctionName(jsFunction: string): string =
  ## get the name of the function containing the scramble functions
  ## ix.Nh(a,2) --> ix
  discard jsFunction.parseUntil(result, '.')


proc parseChildFunction(function: string): tuple[name: string, argument: int] =
  ## returns child function name and second argument
  ## ix.ai(a,5) --> (ai, 5)
  result.name = function.captureBetween('.', '(')
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
  var code: string
  discard js.parseUntil(code, "};", js.find("""var $1={""" % mainFunc) + 7)
  for item in code[1..^1].split(",\n"):
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


proc urlOrCipher(stream: Stream): string =
  ## produce stream url, deciphering if necessary and tranform n throttle string
  if not stream.url.startsWith("https"):
    result = getSigCipherUrl(stream.url)
  else:
    result = stream.url

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


proc getBitrate(stream: JsonNode): int =
  ## extract bitrate value from json. prefers average bitrate.
  if stream.hasKey("averageBitrate"):
    # NOTE: not present in DASH streams metadata
    result = stream["averageBitrate"].getInt()
  else:
    result = stream["bitrate"].getInt()


proc selectVideoStream(streams: seq[Stream], id, codec: string): Stream =
  #[ NOTE: in tests, when adding up all samples where (subjectively) vp9 looked better, the average
    weight (vp9 bitrate/avc1 bitrate) was 0.92; this is fine in most cases. however a strong vp9 bias is preferential so
    a value of 0.8 is used. ]#
  const threshold = 0.8

  if id != "":
    # NOTE: select by user itag choice
    for stream in streams:
      if stream.id == id:
        return stream
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
    # NOTE: if any codec has a larger semiperimeter than the others, select it.
    if (bestVP9.semiperimeter > bestAVC1.semiperimeter and bestVP9.semiperimeter > bestAV1.semiperimeter):
      result = bestVP9
    elif (bestAVC1.semiperimeter > bestVP9.semiperimeter and bestAVC1.semiperimeter > bestAV1.semiperimeter):
      result = bestAVC1
    elif (bestAV1.semiperimeter > bestAVC1.semiperimeter and bestAV1.semiperimeter > bestVP9.semiperimeter):
      result = bestAV1
    else:
      # QUESTION: should av1 just be defaulted to if it exists and is the same resolution as others?
      if (bestAV1.bitrate >= bestVP9.bitrate) and (bestAV1.bitrate / bestAVC1.bitrate >= threshold):
        result = bestAV1
      elif bestVP9.bitrate / bestAVC1.bitrate >= threshold:
        result = bestVP9
      else:
        result = bestAVC1
  if result.id == "":
    result = streams[0]


proc selectAudioStream(streams: seq[Stream], id, codec: string): Stream =
  #[ NOTE: in tests, it seems youtube videos "without audio" still contain empty
    audio streams; furthermore aac streams seem to have a minimum bitrate as "empty"
    streams still have non trivial bitrate and filesizes.
  + "audio-less" video: https://www.youtube.com/watch?v=fW2e0CZjnFM
  + prefer opus
  + the majority of (all?) the time there are 4 audio streams:
    - itag 140 --> m4a
    - itag 251 --> opus
    + two low quality options (1 m4a and 1 opus) ]#
  if id != "":
    # NOTE: select by user itag choice
    for stream in streams:
      if stream.id == id:
        return stream
  elif codec != "":
    # NOTE: select by user codec preference
    result = selectAudioByBitrate(streams, codec)
  else:
    # NOTE: fallback selection
    result = selectAudioByBitrate(streams, "opus")


proc newStream(stream: JsonNode, videoId: string, duration: int, segmentsUrl = ""): Stream =
  ## populate new stream
  if stream.kind != JNull:
    if stream.hasKey("width") and stream.hasKey("audioQuality"):
      result.kind = "combined"
    elif stream.hasKey("audioQuality"):
      result.kind = "audio"
    else:
      result.kind = "video"

    if result.kind == "audio":
      result.quality = stream["audioQuality"].getStr().replace("AUDIO_QUALITY_").toLowerAscii()
    else:
      result.resolution = $stream["width"].getInt() & 'x' & $stream["height"].getInt()
      result.semiperimeter = stream["width"].getInt() + stream["height"].getInt()
      result.quality = stream["qualityLabel"].getStr()
      result.fps = $stream["fps"].getInt()

    result.id = $stream["itag"].getInt()
    let mimeAndCodec = stream["mimeType"].getStr().split("; codecs=\"")
    result.mime = mimeAndCodec[0]
    result.codec = mimeAndCodec[1].strip(chars={'"'})
    result.ext = extensions[result.mime]

    result.bitrate = getBitrate(stream)
    result.bitrateShort = formatSize(result.bitrate, includeSpace=true) & "/s"

    if stream.hasKey("contentLength"):
      result.size = parseInt(stream["contentLength"].getStr())
    else:
      # NOTE: estimate from bitrate
      # WARNING: this is innacurate when the average bitrate it not available
      result.size = int(result.bitrate * duration / 8)
    result.sizeShort = formatSize(result.size, includeSpace=true)
    # IDEA: could also use contentLength?
    if (stream.hasKey("type") and stream["type"].getStr() == "FORMAT_STREAM_TYPE_OTF") or (not stream.hasKey("averageBitrate") and segmentsUrl != ""):
      result.format = "dash"
    else:
      result.format = "progressive"

    if stream.hasKey("url"):
      result.url = stream["url"].getStr()
    elif stream.hasKey("signatureCipher"):
      result.url = stream["signatureCipher"].getStr()

    result.duration = duration
    result.filename = addFileExt(videoId & "-" & result.kind, result.ext)
    result.exists = true


proc setUrl(stream: var Stream, dashManifestUrl="", hlsManifestUrl="") =
  ## decipher url or extract dash/hls segments
  #[ NOTE: this is not done in newStream so that requests are not made for manifests
    for each stream, and only done for the selected streams ]#
  if stream.format == "dash":
    var
      baseUrl: string
      segmentList: string
    logDebug("DASH manifest: ", dashManifestUrl)
    stream.urlSegments = extractDashSegments(extractDashEntry(dashManifestUrl, stream.id))
  else:
    stream.url = urlOrCipher(stream)


proc newDownload(streams: seq[Stream], title, youtubeUrl, thumbnailUrl, videoId,
              aItag, vItag, aCodec, vCodec: string, dashManifestUrl="", hlsManifestUrl=""): Download =
  result.title = title
  result.url = youtubeUrl
  result.videoId = videoId
  result.thumbnailUrl = thumbnailUrl
  if includeVideo:
    result.videoStream = selectVideoStream(streams, vItag, vCodec)
    result.videoStream.setUrl(dashManifestUrl, hlsManifestUrl)
  if includeAudio and result.videoStream.kind != "combined":
    result.audioStream = selectAudioStream(streams, aItag, aCodec)
    result.audioStream.setUrl(dashManifestUrl, hlsManifestUrl)


proc reportStreamInfo(stream: Stream) =
  ## echo metadata for single stream
  # TODO: expand this
  logInfo("stream: ", stream.filename)
  logInfo("itag: ", stream.id)
  logInfo("size: ", stream.sizeShort)
  logInfo("quality: ", stream.quality)
  logInfo("mime: ", stream.mime)
  logInfo("codec: ", stream.codec)
  if stream.format == "dash":
    logInfo("segments: ", stream.urlSegments.len)


########################################################
# misc
########################################################


proc parseBaseJS() =
  ## extract cipher and throttle javascript code from youtube base.js
  logDebug("baseJS version: ", globalBaseJsVersion)
  logDebug("api locale: ", apiLocale)
  logDebug("requesting base.js")
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
    #[ TODO: this should be extracted when the initial request is made instead of making
      two requests for the same content ]#
    logDebug("requesting webpage")
    let (_, response) = doGet(youtubeUrl)
    result = response.captureBetween('"', '"', response.find("""browseId":""") + 9)
  else:
    result = youtubeUrl.captureBetween('/', '/', youtubeUrl.find("channel"))


proc isolatePlaylist(youtubeUrl: string): string =
  result = youtubeUrl.captureBetween('=', '&', youtubeUrl.find("list="))


proc giveReasons(reason: JsonNode) =
  ## iterate over and echo youtube reason
  if reason.hasKey("runs"):
    stdout.write("[error] ")
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

  if playabilityStatus.hasKey("errorScreen"):
    # if playabilityStatus["errorScreen"]["playerErrorMessageRenderer"].hasKey("reason"):
    #   giveReasons(playabilityStatus["errorScreen"]["playerErrorMessageRenderer"]["reason"])
    if playabilityStatus["errorScreen"]["playerErrorMessageRenderer"].hasKey("subreason"):
      giveReasons(playabilityStatus["errorScreen"]["playerErrorMessageRenderer"]["subreason"])


########################################################
# main
########################################################


proc grabVideo(youtubeUrl, aItag, vItag, aCodec, vCodec: string) =
  let
    videoId = isolateVideoId(youtubeUrl)
    standardYoutubeUrl = watchUrl & videoId
  var
    code: HttpCode
    response: string
    playerResponse: JsonNode
    dashManifestUrl, hlsManifestUrl: string
    captions: string
    audioStreams: seq[Stream]
    videoStreams: seq[Stream]

  logInfo("video id: ", videoId)

  # NOTE: make initial request to get base.js version, timestamp, and api locale
  logDebug("requesting webpage")
  (code, response) = doGet(standardYoutubeUrl)
  if code.is2xx:
    apiLocale = response.captureBetween('\"', '\"', response.find("GAPI_LOCALE\":") + 12)
    let
      sigTimeStamp = response.captureBetween(':', ',', response.find("\"STS\""))
      thisBaseJsVersion = response.captureBetween('/', '/', response.find("""jsUrl":"/s/player/""") + 11)
    if thisBaseJsVersion != globalBaseJsVersion:
      globalBaseJsVersion = thisBaseJsVersion
      parseBaseJS()
    logDebug("requesting player")
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
            logDebug("requesting player")
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


        #[ NOTE: hls is for combined audio + videos streams (youtube premium downloads) while dash manifest
          is for single audio or videos streams. hls also seems to be specific to live streams. ]#
        if playerResponse["streamingData"].hasKey("dashManifestUrl"):
          dashManifestUrl = playerResponse["streamingData"]["dashManifestUrl"].getStr()
        if playerResponse["streamingData"].hasKey("hlsManifestUrl"):
          hlsManifestUrl = playerResponse["streamingData"]["hlsManifestUrl"].getStr()

        for stream in playerResponse["streamingData"]["adaptiveFormats"]:
          if stream.hasKey("width"):
            videoStreams.add(newStream(stream, videoId, duration, dashManifestUrl))
          else:
            audioStreams.add(newStream(stream, videoId, duration, dashManifestUrl))

        if playerResponse["streamingData"].hasKey("formats"):
          for stream in playerResponse["streamingData"]["formats"]:
            videoStreams.add(newStream(stream, videoId, duration))

        let allStreams = videoStreams.sorted(compareBitrate) & audioStreams.sorted(compareBitrate)

        if showStreams:
          displayStreams(allStreams)
          return

        let download = newDownload(allStreams, title, standardYoutubeUrl, thumbnailUrl, videoId, aItag, vItag, aCodec, vCodec, dashManifestUrl, hlsManifestUrl)
        logInfo("title: ", download.title)

        if includeThumb:
          if not grab(download.thumbnailUrl, fullFilename.changeFileExt("jpeg"), forceDl=true).is2xx:
            logError("failed to download thumbnail")

        if includeSubtitles:
          if playerResponse.hasKey("captions"):
            generateSubtitles(playerResponse["captions"])
          else:
            includeSubtitles = false
            logError("video does not contain subtitles")

        var attempt: HttpCode
        if includeVideo:
          reportStreamInfo(download.videoStream)
          if download.videoStream.format == "dash":
            attempt = grab(download.videoStream.urlSegments, download.videoStream.filename, forceDl=true)
          else:
            attempt = grab(download.videoStream.url, download.videoStream.filename, forceDl=true)
          if not attempt.is2xx:
            logError("failed to download video stream")
            includeVideo = false
            # NOTE: remove empty file
            discard tryRemoveFile(download.videoStream.filename)

        if includeAudio and download.audioStream.exists:
          reportStreamInfo(download.audioStream)
          if download.audioStream.format == "dash":
            attempt = grab(download.audioStream.urlSegments, download.audioStream.filename, forceDl=true)
          else:
            attempt = grab(download.audioStream.url, download.audioStream.filename, forceDl=true)
          if not attempt.is2xx:
            logError("failed to download audio stream")
            includeAudio = false
            # NOTE: remove empty file
            discard tryRemoveFile(download.audioStream.filename)
        else:
          includeAudio = false

        # QUESTION: should we abort if either audio or video streams failed to download?
        if includeAudio and includeVideo:
          streamsToMkv(download.videoStream.filename, download.audioStream.filename, fullFilename, subtitlesLanguage, includeSubtitles)
        elif includeAudio and not includeVideo:
          convertAudio(download.audioStream.filename, safeTitle & " [" & videoId & ']', audioFormat)
        elif includeVideo:
          streamToMkv(download.videoStream.filename, fullFilename, subtitlesLanguage, includeSubtitles)
        else:
          logError("no streams were downloaded")
    else:
      logError(code)
      logError(videoMetadataFailureMessage)
  else:
    logError(code)
    logError(videoMetadataFailureMessage)


proc grabPlaylist(youtubeUrl, aItag, vItag, aCodec, vCodec: string) =
  var videoIds: seq[string]
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
        videoIds.add(item["playlistPanelVideoRenderer"]["videoId"].getStr())

      logInfo(videoIds.len, " videos queued")
      for idx, id in videoIds:
        logGeneric(lvlInfo, "download", idx.succ, " of ", videoIds.len)
        grabVideo(watchUrl & id, aItag, vItag, aCodec, vCodec)
  else:
    logError(code)
    logError(playlistMetadataFailureMessage)


proc grabChannel(youtubeUrl, aItag, vItag, aCodec, vCodec: string) =
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
    logGeneric(lvlInfo, "download", idx.succ, " of ", videoIds.len)
    grabVideo(watchUrl & id, aItag, vItag, aCodec, vCodec)
  for id in playlistIds:
    grabPlaylist(playlistUrl & id, aItag, vItag, aCodec, vCodec)


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

  logGeneric(lvlInfo, "uvd", "youtube")

  # QUESTION: make codecs and itags global?
  if "/channel/" in youtubeUrl or "/c/" in youtubeUrl:
    grabChannel(youtubeUrl, aItag, vItag, aCodec, vCodec)
  elif "/playlist?" in youtubeUrl:
    grabPlaylist(youtubeUrl, aItag, vItag, aCodec, vCodec)
  else:
    grabVideo(youtubeUrl, aItag, vItag, aCodec, vCodec)
