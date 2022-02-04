import std/[json, uri, parseutils, sequtils]

import utils


#[ NOTE: s=788550b1a916f3211f77d5261169782a1c4b5a46_1620593836
  sha1hash_timestamp
  timestamp == unix time
  can use toUnix(getTime()) or epochTime().int
  timestamp most likely used in hash as salt ]#
# QUESTIONS: SAPISIDHASH?

#[ NOTE: profiles:
    172 = 2160p
    170 = 1440p
    175 = 1080p
    119 = 1080p
    174 = 720p
    113 = 720p
    165 = 540p
    164 = 360p
    112 = 360p
    116 = 240p
]#


type
  Stream = object
    id: string
    mime: string
    ext: string
    codec: string
    size: string
    quality: string
    resolution: string
    fps: string
    bitrate: string
    format: string
    urlSegments: seq[string]
    filename: string
    exists: bool

  Video = object
    title: string
    videoId: string
    url: string
    thumbnailUrl: string
    audioStream: Stream
    videoStream: Stream

const
  baseUrl = "https://vimeo.com"
  apiUrl = "https://api.vimeo.com"
  configUrl = "https://player.vimeo.com/video/$1/config"
  unlistedConfigUrl = "https://player.vimeo.com/video/$1/config?h=$2"
  # detailsUrl = "https://vimeo.com/api/v2/video/$1.json"
  authorizationUrl = "https://vimeo.com/_rv/viewer"
  profileUrl = "https://api.vimeo.com/users/$1/profile_sections?fields=uri%2Ctitle%2CuserUri%2Curi%2C"
  videosUrl = "https://api.vimeo.com/users/$1/profile_sections/$2/videos?fields=video_details%2Cprofile_section_uri%2Ccolumn_width%2Cclip.uri%2Cclip.name%2Cclip.type%2Cclip.categories.name%2Cclip.categories.uri%2Cclip.config_url%2Cclip.pictures%2Cclip.height%2Cclip.width%2Cclip.duration%2Cclip.description%2Cclip.created_time%2C&page=1&per_page=10"
  bypassUrl = "https://player.vimeo.com/video/$1?app_id=122963&referrer=https%3A%2F%2Fwww.patreon.com%2F"

var
  includeAudio, includeVideo, includeThumb, includeSubtitles: bool
  audioFormat: string
  subtitlesLanguage: string
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
    logError("authorization failed")


########################################################
# subtitles
########################################################
# NOTE: example video https://vimeo.com/358296408

proc generateSubtitles(captions: JsonNode) =
  var textTrack = newJNull()

  if subtitlesLanguage != "":
    # NOTE: check if desired language exists
    for track in captions:
      if track["lang"].getStr() == subtitlesLanguage:
        textTrack = track
        break
    if textTrack.kind == JNull:
      logError("subtitles not available in desired language")
  else:
    # NOTE: select default track
    textTrack = captions[0]
    subtitlesLanguage = textTrack["lang"].getStr()

  if textTrack.kind != JNull:
    let textTrackUrl = baseUrl & textTrack["url"].getStr()

    let (code, response) = doGet(textTrackUrl)
    if code.is2xx:
      includeSubtitles = response.save(addFileExt(subtitlesLanguage, "srt"))
    else:
      logError("failed to download subtitles")
  else:
    includeSubtitles = false
    logError("failed to obtain subtitles")


########################################################
# stream logic
########################################################


proc isVerticle(stream: JsonNode): bool =
  # NOTE: streams are always w x h
  stream["height"].getInt() > stream["width"].getInt()


proc getBitrate(stream: JsonNode): int =
  ## extract bitrate value from json. prefers average bitrate.
  if stream.kind == JNull:
    result = 0
  elif stream.hasKey("avg_bitrate"):
    result = stream["avg_bitrate"].getInt()
  else:
    result = stream["bitrate"].getInt()


proc selectVideoByBitrate(streams: JsonNode, codec: string): JsonNode =
  ## select $codec video stream with highest bitrate (and resolution)
  var
    thisBitrate, maxBitrate, idx, thisSemiperimeter, maxSemiperimeter: int
    select = -1
  result = newJNull()

  for stream in streams:
    if stream["codecs"].getStr().contains(codec):
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
    if stream["codecs"].getStr().contains(codec):
      thisBitrate = getBitrate(stream)
      if thisBitrate > maxBitrate:
        maxBitrate = thisBitrate
        select = idx
    inc idx

  if select > -1:
    result = streams[select]


proc selectVideoStream(streams: JsonNode, id, codec: string): JsonNode =
  ## select video by id or resolution
  if id != "0":
    # NOTE: select by user itag choice
    for stream in streams:
      if stream["id"].getStr() == id:
        result = stream
        break
  elif codec != "":
    # NOTE: select by user codec preference
    result = selectVideoByBitrate(streams, codec)
  else:
    # NOTE: fallback selection
    result = selectVideoByBitrate(streams, "avc1")


proc selectAudioStream(streams: JsonNode, id, codec: string): JsonNode =
  ## select video by id or bitrate
  if streams.kind == JNull:
    result = streams
  elif id != "0":
    # NOTE: select by user itag choice
    for stream in streams:
      if stream["id"].getStr() == id:
        result = stream
        break
  elif codec != "":
    # NOTE: select by user codec preference
    result = selectAudioByBitrate(streams, codec)
  else:
    # NOTE: fallback selection
    result = selectAudioByBitrate(streams, "mp4a")


proc produceUrlSegments(stream: JsonNode, cdnUrl: string): seq[string] =
  ## produce dash segments
  let
    baseUrl = stream["base_url"].getStr().replace("../")
    initSegment = stream["init_segment"].getStr()
    streamId = stream["id"].getStr()
    cdnUri = parseUri(cdnUrl)
  var sep: string

  if baseUrl.contains("audio"):
    sep = "sep"
  else:
    sep = "sep/video"
  if not baseUrl.contains(streamId):
    # NOTE: some (older?) streams do not already contain the streamId and it needs to be added
    sep.add("/" & streamId)

  if baseUrl.contains("parcel"):
    # NOTE: dash
    #[ NOTE: this completes with only init url even though there are index url and segment urls as well.
      this may be a server side bug as the init is requested with a content range query string which
      doesn't seem to be honored ]#
    result.add($(cdnUri / baseUrl / initSegment))
  else:
    # NOTE: mp42
    result.add($(cdnUri / sep / baseUrl / initSegment))
    for segment in stream["segments"]:
      result.add($(cdnUri / sep / baseUrl / segment["url"].getStr()))


proc getVideoStreamInfo(stream: JsonNode): tuple[id, mime, codec, ext, size, qlt, resolution, fps, bitrate, format: string] =
  ## compile all relevent video stream metadata
  result.id = stream["id"].getStr()
  result.mime = stream["mime_type"].getStr()
  result.codec = stream["codecs"].getStr()
  result.ext = extensions[result.mime]
  result.bitrate = formatSize(stream["avg_bitrate"].getInt(), includeSpace=true) & "/s"
  result.resolution = $stream["width"].getInt() & "x" & $stream["height"].getInt()
  result.fps = ($stream["framerate"].getFloat())[0..4]
  result.format = stream["format"].getStr()

  if isVerticle(stream):
    result.qlt = $stream["width"].getInt() & 'p'
  else:
    result.qlt = $stream["height"].getInt() & 'p'

  var size: int
  for segment in stream["segments"]:
    size.inc(segment["size"].getInt())
  result.size = formatSize(size, includeSpace=true)


proc getAudioStreamInfo(stream: JsonNode): tuple[id, mime, codec, ext, size, qlt, bitrate, format: string] =
  ## compile all relevent audio stream metadata
  result.id = stream["id"].getStr()
  result.mime = stream["mime_type"].getStr()
  result.codec = stream["codecs"].getStr()
  result.ext = extensions[result.mime]
  result.qlt = formatSize(stream["avg_bitrate"].getInt(), includeSpace=true) & "/s"
  result.bitrate = formatSize(stream["avg_bitrate"].getInt(), includeSpace=true) & "/s"
  result.format = stream["format"].getStr()

  var size: int
  for segment in stream["segments"]:
    size.inc(segment["size"].getInt())
  result.size = formatSize(size, includeSpace=true)


proc newVideoStream(cdnUrl, videoId: string, stream: JsonNode): Stream =
  if stream.kind != JNull:
    # NOTE: should NEVER be JNull but go through the motions anyway for parity with newAudioStream
    (result.id, result.mime, result.codec, result.ext, result.size, result.quality, result.resolution, result.fps, result.bitrate, result.format) = getVideoStreamInfo(stream)
    result.filename = addFileExt(videoId, result.ext)
    result.urlSegments = stream.produceUrlSegments(cdnUrl.split("sep/")[0])
    result.exists = true


proc newAudioStream(cdnUrl, videoId: string, stream: JsonNode): Stream =
  if stream.kind != JNull:
    (result.id, result.mime, result.codec, result.ext, result.size, result.quality, result.bitrate, result.format) = getAudioStreamInfo(stream)
    result.filename = addFileExt(videoId, result.ext)
    result.urlSegments = stream.produceUrlSegments(cdnUrl.split("sep/")[0])
    result.exists = true


proc newVideo(vimeoUrl, cdnUrl, thumbnailUrl, title, videoId: string, cdnResponse: JsonNode, aId, vId, aCodec, vCodec: string): Video =
  result.title = title
  result.url = vimeoUrl
  result.videoId = videoId
  result.thumbnailUrl = thumbnailUrl
  result.videoStream = newVideoStream(cdnUrl, videoId, selectVideoStream(cdnResponse["video"], vId, vCodec))
  result.audioStream = newAudioStream(cdnUrl, videoId, selectAudioStream(cdnResponse["audio"], aId, aCodec))


proc reportStreamInfo(stream: Stream) =
  ## echo metadata for single stream
  logInfo("stream: ", stream.filename)
  logInfo("id: ", stream.id)
  logInfo("size: ", stream.size)
  if not (stream.quality == ""):
    logInfo("quality: ", stream.quality)
  logInfo("mime: ", stream.mime)
  logInfo("codec: ", stream.codec)
  logInfo("segments: ", stream.urlSegments.len)


proc reportStreams(cdnResponse: JsonNode) =
  ## echo metadata for all streams
  var id, mime, codec, ext, size, quality, resolution, fps, bitrate, format: string

  for item in cdnResponse["video"]:
    (id, mime, codec, ext, size, quality, resolution, fps, bitrate, format) = getVideoStreamInfo(item)
    echo "[video]", " id: ", id,
         " quality: ", quality,
         " resolution: ", resolution,
         " fps: ", fps,
         " bitrate: ", bitrate,
         " mime: ", mime,
         " codec: ", codec,
         " size: ", size,
         " format: ", format

  if cdnResponse["audio"].kind != JNull:
    for item in cdnResponse["audio"]:
      (id, mime, codec, ext, size, quality, bitrate, format) = getAudioStreamInfo(item)
      echo "[audio]", " id: ", id,
           " bitrate: ", bitrate,
           " mime: ", mime,
           " codec: ", codec,
           " size: ", size,
           " format: ", format


proc getProfileIds(vimeoUrl: string): tuple[profileId, sectionId: string] =
  ## obtain userId and sectionId from profiles
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
    logError("failed to obtain profile metadata")


proc extractId(vimeoUrl: string): string =
  ## extract video/profile id from url
  if vimeoUrl.contains("/config"):
    result = vimeoUrl.captureBetween('/', '/', vimeoUrl.find("video/"))
  elif vimeoUrl.contains("/video/"):
    result = vimeoUrl.captureBetween('/', '?', vimeoUrl.find("video/"))
  else:
    result = vimeoUrl.captureBetween('/', '?', start=vimeoUrl.find(".com/"))


proc extractHash(vimeoUrl: string): string =
  ## extract unlinsted hash from url
  result = vimeoUrl.dequery().split('/')[^1]


proc isUnlisted(vimeoUrl: string): bool =
  ## check for unlisted hash in vimeo url
  var slug: string
  if vimeoUrl.contains("/video/"):
    slug = vimeoUrl.captureBetween('/', '?', vimeoUrl.find("video/"))
  else:
    slug = vimeoUrl.captureBetween('/', '?', vimeoUrl.find(".com/"))
  if slug.count('/') > 0:
    result = true


proc getBestThumb(thumbs: JsonNode): string =
  # QUESTION: are there other resolutions?
  if thumbs.hasKey("base"):
    result = thumbs["base"].getStr()
  elif thumbs.hasKey("1280"):
    result = thumbs["1280"].getStr()
  elif thumbs.hasKey("960"):
    result = thumbs["960"].getStr()
  elif thumbs.hasKey("640"):
    result = thumbs["640"].getStr()


########################################################
# main
########################################################


proc getVideo(vimeoUrl: string, aId, vId, aCodec, vCodec: string) =
  var
    configResponse: JsonNode
    response: string
    code: HttpCode
    thumbnailUrl: string
  let videoId = extractId(vimeoUrl)
  var standardVimeoUrl = baseUrl & '/' & videoId

  logInfo("id: ", videoId)

  if vimeoUrl.contains("/config?"):
    # NOTE: config url already obtained (calls from getProfile)
    (code, response) = doGet(vimeoUrl)
  else:
    if isUnlisted(vimeoUrl):
      let unlistedHash = extractHash(vimeoUrl)
      logDebug("unlisted hash: ", unlistedHash)
      standardVimeoUrl = standardVimeoUrl & '/' & unlistedHash
      (code, response) = doGet(unlistedConfigUrl % [videoId, unlistedHash])
    else:
      (code, response) = doGet(configUrl % videoId)
    if code == Http403:
      # NOTE: videos where this step was previously necessary now seem to work without it.
      # QUESTION: can it be removed?
      logNotice("trying signed config url")
      (code, response) = doGet(standardVimeoUrl)
      let signedConfigUrl = response.captureBetween('"', '"', response.find(""""config_url":""") + 13)

      if not signedConfigUrl.contains("vimeo"):
        logNotice("trying embed url")
        # HACK: use patreon embed url to get meta data
        # QUESTION: is there a seperate bypass url for unlisted videos?
        headers.add(("referer", "https://cdn.embedly.com/"))
        (code, response) = doGet(bypassUrl % videoId)
        let embedResponse = response.captureBetween(' ', ';', response.find("""config =""") + 8)

        if embedResponse.contains("cdn_url"):
          response = embedResponse
        else:
          logError("failed to obtain video metadata")
          return
      else:
        (code, response) = doGet(signedConfigUrl.replace("\\"))
    elif not code.is2xx:
      configResponse = parseJson(response)
      logError(configResponse["message"].getStr().strip(chars={'"'}))
      logError("failed to obtain video metadata")
      return

  configResponse = parseJson(response)
  if not configResponse["video"].hasKey("owner"):
    logError("video does not exist or is hidden")
  else:
    let
      title = configResponse["video"]["title"].getStr()
      safeTitle = makeSafe(title)
      fullFilename = addFileExt(safeTitle & " [" & videoId & ']', ".mkv")
      thumbnailUrl = getBestThumb(configResponse["video"]["thumbs"])

    if fileExists(fullFilename) and not showStreams:
      logError("file exists: ", safeTitle)
    else:
      let
        defaultCDN = configResponse["request"]["files"]["dash"]["default_cdn"].getStr()
        cdnUrl = configResponse["request"]["files"]["dash"]["cdns"][defaultCDN]["url"].getStr()

      logDebug("default CDN: ", defaultCDN)
      logDebug("CDN url: ", cdnUrl)

      (code, response) = doGet(cdnUrl.dequery())
      let cdnResponse = parseJson(response)

      if showStreams:
        reportStreams(cdnResponse)
        return

      let video = newVideo(standardVimeoUrl, cdnUrl, thumbnailUrl, title, videoId, cdnResponse, aId, vId, aCodec, vCodec)
      logInfo("title: ", video.title)

      if includeThumb and thumbnailUrl != "":
        if not grab(video.thumbnailUrl, fullFilename.changeFileExt("jpeg"), forceDl=true).is2xx:
          logError("failed to download thumbnail")

      if includeSubtitles:
        if configResponse["request"].hasKey("text_tracks"):
          generateSubtitles(configResponse["request"]["text_tracks"])
        else:
          includeSubtitles = false
          logError("video does not contain subtitles")

      if includeVideo:
        reportStreamInfo(video.videoStream)
        if not grab(video.videoStream.urlSegments, video.videoStream.filename,
                    forceDl=true).is2xx:
          logError("failed to download video stream")
          includeVideo = false

      if includeAudio and video.audioStream.exists:
        reportStreamInfo(video.audioStream)
        if not grab(video.audioStream.urlSegments, video.audioStream.filename,
                    forceDl=true).is2xx:
          logError("failed to download audio stream")
          includeAudio = false
      else:
        includeAudio = false

      if includeAudio and includeVideo:
        joinStreams(video.videoStream.filename, video.audioStream.filename, fullFilename, subtitlesLanguage, includeSubtitles)
      elif includeAudio and not includeVideo:
        convertAudio(video.audioStream.filename, safeTitle & " [" & videoId & ']', audioFormat)
      elif includeVideo:
        moveFile(video.videoStream.filename, fullFilename.changeFileExt(video.videoStream.ext))
        logInfo("complete: ", addFileExt(safeTitle, video.videoStream.ext))
      else:
        logError("no streams were downloaded")


proc getProfile(vimeoUrl, aId, vId, aCodec, vCodec: string) =
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

  logDebug("slug: ", userSlug, " user id: ", userId, " sectionId: ", sectionId)

  logInfo("collecting videos")
  while nextUrl != apiUrl:
    (code, response) = doGet(nextUrl)
    if code.is2xx:
      profileResponse = parseJson(response)
      for video in profileResponse["data"]:
        urls.add(video["clip"]["config_url"].getStr())
      nextUrl = apiUrl & profileResponse["paging"]["next"].getStr()
    else:
      logError("failed to obtain profile metadata")
      return

  logInfo(urls.len, " videos queued")
  for idx, url in urls:
    logGeneric(lvlInfo, "download", idx.succ, " of ", urls.len)
    getVideo(url, aId, vId, aCodec, vCodec)


proc vimeoDownload*(vimeoUrl, aFormat, aId, vId, aCodec, vCodec, sLang: string,
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

  logGeneric(lvlInfo, "uvd", "vimeo")
  if extractId(vimeoUrl).all(isDigit):
    getVideo(vimeoUrl, aId, vId, aCodec, vCodec)
  else:
    getProfile(vimeoUrl, aId, vId, aCodec, vCodec)
