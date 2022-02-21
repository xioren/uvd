import common


#[ NOTE: s=788550b1a916f3211f77d5261169782a1c4b5a46_1620593836
  sha1hash_timestamp
  timestamp == unix time
  can use toUnix(getTime()) or epochTime().int
  timestamp most likely used in hash as salt ]#
# QUESTION: SAPISIDHASH?
# NOTE: other url containing jwt: https://api.vimeo.com/client_configs/single_video_view?clip_id=477957994&vuid=192548912.843356162&clip_hash=2282452868&fields=presence
# NOTE: some notable query string args: bypass_privacy=1, force_embed=1

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

const
  baseUrl = "https://vimeo.com"
  playerUrl = "https://player.vimeo.com"
  apiUrl = "https://api.vimeo.com"
  profileApiUrl = "https://api.vimeo.com/users/$1/profile_sections?fields=uri%2Ctitle%2CuserUri%2Curi%2C"
  videosApiUrl = "https://api.vimeo.com/users/$1/profile_sections/$2/videos?fields=video_details%2Cprofile_section_uri%2Ccolumn_width%2Cclip.uri%2Cclip.name%2Cclip.type%2Cclip.categories.name%2Cclip.categories.uri%2Cclip.config_url%2Cclip.pictures%2Cclip.height%2Cclip.width%2Cclip.duration%2Cclip.description%2Cclip.created_time%2C&page=1&per_page=10"
  videoApiUrl = "https://api.vimeo.com/videos/$1"
  videoApiUnlistedUrl = "https://api.vimeo.com/videos/$1:$2"
  genericConfigUrl = "https://player.vimeo.com/video/$1/config"
  bypassUrl = "https://player.vimeo.com/video/$1?app_id=122963&referrer=https%3A%2F%2Fwww.patreon.com%2F"
  authorizationUrl = "https://vimeo.com/_rv/viewer"
  # detailsUrl = "https://vimeo.com/api/v2/video/$1.json"

var
  includeAudio, includeVideo, includeThumb, includeSubtitles: bool
  audioFormat: string
  subtitlesLanguage: string
  showStreams: bool


########################################################
# authentication
########################################################


proc authorize() =
  # QUESTION: vuid needed?
  logDebug("requesting authorization")
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
    logDebug("requesting captions")
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
  if stream.hasKey("avg_bitrate"):
    result = stream["avg_bitrate"].getInt()
  elif stream.hasKey("bitrate"):
    result = stream["bitrate"].getInt()


proc selectVideoStream(streams: seq[Stream], id, codec: string): Stream =
  ## select video by id or resolution
  if id != "":
    # NOTE: select by user itag choice
    for stream in streams:
      # NOTE: check kind because there are audio and video streams with the same id
      if stream.id == id and stream.kind != "audio":
        return stream
  elif codec != "":
    # NOTE: select by user codec preference
    result = selectVideoByBitrate(streams, codec)
  else:
    # NOTE: fallback selection
    result = selectVideoByBitrate(streams, "avc1")

  # NOTE: all other selection attempts failed, final attempt with not codec filter
  if result.id == "":
    result = selectVideoByBitrate(streams, "")


proc selectAudioStream(streams: seq[Stream], id, codec: string): Stream =
  ## select video by id or bitrate
  if id != "":
    # NOTE: select by user itag choice
    for stream in streams:
      # NOTE: check kind because there are audio and video streams with the same id
      if stream.id == id and stream.kind == "audio":
        return stream
  elif codec != "":
    # NOTE: select by user codec preference
    result = selectAudioByBitrate(streams, codec)
  else:
    # NOTE: fallback selection
    result = selectAudioByBitrate(streams, "mp4a")

  # NOTE: all other selection attempts failed, final attempt with not codec filter
  if result.id == "":
    result = selectVideoByBitrate(streams, "")


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


proc newStream(stream: JsonNode, videoId: string, duration: int, cdnUrl=""): Stream =
  ## populate new stream
  if stream.kind != JNull:
    if cdnUrl != "":
      result.urlSegments = stream.produceUrlSegments(cdnUrl.split("sep/")[0])
    else:
      result.url = stream["link"].getStr()

    if stream.hasKey("width"):
      if stream.hasKey("public_name"):
        result.kind = "combined"
      else:
        result.kind = "video"
      result.resolution = $stream["width"].getInt() & "x" & $stream["height"].getInt()
      result.semiperimeter = stream["width"].getInt() + stream["height"].getInt()
      if stream.hasKey("framerate"):
        result.fps = fmt"""{stream["framerate"].getFloat():.4}"""
      elif stream.hasKey("fps"):
        result.fps = fmt"""{stream["fps"].getFloat():.4}"""
      if isVerticle(stream):
        result.quality = $stream["width"].getInt() & "p"
      else:
        result.quality = $stream["height"].getInt() & "p"
    else:
      result.kind = "audio"
    if stream.hasKey("id"):
      result.id = stream["id"].getStr()
    elif stream.hasKey("public_name"):
      result.id = stream["public_name"].getStr()
    if stream.hasKey("mime_type"):
      result.mime = stream["mime_type"].getStr()
      result.ext = extensions[result.mime]
    if stream.hasKey("codecs"):
      result.codec = stream["codecs"].getStr()
    if result.kind == "combined":
      result.format = "progressive"
    else:
      result.format = "dash"
    result.duration = duration
    result.filename = addFileExt(videoId & "-" & result.id, result.ext)

    if stream.hasKey("segments"):
      for segment in stream["segments"]:
        result.size.inc(segment["size"].getInt())
    elif stream.hasKey("size"):
      result.size = stream["size"].getInt()
    result.sizeShort = formatSize(result.size, includeSpace=true)

    if stream.hasKey("avg_bitrate"):
      result.bitrate = stream["avg_bitrate"].getInt()
    else:
      # NOTE: weight by 0.95 to account for audio in filesize
      result.bitrate = int((result.size * 8) / duration * 0.95)
    result.bitrateShort = formatSize(result.bitrate, includeSpace=true) & "/s"
    result.exists = true


proc newDownload(streams: seq[Stream], title, vimeoUrl, thumbnailUrl, videoId, aId, vId, aCodec, vCodec: string): Download =
  result.title = title
  result.url = vimeoUrl
  result.videoId = videoId
  result.thumbnailUrl = thumbnailUrl

  if includeVideo:
    result.videoStream = selectVideoStream(streams, vId, vCodec)
  if includeAudio and result.videoStream.kind != "combined":
    result.audioStream = selectAudioStream(streams, aId, aCodec)


proc reportStreamInfo(stream: Stream) =
  ## echo metadata for single stream
  logInfo("stream: ", stream.filename)
  logInfo("id: ", stream.id)
  logInfo("size: ", stream.sizeShort)
  if stream.quality != "":
    logInfo("quality: ", stream.quality)
  if stream.mime != "":
    logInfo("mime: ", stream.mime)
  if stream.codec != "":
    logInfo("codec: ", stream.codec)
  if stream.format == "dash":
    logInfo("segments: ", stream.urlSegments.len)


proc extractProfileIds(vimeoUrl: string): tuple[profileId, sectionId: string] =
  ## obtain userId and sectionId from profiles
  var
    profileResponse: JsonNode
    response: string
    code: HttpCode
  logDebug("requesting webpage")
  (code, response) = doGet(vimeoUrl)
  if code.is2xx:
    profileResponse = parseJson(response)
    let parts = profileResponse["data"][0]["uri"].getStr().split('/')
    result = (parts[2], parts[^1])
  else:
    logDebug(code)
    logError("failed to obtain profile metadata")


proc extractId(vimeoUrl: string): string =
  ## extract video/profile id from url
  if vimeoUrl.contains("/config"):
    result = vimeoUrl.captureBetween('/', '/', vimeoUrl.find("video/"))
  elif vimeoUrl.contains("/video"):
    discard vimeoUrl.parseUntil(result, '?', vimeoUrl.find("video") + 7)
  else:
    discard vimeoUrl.parseUntil(result, {'?', '/'}, start=vimeoUrl.find(".com/") + 5)


proc extractHash(vimeoUrl: string): string =
  ## extract unlinsted hash from url
  if vimeoUrl.contains("&h="):
    result = vimeoUrl.captureBetween('=', '&', vimeoUrl.find("&h="))
  else:
    result = vimeoUrl.dequery().split('/')[^1]


proc isUnlisted(vimeoUrl: string): bool =
  ## check for unlisted hash in vimeo url
  if vimeoUrl.contains("&h="):
    result = true
  else:
    var slug: string
    if vimeoUrl.contains("/video"):
      slug = vimeoUrl.captureBetween('/', '?', vimeoUrl.find("/video").succ)
    else:
      slug = vimeoUrl.captureBetween('/', '?', vimeoUrl.find(".com/"))
    if slug.count('/') > 0:
      result = true


proc getBestThumb(thumbs: JsonNode): string =
  # QUESTION: are there other resolutions?
  if thumbs.hasKey("sizes"):
    result = thumbs["base_link"].getStr()
  else:
    if thumbs.hasKey("base"):
      result = thumbs["base"].getStr()
    elif thumbs.hasKey("1280"):
      result = thumbs["1280"].getStr()
    elif thumbs.hasKey("960"):
      result = thumbs["960"].getStr()
    elif thumbs.hasKey("640"):
      result = thumbs["640"].getStr()


proc getVideoData(videoId: string, unlistedHash=""): JsonNode =
  ## request video api data json
  var
    code: HttpCode
    response: string
    apiUrl: string

  result = newJNull()

  if unlistedHash != "":
    apiUrl = videoApiUnlistedUrl % [videoId, unlistedHash]
  else:
    apiUrl = videoApiUrl % videoId

  logDebug("requesting video api json")
  logDebug("api url: ", apiUrl)
  (code, response) = doGet(apiUrl)

  if code.is2xx:
    result = parseJson(response)
  else:
    logDebug(code)
    logError("failed to obtain video api data")


proc getPlayerConfig(configUrl, videoId: string): JsonNode =
  ## request player config json
  var
    code: HttpCode
    response: string
  let standardVimeoUrl = baseUrl & '/' & videoId

  result = newJNull()

  logDebug("requesting player config json")
  logDebug("config url: ", configUrl)
  (code, response) = doGet(configUrl)

  if code == Http403:
    logDebug(code)
    logNotice("trying embed url")
    # HACK: use patreon embed url to get meta data
    # QUESTION: is there a seperate bypass url for unlisted videos?
    headers.add(("referer", "https://cdn.embedly.com/"))
    (code, response) = doGet(bypassUrl % videoId)
    let embedResponse = response.captureBetween(' ', ';', response.find("""config =""") + 8)

    if embedResponse.contains("cdn_url"):
      result = parseJson(embedResponse)
    else:
      logError("failed to obtain player config")
  elif not code.is2xx:
    # let configResponse = parseJson(response)
    logDebug(code)
    # logError(configResponse["message"].getStr().strip(chars={'"'}))
    logError("failed to obtain player config")
  else:
    result = parseJson(response)


########################################################
# main
########################################################


proc grabVideo(vimeoUrl: string, aId, vId, aCodec, vCodec: string) =
  var
    code: HttpCode
    response: string
    title: string
    duration: int
    configUrl: string
    thumbnailUrl: string
    unlistedHash: string
    defaultCDN: string
    cdnUrl: string
    audioStreams: seq[Stream]
    videoStreams: seq[Stream]
  let
    videoId = extractId(vimeoUrl)
    standardVimeoUrl = baseUrl & '/' & videoId

  logInfo("video id: ", videoId)
  logDebug("grabVideo called")

  if isUnlisted(vimeoUrl):
    unlistedHash = extractHash(vimeoUrl)
    logDebug("unlisted hash: ", unlistedHash)

  let apiResponse = getVideoData(videoId, unlistedHash)
  if apiResponse.kind != JNull and apiResponse.hasKey("config_url"):
    configUrl = apiResponse["config_url"].getStr()
  elif apiResponse.kind != JNull and apiResponse.hasKey("embed_player_config_url"):
    configUrl = apiResponse["embed_player_config_url"].getStr()
  else:
    configUrl = genericConfigUrl % videoId
  let configResponse = getPlayerConfig(configUrl, videoId)

  if apiResponse.kind != JNull:
    title = apiResponse["name"].getStr()
    duration = apiResponse["duration"].getInt()
    thumbnailUrl = getBestThumb(apiResponse["pictures"])
    for stream in apiResponse["download"]:
      videoStreams.add(newStream(stream, videoId, duration))
  if configResponse.kind != JNull:
    if title == "":
      title = configResponse["video"]["title"].getStr()
    if duration == 0:
      duration = configResponse["video"]["duration"].getInt()
    if thumbnailUrl == "":
      thumbnailUrl = getBestThumb(configResponse["video"]["thumbs"])
    # NOTE: progressive streams have sparse meta data associated with them --> skip
    # for stream in configResponse["request"]["files"]["progressive"]:
    #   videoStreams.add(stream, videoId, duration)

    defaultCDN = configResponse["request"]["files"]["dash"]["default_cdn"].getStr()
    cdnUrl = configResponse["request"]["files"]["dash"]["cdns"][defaultCDN]["url"].getStr()
    logDebug("default CDN: ", defaultCDN)
    logDebug("CDN url: ", cdnUrl)
    logDebug("requesting CDN json")
    (code, response) = doGet(cdnUrl.dequery())
    if code.is2xx:
      let cdnResponse = parseJson(response)
      if cdnResponse["video"].kind != JNull:
        for stream in cdnResponse["video"]:
          videoStreams.add(newStream(stream, videoId, duration, cdnUrl))
      elif includeVideo:
        logDebug("no video streams present in cdn response")
        includeVideo = false
      if cdnResponse["audio"].kind != JNull:
        for stream in cdnResponse["audio"]:
          audioStreams.add(newStream(stream, videoId, duration, cdnUrl))
      elif includeAudio:
        logDebug("no audio streams present in cdn response")
        includeAudio = false
    else:
      logDebug(code)
      logError("failed to obtain cdn json")
      return
  else:
    logError("failed to obtain video metadata")
    return

  let allStreams = videoStreams.sorted(compareBitrate) & audioStreams.sorted(compareBitrate)

  let
    safeTitle = makeSafe(title)
    fullFilename = addFileExt(safeTitle & " [" & videoId & ']', ".mkv")

  if showStreams:
    displayStreams(allStreams)
    return
  if fileExists(fullFilename):
    logError("file exists: ", fullFilename)
    return

  let download = newDownload(allStreams, title, standardVimeoUrl, thumbnailUrl, videoId, aId, vId, aCodec, vCodec)
  logInfo("title: ", download.title)

  if includeThumb and thumbnailUrl != "":
    if not grab(download.thumbnailUrl, fullFilename.changeFileExt("jpeg"), overwrite=true).is2xx:
      logError("failed to download thumbnail")

  if includeSubtitles:
    if configResponse["request"].hasKey("text_tracks"):
      generateSubtitles(configResponse["request"]["text_tracks"])
    else:
      includeSubtitles = false
      logError("video does not contain subtitles")

  var attempt: HttpCode
  if includeVideo:
    reportStreamInfo(download.videoStream)
    if download.videoStream.format == "dash":
      attempt = grab(download.videoStream.urlSegments, download.videoStream.filename, overwrite=true)
    else:
      attempt = grab(download.videoStream.url, download.videoStream.filename, overwrite=true)
    if not attempt.is2xx:
      logError("failed to download video stream")
      includeVideo = false
      # NOTE: remove empty file
      discard tryRemoveFile(download.videoStream.filename)

  if includeAudio and download.audioStream.exists:
    reportStreamInfo(download.audioStream)
    if download.audioStream.format == "dash":
      attempt = grab(download.audioStream.urlSegments, download.audioStream.filename, overwrite=true)
    else:
      attempt = grab(download.audioStream.url, download.audioStream.filename, overwrite=true)
    if not attempt.is2xx:
      logError("failed to download audio stream")
      includeAudio = false
      # NOTE: remove empty file
      discard tryRemoveFile(download.audioStream.filename)
  else:
    includeAudio = false

  if includeAudio and includeVideo:
    streamsToMkv(download.videoStream.filename, download.audioStream.filename, fullFilename, subtitlesLanguage, includeSubtitles)
  elif includeAudio and not includeVideo:
    convertAudio(download.audioStream.filename, safeTitle & " [" & videoId & ']', audioFormat)
  elif includeVideo:
    streamToMkv(download.videoStream.filename, fullFilename, subtitlesLanguage, includeSubtitles)
  else:
    logError("no streams were downloaded")


proc grabProfile(vimeoUrl, aId, vId, aCodec, vCodec: string) =
  var
    profileResponse: JsonNode
    response: string
    code: HttpCode
    nextUrl: string
    urls: seq[string]

  logDebug("grabProfile called")

  let userSlug = dequery(vimeoUrl).split('/')[^1]
  let (userId, sectionId) = extractProfileIds(profileApiUrl % userSlug)
  nextUrl = videosApiUrl % [userId, sectionId]

  logDebug("user slug: ", userSlug, " user id: ", userId, " section id: ", sectionId)

  logInfo("collecting videos")
  while nextUrl != apiUrl:
    # logDebug("requesting next video")
    (code, response) = doGet(nextUrl)
    if code.is2xx:
      profileResponse = parseJson(response)
      for video in profileResponse["data"]:
        urls.add(playerUrl & video["clip"]["uri"].getStr())
      nextUrl = apiUrl & profileResponse["paging"]["next"].getStr()
    else:
      logDebug(code)
      logError("failed to obtain profile metadata")
      return

  logInfo(urls.len, " videos queued")
  for idx, url in urls:
    logGeneric(lvlInfo, "download", idx.succ, " of ", urls.len)
    grabVideo(url, aId, vId, aCodec, vCodec)


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
  authorize()
  if extractId(vimeoUrl).all(isDigit):
    grabVideo(vimeoUrl, aId, vId, aCodec, vCodec)
  else:
    grabProfile(vimeoUrl, aId, vId, aCodec, vCodec)
