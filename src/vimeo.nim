import std/[json, uri, parseutils, sequtils]

import utils


#[ NOTE: s=788550b1a916f3211f77d5261169782a1c4b5a46_1620593836
  sha1hash_timestamp
  timestamp == unix time
  can use toUnix(getTime()) or epochTime().int
  timestamp most likely used in hash as salt ]#
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
    thumbnail: string
    audioStream: Stream
    videoStream: Stream

const
  baseUrl = "https://vimeo.com"
  apiUrl = "https://api.vimeo.com"
  configUrl = "https://player.vimeo.com/video/$1/config"
  unlistedConfigUrl = "https://player.vimeo.com/video/$1/config?h=$2"
  # detailsUrl = "http://vimeo.com/api/v2/video/$1.json"
  authorizationUrl = "https://vimeo.com/_rv/viewer"
  profileUrl = "https://api.vimeo.com/users/$1/profile_sections?fields=uri%2Ctitle%2CuserUri%2Curi%2C"
  videosUrl = "https://api.vimeo.com/users/$1/profile_sections/$2/videos?fields=video_details%2Cprofile_section_uri%2Ccolumn_width%2Cclip.uri%2Cclip.name%2Cclip.type%2Cclip.categories.name%2Cclip.categories.uri%2Cclip.config_url%2Cclip.pictures%2Cclip.height%2Cclip.width%2Cclip.duration%2Cclip.description%2Cclip.created_time%2C&page=1&per_page=10"
  bypassUrl = "https://player.vimeo.com/video/$1?app_id=122963&referrer=https%3A%2F%2Fwww.patreon.com%2F"

var
  debug: bool
  includeAudio, includeVideo, includeThumb, includeCaptions: bool
  audioFormat: string
  desiredLanguage: string
  showStreams: bool


########################################################
# authentication
########################################################


proc authorize() =
  let (code, response) = doGet(authorizationUrl)
  if code.is2xx:
    let authResponse = parseJson(response)
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
      thisDimension, maxDimension: int
      dimension: string

    if isVerticle(streams[0]):
      dimension = "width"
    else:
      dimension = "height"

    for stream in streams:
      thisDimension = stream[dimension].getInt()
      if thisDimension > maxDimension:
        maxDimension = thisDimension
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
    var thisBitrate, maxBitrate: int
    for stream in streams:
      thisBitrate = stream["bitrate"].getInt()
      if thisBitrate > maxBitrate:
        maxBitrate = thisBitrate
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


proc produceUrlSegments(cdnUrl, baseUrl, initUrl, streamId: string, stream: JsonNode, audio: bool): seq[string] =
  let cdn = parseUri(cdnUrl)
  var sep: string

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
      if baseUrl.contains(streamId):
        sep = "sep/video"
      else:
        # NOTE: some (older?) streams do not already contain the streamId and it needs to be added
        sep = "sep/video/" & streamId

      result.add($(cdn / sep / baseUrl) & initUrl)
      for segment in stream["segments"]:
        result.add($(cdn / sep / baseUrl) & segment["url"].getStr())


proc newVideoStream(cdnUrl, videoId: string, stream: JsonNode): Stream =
  if stream.kind != JNull:
    # NOTE: should NEVER be JNull but go through the motions anyway for parity with newAudioStream
    (result.id, result.mime, result.ext, result.size, result.quality, result.bitrate) = getVideoStreamInfo(stream)
    result.filename = addFileExt(videoId, result.ext)
    result.baseUrl = stream["base_url"].getStr().replace("../")
    result.initUrl = stream["init_segment"].getStr()
    result.urlSegments = produceUrlSegments(cdnUrl.split("sep/")[0], result.baseUrl,
                                            result.initUrl, stream["id"].getStr(), stream, false)
    result.exists = true


proc newAudioStream(cdnUrl, videoId: string, stream: JsonNode): Stream =
  if stream.kind != JNull:
    (result.id, result.mime, result.ext, result.size, result.quality, result.bitrate) = getAudioStreamInfo(stream)
    result.filename = addFileExt(videoId, result.ext)
    result.baseUrl = stream["base_url"].getStr().replace("../")
    result.initUrl = stream["init_segment"].getStr()
    result.urlSegments = produceUrlSegments(cdnUrl.split("sep/")[0], result.baseUrl,
                                            result.initUrl, stream["id"].getStr(), stream, true)
    result.exists = true


proc newVideo(vimeoUrl, cdnUrl, thumbnailUrl, title, videoId: string, cdnResponse: JsonNode, aId, vId: string): Video =
  result.title = title
  result.url = vimeoUrl
  result.videoId = videoId
  result.thumbnail = thumbnailUrl
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
    result = vimeoUrl.captureBetween('/', start=vimeoUrl.find(".com/"))


proc extractHash(vimeoUrl: string): string =
  result = vimeoUrl.dequery().split('/')[^1]


proc isUnlisted(vimeoUrl: string): bool =
  ## check for unlisted hash in vimeo url
  let slug = vimeoUrl.captureBetween('/', '?', vimeoUrl.find(".com/"))
  if slug.count('/') > 0:
    result = true


########################################################
# main
########################################################


proc getVideo(vimeoUrl: string, aId="0", vId="0") =
  var
    configResponse: JsonNode
    response: string
    code: HttpCode
    subtitles: string
  let videoId = extractId(vimeoUrl)
  var standardVimeoUrl = baseUrl & '/' & videoId

  if debug:
    echo "[debug] video id: ", videoId

  if vimeoUrl.contains("/config?"):
    # NOTE: config url already obtained from getProfile
    (code, response) = doGet(vimeoUrl)
  else:
    if isUnlisted(vimeoUrl):
      let unlistedHash = extractHash(vimeoUrl)
      if debug:
        echo "[debug] unlisted hash: ", unlistedHash
      standardVimeoUrl = standardVimeoUrl & '/' & unlistedHash
      (code, response) = doGet(unlistedConfigUrl % [videoId, unlistedHash])
    else:
      (code, response) = doGet(configUrl % videoId)
    if code == Http403:
      # NOTE: videos where this step was previously necessary now seem to work without it.
      # QUESTION: can it be removed?
      echo "[trying signed config url]"
      (code, response) = doGet(standardVimeoUrl)
      let signedConfigUrl = response.captureBetween('"', '"', response.find(""""config_url":""") + 13)

      if not signedConfigUrl.contains("vimeo"):
        echo "[trying embed url]"
        # HACK: use patreon embed url to get meta data
        # QUESTION: is there a seperate bypass url for unlisted videos?
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
      thumbnailUrl = configResponse["video"]["thumbs"]["base"].getStr()

    if fileExists(fullFilename) and not showStreams:
      echo "<file exists> ", safeTitle
    else:
      let
        defaultCDN = configResponse["request"]["files"]["dash"]["default_cdn"].getStr()
        cdnUrl = configResponse["request"]["files"]["dash"]["cdns"][defaultCDN]["url"].getStr()

      if debug:
        echo "[debug] default CDN: ", defaultCDN
        echo "[debug] CDN url: ", cdnUrl
      (code, response) = doGet(cdnUrl.dequery())
      let cdnResponse = parseJson(response)

      if showStreams:
        reportStreams(cdnResponse)
        return

      let video = newVideo(standardVimeoUrl, cdnUrl, thumbnailUrl, title, videoId, cdnResponse, aId, vId)
      echo "title: ", video.title

      if includeThumb:
        if not grab(video.thumbnail, extractFilename(video.thumbnail).addFileExt("jpeg"), forceDl=true).is2xx:
          echo "<failed to download thumbnail>"

      if includeVideo:
        reportStreamInfo(video.videoStream)
        if not grab(video.videoStream.urlSegments, video.videoStream.filename,
                    forceDl=true).is2xx:
          echo "<failed to download video stream>"
          includeVideo = false

      if includeAudio and video.audioStream.exists:
        reportStreamInfo(video.audioStream)
        if not grab(video.audioStream.urlSegments, video.audioStream.filename,
                    forceDl=true).is2xx:
          echo "<failed to download audio stream>"
          includeAudio = false
      else:
        includeAudio = false

      if includeAudio and includeVideo:
        joinStreams(video.videoStream.filename, video.audioStream.filename, fullFilename, desiredLanguage, includeCaptions)
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
    nextUrl: string
    urls: seq[string]

  let userSlug = dequery(vimeoUrl).split('/')[^1]
  authorize()
  let (userId, sectionId) = getProfileIds(profileUrl % userSlug)
  nextUrl = videosUrl % [userId, sectionId]

  if debug:
    echo "[debug] slug: ", userSlug, " user id: ", userId, " sectionId: ", sectionId

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


proc vimeoDownload*(vimeoUrl, format, aId, vId: string,
                    iAudio, iVideo, iThumb, iCaptions, streams, debugMode: bool) =
  includeAudio = iAudio
  includeVideo = iVideo
  includeThumb = iThumb
  includeCaptions = iCaptions
  audioFormat = format
  showStreams = streams
  debug = debugMode

  if extractId(vimeoUrl).all(isDigit):
    getVideo(vimeoUrl, aId, vId)
  else:
    getProfile(vimeoUrl)
