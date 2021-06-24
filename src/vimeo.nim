import std/[json, uri, parseutils]

import utils


# NOTE: s=788550b1a916f3211f77d5261169782a1c4b5a46_1620593836
# sha1hash_timestamp
# timestamp == unix time
# can use toUnix(getTime()) or epochTime().int
# timestamp most likely used in hash as salt

# NOTE: vimeo=OHLd4DDZLe4MVHLXDDPL44ZtMxHDtBcDNdNca34c4DeXXtaDeN3tcDtXLSBN4BZ%2CZ%2CdMiwiViN5_59biw_ViY3HLXDDPL44ZtMIHcPBPZ%2C3BNDdXNDLec4DX4SZBdedDcdPDSceDZdDXXDtPaSNN3Z3aLDB3cNdZN%2C3S
# header needed for paid on demand config requests

type
  Stream = object
    title: string
    filename: string
    mime: string
    ext: string
    size: string
    quality: string
    initUrl: string
    baseUrl: string
    urlSegments: seq[string]
    exists: bool


const
  configUrl = "https://player.vimeo.com/video/$1/config"
  # detailsUrl = "http://vimeo.com/api/v2/video/$1.json"


proc isVerticle(stream: JsonNode): bool =
  # NOTE: streams are always w x h
  stream["height"].getInt() > stream["width"].getInt()


proc selectBestVideoStream(streams: JsonNode): JsonNode =
  var
    largest = 0
    dimension: string
  if isVerticle(streams[0]):
    dimension = "width"
  else:
    dimension = "height"
  for stream in streams:
    if stream[dimension].getInt() > largest:
      largest = stream[dimension].getInt()
      result = stream


proc selectBestAudioStream(streams: JsonNode): JsonNode =
  if streams.kind == JNull:
    result = streams
  else:
    var largest = 0
    for stream in streams:
      if stream["bitrate"].getInt() > largest:
        largest = stream["bitrate"].getInt()
        result = stream


proc getVideoStreamInfo(stream: JsonNode): tuple[mime, ext, size, qlt: string] =
  result.mime = stream["mime_type"].getStr()
  result.ext = extensions[result.mime]
  if isVerticle(stream):
    result.qlt = $stream["width"].getInt() & "p"
  else:
    result.qlt = $stream["height"].getInt() & "p"
  var size = 0
  for segment in stream["segments"]:
    size.inc(segment["size"].getInt())
  result.size = formatSize(size, includeSpace=true)


proc getAudioStreamInfo(stream: JsonNode): tuple[mime, ext, size, qlt: string] =
  result.mime = stream["mime_type"].getStr()
  result.ext = extensions[result.mime]
  result.qlt = $stream["sample_rate"].getInt()
  var size = 0
  for segment in stream["segments"]:
    size.inc(segment["size"].getInt())
  result.size = formatSize(size, includeSpace=true)


proc produceUrlSegments(cdnUrl, baseUrl, initUrl: string, stream: JsonNode): seq[string] =
  let cdn = parseUri(cdnUrl)
  result.add($(cdn / baseUrl / initUrl))
  for segment in stream["segments"]:
    result.add($(cdn / baseUrl / segment["url"].getStr()))


proc newVideoStream(cdnUrl, title: string, stream: JsonNode): Stream =
  result.title = title
  (result.mime, result.ext, result.size, result.quality) = getVideoStreamInfo(stream)
  result.filename = addFileExt("videostream", result.ext)
  result.baseUrl = stream["base_url"].getStr()
  result.initUrl = stream["init_segment"].getStr()
  result.urlSegments = produceUrlSegments(cdnUrl.split("sep/")[0] & "sep/video",
                                          result.baseUrl, result.initUrl, stream)
  result.exists = true


proc newAudioStream(cdnUrl, title: string, stream: JsonNode): Stream =
  if stream.kind != JNull:
    result.title = title
    (result.mime, result.ext, result.size, result.quality) = getAudioStreamInfo(stream)
    result.filename = addFileExt("audiostream", result.ext)
    result.baseUrl = stream["base_url"].getStr().strip(leading=true, chars={'.'})
    result.initUrl = stream["init_segment"].getStr()
    result.urlSegments = produceUrlSegments(cdnUrl.split("sep/")[0] & "sep/",
                                            result.baseUrl, result.initUrl, stream)
    result.exists = true


proc reportStreamInfo(stream: Stream) =
  once:
    echo "title: ", stream.title
  echo "stream: ", stream.filename, '\n',
       "size: ", stream.size, '\n',
       "quality: ", stream.quality, '\n',
       "mime: ", stream.mime, '\n',
       "segments: ", stream.urlSegments.len


proc vimeoDownload*(vimeoUrl: string) =
  var
    configResponse: JsonNode
    id, response: string
    code: HttpCode
  if vimeoUrl.contains("/video/"):
    id = vimeoUrl.captureBetween('/', '?', vimeoUrl.find("video/"))
  else:
    id = vimeoUrl.captureBetween('/', '?', vimeoUrl.find(".com/"))
  (code, response) = getThis(configUrl % id)
  if code == Http403:
    echo "[trying signed config url]"
    (code, response) = getThis(vimeoUrl)
    let signedConfigUrl = response.captureBetween('"', '"', response.find(""""config_url":""") + 13)
    (code, response) = getThis(signedConfigUrl.replace("\\"))
    configResponse = parseJson(response)
  elif not code.is2xx:
    return
  else:
    configResponse = parseJson(response)
  let
    title = configResponse["video"]["title"].getStr()
    safeTitle = title.multiReplace((".", ""), ("/", "-"), (": ", " - "), (":", "-"))
    finalPath = addFileExt(joinPath(getCurrentDir(), safeTitle), ".mkv")

  if fileExists(finalPath):
    echo "<file exists> ", safeTitle
  else:
    let
      defaultCdn = configResponse["request"]["files"]["dash"]["default_cdn"].getStr()
      cdnUrl = configResponse["request"]["files"]["dash"]["cdns"][defaultCdn]["url"].getStr()
    (code, response) = getThis(dequery(cdnUrl))
    let
      cdnResponse = parseJson(response)
      videoStream = newVideoStream(cdnUrl, title, selectBestVideoStream(cdnResponse["video"]))
      audioStream = newAudioStream(cdnUrl, title, selectBestAudioStream(cdnResponse["audio"]))

    reportStreamInfo(videoStream)
    if not grabMulti(videoStream.urlSegments, forceFilename=videoStream.filename,
                     saveLocation=getCurrentDir(), forceDl=true).is2xx:
      echo "<failed to download video stream>"
    elif audioStream.exists:
      reportStreamInfo(audioStream)
      if not grabMulti(audioStream.urlSegments, forceFilename=audioStream.filename,
                       saveLocation=getCurrentDir(), forceDl=true).is2xx:
        echo "<failed to download audio stream>"
      else:
        joinStreams(videoStream.filename, audioStream.filename, safeTitle)
    else:
      moveFile(joinPath(getCurrentDir(), videoStream.filename), finalPath.changeFileExt(videoStream.ext))
      echo "[complete] ", addFileExt(safeTitle, videoStream.ext)
