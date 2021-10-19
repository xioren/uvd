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
    id: string
    mime: string
    ext: string
    size: string
    quality: string
    bitrate: string
    initUrl: string
    baseUrl: string
    urlSegments: seq[string]
    filename: string
    exists: bool

  Video = object
    title: string
    videoId: string
    url: string
    audioStream: Stream
    videoStream: Stream

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
  result.bitrate = formatSize(stream["avg_bitrate"].getInt(), includeSpace=true) & "/s"

  if isVerticle(stream):
    result.qlt = $stream["width"].getInt() & 'p'
  else:
    result.qlt = $stream["height"].getInt() & 'p'

  var size: int
  for segment in stream["segments"]:
    size.inc(segment["size"].getInt())
  result.size = formatSize(size, includeSpace=true)


proc getAudioStreamInfo(stream: JsonNode): tuple[id, mime, ext, size, qlt, bitrate: string] =
  result.id = stream["id"].getStr()
  result.mime = stream["mime_type"].getStr()
  result.ext = extensions[result.mime]
  result.qlt = formatSize(stream["avg_bitrate"].getInt(), includeSpace=true) & "/s"
  result.bitrate = formatSize(stream["avg_bitrate"].getInt(), includeSpace=true) & "/s"

  var size: int
  for segment in stream["segments"]:
    size.inc(segment["size"].getInt())
  result.size = formatSize(size, includeSpace=true)


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


proc newVideoStream(cdnUrl, videoId: string, stream: JsonNode): Stream =
  if stream.kind != JNull:
    # NOTE: should NEVER be JNull but go through the motions anyway for parity with newAudioStream
    (result.id, result.mime, result.ext, result.size, result.quality, result.bitrate) = getVideoStreamInfo(stream)
    result.filename = addFileExt(videoId, result.ext)
    result.baseUrl = stream["base_url"].getStr().replace("../")
    result.initUrl = stream["init_segment"].getStr()
    result.urlSegments = produceUrlSegments(cdnUrl.split("sep/")[0], result.baseUrl,
                                            result.initUrl, stream, false)
    result.exists = true


proc newAudioStream(cdnUrl, videoId: string, stream: JsonNode): Stream =
  if stream.kind != JNull:
    (result.id, result.mime, result.ext, result.size, result.quality, result.bitrate) = getAudioStreamInfo(stream)
    result.filename = addFileExt(videoId, result.ext)
    result.baseUrl = stream["base_url"].getStr().replace("../")
    result.initUrl = stream["init_segment"].getStr()
    result.urlSegments = produceUrlSegments(cdnUrl.split("sep/")[0], result.baseUrl,
                                            result.initUrl, stream, true)
    result.exists = true


proc newVideo(vimeoUrl, cdnUrl, title, videoId: string, cdnResponse: JsonNode, aId, vId: string): Video =
  result.title = title
  result.url = vimeoUrl
  result.videoId = videoId
  result.videoStream = newVideoStream(cdnUrl, videoId, selectVideoStream(cdnResponse["video"], vId))
  result.audioStream = newAudioStream(cdnUrl, videoId, selectAudioStream(cdnResponse["audio"], aId))


proc reportStreamInfo(stream: Stream) =
  echo "stream: ", stream.filename, '\n',
       "id: ", stream.id, '\n',
       "size: ", stream.size
  if not stream.quality.isEmptyOrWhitespace():
    echo "quality: ", stream.quality
  echo "mime: ", stream.mime, '\n',
       "segments: ", stream.urlSegments.len


proc reportStreams(cdnResponse: JsonNode) =
  # TODO: sort streams by quality
  var id, mime, ext, size, quality, dimensions, bitrate: string

  for item in cdnResponse["video"]:
    dimensions = $item["width"].getInt() & "x" & $item["height"].getInt()
    (id, mime, ext, size, quality, bitrate) = getVideoStreamInfo(item)
    echo "[video]", " id: ", id, " quality: ", quality,
         " resolution: ", dimensions, " bitrate: ", bitrate, " mime: ", mime, " size: ", size
  if cdnResponse["audio"].kind != JNull:
    for item in cdnResponse["audio"]:
      (id, mime, ext, size, quality, bitrate) = getAudioStreamInfo(item)
      echo "[audio]", " id: ", id, " bitrate: ", bitrate,
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
  if vimeoUrl.contains("/config"):
    result = vimeoUrl.captureBetween('/', '/', vimeoUrl.find("video/"))
  elif vimeoUrl.contains("/video/"):
    result = vimeoUrl.captureBetween('/', '?', vimeoUrl.find("video/"))
  else:
    result = vimeoUrl.captureBetween('/', '?', vimeoUrl.find(".com/"))


########################################################
# main
########################################################


proc getVideo(vimeoUrl: string, aId="0", vId="0") =
  var
    configResponse: JsonNode
    response: string
    code: HttpCode
  let
    videoId = extractId(vimeoUrl)
    standardVimeoUrl = "https://vimeo.com/video/" & videoId

  if vimeoUrl.contains("/config?"):
    # NOTE: config url already obtained from getProfile
    (code, response) = doGet(vimeoUrl)
  else:
    (code, response) = doGet(configUrl % videoId)
    if code == Http403:
      echo "[trying signed config url]"
      (code, response) = doGet(standardVimeoUrl)
      let signedConfigUrl = response.captureBetween('"', '"', response.find(""""config_url":""") + 13)

      if not signedConfigUrl.contains("vimeo"):
        echo "[trying embed url]"
        # HACK: use patreon embed url to get meta data
        headers.add(("referer", "https://cdn.embedly.com/"))
        (code, response) = doGet(bypassUrl % videoId)
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
      safeTitle = makeSafe(title)
      fullFilename = addFileExt(safeTitle, ".mkv")

    if fileExists(fullFilename) and not showStreams:
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

      let video = newVideo(standardVimeoUrl, cdnUrl, title, videoId, cdnResponse, aId, vId)
      echo "title: ", video.title

      if includeVideo:
        reportStreamInfo(video.videoStream)
        if not grab(video.videoStream.urlSegments, filename=video.videoStream.filename,
                         forceDl=true).is2xx:
          echo "<failed to download video stream>"
          includeVideo = false

      if includeAudio and video.audioStream.exists:
        reportStreamInfo(video.audioStream)
        if not grab(video.audioStream.urlSegments, filename=video.audioStream.filename,
                         forceDl=true).is2xx:
          echo "<failed to download audio stream>"
          includeAudio = false
      else:
        includeAudio = false

      if includeAudio and includeVideo:
        joinStreams(video.videoStream.filename, video.audioStream.filename, fullFilename)
      elif includeAudio and not includeVideo:
        convertAudio(video.audioStream.filename, safeTitle, audioFormat)
      elif includeVideo:
        moveFile(video.videoStream.filename, fullFilename.changeFileExt(video.videoStream.ext))
        echo "[complete] ", addFileExt(safeTitle, video.videoStream.ext)
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
