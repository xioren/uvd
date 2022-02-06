import std/[json, sequtils]

import common


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

const
  baseUrl = "https://vimeo.com"
  apiUrl = "https://api.vimeo.com"
  profileApiUrl = "https://api.vimeo.com/users/$1/profile_sections?fields=uri%2Ctitle%2CuserUri%2Curi%2C"
  videosApiUrl = "https://api.vimeo.com/users/$1/profile_sections/$2/videos?fields=video_details%2Cprofile_section_uri%2Ccolumn_width%2Cclip.uri%2Cclip.name%2Cclip.type%2Cclip.categories.name%2Cclip.categories.uri%2Cclip.config_url%2Cclip.pictures%2Cclip.height%2Cclip.width%2Cclip.duration%2Cclip.description%2Cclip.created_time%2C&page=1&per_page=10"
  videoApiUrl = "https://api.vimeo.com/videos/$1?bypass_privacy=1"
  configUrl = "https://player.vimeo.com/video/$1/config?bypass_privacy=1"
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

  if result.id == "":
    result = streams[0]


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
    result.filename = addFileExt(videoId & "-" & result.kind, result.ext)

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
  if includeAudio and result.videoStream.format != "progressive":
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
    response: string
    code: HttpCode

  result = newJNull()

  logDebug("requesting video api json")

  if unlistedHash != "":
    (code, response) = doGet(videoApiUrl % videoId & "&h=" & unlistedHash)
  else:
    (code, response) = doGet(videoApiUrl % videoId)

  if code.is2xx:
    result = parseJson(response)
  else:
    logError("failed to obtain video api data")


proc getPlayerConfig(videoId: string, unlistedHash=""): JsonNode =
  ## request player config json
  var
    response: string
    code: HttpCode
  let standardVimeoUrl = baseUrl & '/' & videoId

  result = newJNull()

  logDebug("requesting player config json")
  if unlistedHash != "":
    (code, response) = doGet(configUrl % videoId & "&h=" & unlistedHash)
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
        logError("failed to obtain player config")
        return
    else:
      (code, response) = doGet(signedConfigUrl.replace("\\"))
  elif not code.is2xx:
    let configResponse = parseJson(response)
    logError(configResponse["message"].getStr().strip(chars={'"'}))
    logError("failed to obtain player config")
    return

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

  if isUnlisted(vimeoUrl):
    unlistedHash = extractHash(vimeoUrl)
    logDebug("unlisted hash: ", unlistedHash)

  authorize()
  let apiResponse = getVideoData(videoId, unlistedHash)
  let configResponse = getPlayerConfig(videoId, unlistedHash)

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
    # NOTE: progressive streams have barely any meta data associated with them --> skip
    # for stream in configResponse["request"]["files"]["progressive"]:
    #   videoStreams.add(stream, videoId, duration)

    defaultCDN = configResponse["request"]["files"]["dash"]["default_cdn"].getStr()
    cdnUrl = configResponse["request"]["files"]["dash"]["cdns"][defaultCDN]["url"].getStr()
    logDebug("default CDN: ", defaultCDN)
    logDebug("CDN url: ", cdnUrl)
    logDebug("requesting CDN json")
    (code, response) = doGet(cdnUrl.dequery())
    let cdnResponse = parseJson(response)
    for stream in cdnResponse["video"]:
      videoStreams.add(newStream(stream, videoId, duration, cdnUrl))
    for stream in cdnResponse["audio"]:
      audioStreams.add(newStream(stream, videoId, duration, cdnUrl))
  else:
    logError("failed to obtain video metadata")
    return

  let allStreams = videoStreams.sorted(compareBitrate) & audioStreams.sorted(compareBitrate)

  let
    safeTitle = makeSafe(title)
    fullFilename = addFileExt(safeTitle & " [" & videoId & ']', ".mkv")

  if fileExists(fullFilename) and not showStreams:
    logError("file exists: ", safeTitle)
  else:
    if showStreams:
      displayStreams(allStreams)
      return

    let download = newDownload(allStreams, title, standardVimeoUrl, thumbnailUrl, videoId, aId, vId, aCodec, vCodec)
    logInfo("title: ", download.title)

    if includeThumb and thumbnailUrl != "":
      if not grab(download.thumbnailUrl, fullFilename.changeFileExt("jpeg"), forceDl=true).is2xx:
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

  let userSlug = dequery(vimeoUrl).split('/')[^1]
  authorize()
  let (userId, sectionId) = extractProfileIds(profileApiUrl % userSlug)
  nextUrl = videosApiUrl % [userId, sectionId]

  logDebug("slug: ", userSlug, " user id: ", userId, " sectionId: ", sectionId)

  logInfo("collecting videos")
  while nextUrl != apiUrl:
    # logDebug("requesting next video")
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
  if extractId(vimeoUrl).all(isDigit):
    grabVideo(vimeoUrl, aId, vId, aCodec, vCodec)
  else:
    grabProfile(vimeoUrl, aId, vId, aCodec, vCodec)
