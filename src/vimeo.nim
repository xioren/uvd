import std/[json, uri, parseutils, sequtils]

import utils


# NOTE: s=788550b1a916f3211f77d5261169782a1c4b5a46_1620593836
# sha1hash_timestamp
# timestamp == unix time
# can use toUnix(getTime()) or epochTime().int
# timestamp most likely used in hash as salt
# QUESTIONS: SAPISIDHASH?

type
  Stream = object
    title: string
    filename: string
    id: string
    mime: string
    ext: string
    size: string
    quality: string
    bitrate: string
    initUrl: string
    baseUrl: string
    urlSegments: seq[string]
    exists: bool

const
  apiUrl = "https://api.vimeo.com"
  configUrl = "https://player.vimeo.com/video/$1/config"
  # detailsUrl = "http://vimeo.com/api/v2/video/$1.json"
  authorizationUrl = "https://vimeo.com/_rv/viewer"
  profileUrl = "https://api.vimeo.com/users/$1/profile_sections?fields=uri%2Ctitle%2CuserUri%2Curi%2C"
  videosUrl = "https://api.vimeo.com/users/$1/profile_sections/$2/videos?fields=video_details%2Cprofile_section_uri%2Ccolumn_width%2Cclip.uri%2Cclip.name%2Cclip.type%2Cclip.categories.name%2Cclip.categories.uri%2Cclip.config_url%2Cclip.pictures%2Cclip.height%2Cclip.width%2Cclip.duration%2Cclip.description%2Cclip.created_time%2C&page=1&per_page=10"
  bypassUrl = "https://player.vimeo.com/video/$1?app_id=122963&referrer=https%3A%2F%2Fwww.patreon.com%2F"

var
  includeAudio, includeVideo: bool
  audioFormat: string
  showStreams: bool


########################################################
# authentication
########################################################


proc authorize() =
  var
    authResponse: JsonNode
    response: string
    code: HttpCode
  (code, response) = doGet(authorizationUrl)
  if code.is2xx:
    authResponse = parseJson(response)
    headers.add(("authorization", "jwt " & authResponse["jwt"].getStr()))
  else:
    echo "<authorization failed>"


########################################################
# stream logic
########################################################


proc isVerticle(stream: JsonNode): bool =
  # NOTE: streams are always w x h
  stream["height"].getInt() > stream["width"].getInt()


proc selectVideoStream(streams: JsonNode, id: string): JsonNode =
  if id == "0":
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
  else:
    for stream in streams:
      if stream["id"].getStr() == id:
        result = stream
        break


proc selectAudioStream(streams: JsonNode, id: string): JsonNode =
  if streams.kind == JNull:
    result = streams
  elif id == "0":
    var largest = 0
    for stream in streams:
      if stream["bitrate"].getInt() > largest:
        largest = stream["bitrate"].getInt()
        result = stream
  else:
    for stream in streams:
      if stream["id"].getStr() == id:
        result = stream
        break


proc getVideoStreamInfo(stream: JsonNode): tuple[id, mime, ext, size, qlt, bitrate: string] =
  result.id = stream["id"].getStr()
  result.mime = stream["mime_type"].getStr()
  result.ext = extensions[result.mime]
  if isVerticle(stream):
    result.qlt = $stream["width"].getInt() & 'p'
  else:
    result.qlt = $stream["height"].getInt() & 'p'
  var size = 0
  for segment in stream["segments"]:
    size.inc(segment["size"].getInt())
  result.size = formatSize(size, includeSpace=true)
  result.bitrate = formatSize(stream["avg_bitrate"].getInt(), includeSpace=true) & "/s"


proc getAudioStreamInfo(stream: JsonNode): tuple[id, mime, ext, size, qlt, bitrate: string] =
  result.id = stream["id"].getStr()
  result.mime = stream["mime_type"].getStr()
  result.ext = extensions[result.mime]
  result.qlt = formatSize(stream["avg_bitrate"].getInt(), includeSpace=true) & "/s"
  var size = 0
  for segment in stream["segments"]:
    size.inc(segment["size"].getInt())
  result.size = formatSize(size, includeSpace=true)
  result.bitrate = formatSize(stream["avg_bitrate"].getInt(), includeSpace=true) & "/s"


proc produceUrlSegments(cdnUrl, baseUrl, initUrl: string, stream: JsonNode, audio: bool): seq[string] =
  let cdn = parseUri(cdnUrl)
  if audio:
    if baseUrl.contains("parcel"):
      result.add($(cdn / baseUrl) & initUrl)
    else:
      result.add($(cdn / "sep" / baseUrl) & initUrl)
      for segment in stream["segments"]:
          result.add($(cdn / "sep" / baseUrl) & segment["url"].getStr())
  else:
    if baseUrl.contains("parcel"):
      result.add($(cdn / baseUrl) & initUrl)
    else:
      result.add($(cdn / "sep/video" / baseUrl) & initUrl)
      for segment in stream["segments"]:
        result.add($(cdn / "sep/video" / baseUrl) & segment["url"].getStr())


proc newVideoStream(cdnUrl, title: string, stream: JsonNode): Stream =
  result.title = title
  (result.id, result.mime, result.ext, result.size, result.quality, result.bitrate) = getVideoStreamInfo(stream)
  result.filename = addFileExt("videostream", result.ext)
  result.baseUrl = stream["base_url"].getStr().replace("../")
  result.initUrl = stream["init_segment"].getStr()
  result.urlSegments = produceUrlSegments(cdnUrl.split("sep/")[0], result.baseUrl,
                                          result.initUrl, stream, false)
  result.exists = true


proc newAudioStream(cdnUrl, title: string, stream: JsonNode): Stream =
  if stream.kind != JNull:
    result.title = title
    (result.id, result.mime, result.ext, result.size, result.quality, result.bitrate) = getAudioStreamInfo(stream)
    result.filename = addFileExt("audiostream", result.ext)
    result.baseUrl = stream["base_url"].getStr().replace("../")
    result.initUrl = stream["init_segment"].getStr()
    result.urlSegments = produceUrlSegments(cdnUrl.split("sep/")[0], result.baseUrl,
                                            result.initUrl, stream, true)
    result.exists = true


proc reportStreamInfo(stream: Stream) =
  echo "title: ", stream.title, '\n',
       "stream: ", stream.filename, '\n',
       "id: ", stream.id, '\n',
       "size: ", stream.size
  if not stream.quality.isEmptyOrWhitespace():
    echo "quality: ", stream.quality
  echo "mime: ", stream.mime, '\n',
       "segments: ", stream.urlSegments.len


proc reportStreams(cdnResponse: JsonNode) =
  # TODO: sort streams by quality
  var mime, ext, size, quality, dimensions, bitrate: string
  for item in cdnResponse["video"]:
    dimensions = $item["width"].getInt() & "x" & $item["height"].getInt()
    (mime, ext, size, quality, bitrate) = getVideoStreamInfo(item)
    echo "[video]", " id: ", item["id"].getStr(), " quality: ", quality,
         " resolution: ", dimensions, " bitrate: ", bitrate, " mime: ", mime, " size: ", size
  for item in cdnResponse["audio"]:
    (mime, ext, size, quality, bitrate) = getAudioStreamInfo(item)
    echo "[audio]", " id: ", item["id"].getStr(), " bitrate: ", bitrate,
         " mime: ", mime, " size: ", size


proc getProfileIds(vimeoUrl: string): tuple[profileId, sectionId: string] =
  var
    profileResponse: JsonNode
    response: string
    code: HttpCode
  (code, response) = doGet(vimeoUrl)
  if code.is2xx:
    profileResponse = parseJson(response)
    let parts = profileResponse["data"][0]["uri"].getStr().split('/')
    result = (parts[2], parts[^1])
  else:
    echo "<failed to obtain profile metadata>"


proc extractId(vimeoUrl: string): string =
  if vimeoUrl.contains("/video/"):
    result = vimeoUrl.captureBetween('/', '?', vimeoUrl.find("video/"))
  else:
    result = vimeoUrl.captureBetween('/', '?', vimeoUrl.find(".com/"))


########################################################
# main
########################################################


proc getVideo(vimeoUrl: string, aId="0", vId="0") =
  var
    configResponse: JsonNode
    id, response: string
    code: HttpCode
    audioStream, videoStream: Stream
  if vimeoUrl.contains("/config?"):
    # NOTE: config url already obtained from getProfile
    (code, response) = doGet(vimeoUrl)
  else:
    id = extractId(vimeoUrl)
    let standardVimeoUrl = "https://vimeo.com/video/" & id

    (code, response) = doGet(configUrl % id)
    if code == Http403:
      echo "[trying signed config url]"
      (code, response) = doGet(standardVimeoUrl)
      let signedConfigUrl = response.captureBetween('"', '"', response.find(""""config_url":""") + 13)

      if not signedConfigUrl.contains("vimeo"):
        echo "[trying embed url]"
        # HACK: use patreon embed url to get meta data
        headers.add(("referer", "https://cdn.embedly.com/"))
        (code, response) = doGet(bypassUrl % id)
        let embedResponse = response.captureBetween(' ', ';', response.find("""config =""") + 8)

        if embedResponse.contains("cdn_url"):
          response = embedResponse
        else:
          echo "<failed to obtain video metadata>"
          return
      else:
        (code, response) = doGet(signedConfigUrl.replace("\\"))
    elif not code.is2xx:
      echo '<', code, '>', '\n', "<failed to obtain video metadata>"
      return

  configResponse = parseJson(response)
  if not configResponse["video"].hasKey("owner"):
    echo "<video does not exist or is hidden>"
  else:
    let
      title = configResponse["video"]["title"].getStr()
      safeTitle = title.multiReplace((".", ""), ("/", "-"), (": ", " - "), (":", "-"))
      finalPath = addFileExt(joinPath(getCurrentDir(), safeTitle), ".mkv")

    if fileExists(finalPath) and not showStreams:
      echo "<file exists> ", safeTitle
    else:
      let
        defaultCdn = configResponse["request"]["files"]["dash"]["default_cdn"].getStr()
        cdnUrl = configResponse["request"]["files"]["dash"]["cdns"][defaultCdn]["url"].getStr()
      (code, response) = doGet(cdnUrl.dequery())
      let cdnResponse = parseJson(response)

      if showStreams:
        reportStreams(cdnResponse)
        return

      if includeVideo:
        videoStream = newVideoStream(cdnUrl, title, selectVideoStream(cdnResponse["video"], vId))
        reportStreamInfo(videoStream)
        if not grabMulti(videoStream.urlSegments, forceFilename=videoStream.filename,
                         saveLocation=getCurrentDir(), forceDl=true).is2xx:
          echo "<failed to download video stream>"
          includeVideo = false
      if includeAudio:
        audioStream = newAudioStream(cdnUrl, title, selectAudioStream(cdnResponse["audio"], aId))
        if audioStream.exists:
          reportStreamInfo(audioStream)
          if not grabMulti(audioStream.urlSegments, forceFilename=audioStream.filename,
                           saveLocation=getCurrentDir(), forceDl=true).is2xx:
            echo "<failed to download audio stream>"
            includeAudio = false
        else:
          includeAudio = false
      if includeAudio and includeVideo:
        joinStreams(videoStream.filename, audioStream.filename, safeTitle)
      else:
        if includeAudio and not includeVideo:
          toMp3(audioStream.filename, safeTitle, audioFormat)
        elif includeVideo:
          moveFile(joinPath(getCurrentDir(), videoStream.filename), finalPath.changeFileExt(videoStream.ext))
          echo "[complete] ", addFileExt(safeTitle, videoStream.ext)
        else:
          echo "<no streams were downloaded>"


proc getProfile(vimeoUrl: string) =
  var
    profileResponse: JsonNode
    response: string
    code: HttpCode
    userId: string
    sectionId: string
    nextUrl: string
    urls: seq[string]

  let userSlug = dequery(vimeoUrl).split('/')[^1]
  authorize()
  (userId, sectionId) = getProfileIds(profileUrl % userSlug)

  nextUrl = videosUrl % [userId, sectionId]
  echo "[collecting videos]"
  while nextUrl != apiUrl:
    (code, response) = doGet(nextUrl)
    if code.is2xx:
      profileResponse = parseJson(response)
      for video in profileResponse["data"]:
        urls.add(video["clip"]["config_url"].getStr())
      nextUrl = apiUrl & profileResponse["paging"]["next"].getStr()
    else:
      echo "<failed to obtain profile metadata>"
      return

  echo '[', urls.len, " videos queued]"
  for url in urls:
    getVideo(url)


proc vimeoDownload*(vimeoUrl: string, audio, video, streams: bool, format, aId, vId: string) =
  includeAudio = audio
  includeVideo = video
  audioFormat = format
  showStreams = streams

  if extractId(vimeoUrl).all(isDigit):
    getVideo(vimeoUrl, aId, vId)
  else:
    getProfile(vimeoUrl)
