import std/[json, uri, parseutils]

import utils


# NOTE: s=788550b1a916f3211f77d5261169782a1c4b5a46_1620593836
# sha1hash_timestamp
# timestamp == unix time
# can use toUnix(getTime()) or epochTime().int
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
    exists: bool

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


proc newVideoStream(cdnUrl: string, stream: JsonNode): Stream =
  (result.mime, result.ext, result.size, result.quality) = getVideoStreamInfo(stream)
  result.name = addFileExt("videostream", result.ext)
  result.baseUrl = stream["base_url"].getStr()
  result.initUrl = stream["init_segment"].getStr()
  result.urlSegments = produceUrlSegments(cdnUrl.split("sep/")[0] & "sep/video",
                                          result.baseUrl, result.initUrl, stream)
  result.exists = true


proc newAudioStream(cdnUrl: string, stream: JsonNode): Stream =
  if stream.kind != JNull:
    (result.mime, result.ext, result.size, result.quality) = getAudioStreamInfo(stream)
    result.name = addFileExt("audiostream", result.ext)
    result.baseUrl = stream["base_url"].getStr().strip(leading=true, chars={'.'})
    result.initUrl = stream["init_segment"].getStr()
    result.urlSegments = produceUrlSegments(cdnUrl.split("sep/")[0] & "sep/",
                                            result.baseUrl, result.initUrl, stream)
    result.exists = true


proc reportStreamInfo(stream: Stream) =
  echo "stream: ", stream.name, '\n',
       "size: ", stream.size, '\n',
       "quality: ", stream.quality, '\n',
       "mime: ", stream.mime


proc main*(vimeoUrl: VimeoUri) =
  let
    id = vimeoUrl.url.captureBetween('/', '?', vimeoUrl.url.find(".com/"))
  var configResponse: JsonNode
  let response = get(configUrl % id)
  if response == "403 Forbidden":
    echo "[trying signed config url]"
    let
      webpage = get(vimeoUrl.url)
      signedConfigUrl = webpage.captureBetween('"', '"', webpage.find(""""config_url":""") + 13)
    configResponse = parseJson(get(signedConfigUrl.replace("\\")))
  elif response != "200 OK":
    echo '<', response, '>'
  else:
    configResponse = parseJson(response)
    let
      title = configResponse["video"]["title"].getStr()
      safeTitle = title.multiReplace((".", ""), ("/", ""))
      finalPath = addFileExt(joinPath(getCurrentDir(), safeTitle), ".mkv")

    if fileExists(finalPath):
      echo "<file exists> ", safeTitle
    else:
      let
        defaultCdn = configResponse["request"]["files"]["dash"]["default_cdn"].getStr()
        cdnUrl = configResponse["request"]["files"]["dash"]["cdns"][defaultCdn]["url"].getStr()
        cdnResponse = parseJson(get(dequery(cdnUrl)))
        videoStream = newVideoStream(cdnUrl, selectBestVideoStream(cdnResponse["video"]))
        audioStream = newAudioStream(cdnUrl, selectBestAudioStream(cdnResponse["audio"]))

      echo "title: ", title
      reportStreamInfo(videoStream)
      if grabMulti(videoStream.urlSegments, forceFilename=videoStream.name,
                   saveLocation=getCurrentDir(), forceDl=true) != "200 OK":
        echo "<failed to download video stream>"
      elif audioStream.exists:
        reportStreamInfo(audioStream)
        if grabMulti(audioStream.urlSegments, forceFilename=audioStream.name,
                     saveLocation=getCurrentDir(), forceDl=true) != "200 OK":
          echo "<failed to download audio stream>"
        else:
          joinStreams(videoStream.name, audioStream.name, safeTitle)
      else:
        moveFile(joinPath(getCurrentDir(), videoStream.name), finalPath.changeFileExt(videoStream.ext))
