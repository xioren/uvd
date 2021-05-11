import std/[json, uri, parseutils]

import utils


# NOTE: s=788550b1a916f3211f77d5261169782a1c4b5a46_1620593836
# sha1hash_timestamp
# timestamp == epochTime
# timestamp most likely used in hash as salt


type
  Stream = object
    name: string
    mime: string
    ext: string
    size: string
    quality: string
    initUrl: string
    baseUrl: string
    urlSegments: seq[string]

  VimeoUri* = object
    url*: string


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
  result.add($(parseUri(cdnUrl) / baseUrl / initUrl))
  for segment in stream["segments"]:
    result.add($(parseUri(cdnUrl) / baseUrl / segment["url"].getStr()))


proc newVideoStream(cdnUrl: string, stream: JsonNode): Stream =
  (result.mime, result.ext, result.size, result.quality) = getVideoStreamInfo(stream)
  result.name = addFileExt("videostream", result.ext)
  result.baseUrl = stream["base_url"].getStr()
  result.initUrl = stream["init_segment"].getStr()
  result.urlSegments = produceUrlSegments(cdnUrl.split("sep/")[0] & "sep/video",
                                          result.baseUrl, result.initUrl, stream)


proc newAudioStream(cdnUrl: string, stream: JsonNode): Stream =
  (result.mime, result.ext, result.size, result.quality) = getAudioStreamInfo(stream)
  result.name = addFileExt("audiostream", result.ext)
  result.baseUrl = stream["base_url"].getStr().strip(leading=true, chars={'.'})
  result.initUrl = stream["init_segment"].getStr()
  result.urlSegments = produceUrlSegments(cdnUrl.split("sep/")[0] & "sep/",
                                          result.baseUrl, result.initUrl, stream)


proc reportStreamInfo(stream: Stream) =
  echo "stream: ", stream.name, '\n',
       "size: ", stream.size, '\n',
       "quality: ", stream.quality, '\n',
       "mime: ", stream.mime


proc main*(vimeoUrl: VimeoUri) =
  let
    id = vimeoUrl.url.captureBetween('/', '?', vimeoUrl.url.find(".com/"))
  var configResponse: JsonNode
  try:
    configResponse = parseJson(get(configUrl % id))
  except JsonParsingError:
    # FIXME: this assumes all json errors are because of restricted video
    echo "[trying signed config url]"
    let
      webpage = get(vimeoUrl.url)
      signedConfigUrl = webpage.captureBetween('"', '"', webpage.find(""""config_url":""") + 13)
    configResponse = parseJson(get(signedConfigUrl.replace("\\")))
  let
    title = configResponse["video"]["title"].getStr()
    safeTitle = title.multiReplace((".", ""), ("/", ""))
    finalPath = addFileExt(joinPath(getCurrentDir(), safeTitle), ".mkv")

  if fileExists(finalPath):
    echo "<file exists> ", safeTitle
  else:
    let
      defaultCDN = configResponse["request"]["files"]["dash"]["default_cdn"].getStr()
      cdnUrl = configResponse["request"]["files"]["dash"]["cdns"][defaultCDN]["url"].getStr()
      cdnResponse = parseJson(get(dequery(cdnUrl)))
      videoStream = newVideoStream(cdnUrl, selectBestVideoStream(cdnResponse["video"]))
    var audioStream: Stream
    if $cdnResponse["audio"] != "null":
      audioStream = newAudioStream(cdnUrl, selectBestAudioStream(cdnResponse["audio"]))

    echo "title: ", title
    reportStreamInfo(videoStream)
    if grabMulti(videoStream.urlSegments, forceFilename=videoStream.name,
                 saveLocation=getCurrentDir()) != "200 OK":
      echo "<failed to download video stream>"
    elif audioStream.name != "":
      reportStreamInfo(audioStream)
      if grabMulti(audioStream.urlSegments, forceFilename=audioStream.name,
                   saveLocation=getCurrentDir()) != "200 OK":
        echo "<failed to download audio stream>"
      else:
        joinStreams(videoStream.name, audioStream.name, safeTitle)
    else:
      moveFile(joinPath(getCurrentDir(), videoStream.name), finalPath.changeFileExt(videoStream.ext))
