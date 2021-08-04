import std/[json, uri, parseutils]

import utils


# NOTE: s=788550b1a916f3211f77d5261169782a1c4b5a46_1620593836
# sha1hash_timestamp
# timestamp == unix time
# can use toUnix(getTime()) or epochTime().int
# timestamp most likely used in hash as salt
# QUESTIONS: SAPISIDHASH?

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
  authorizationUrl = "https://vimeo.com/_rv/viewer"
  apiUrl = "https://api.vimeo.com"
  profileUrl = "https://api.vimeo.com/users/$1/profile_sections?fields=uri%2Ctitle%2CuserUri%2Curi%2C"
  videosUrl = "https://api.vimeo.com/users/$1/profile_sections/$2/videos?fields=video_details%2Cprofile_section_uri%2Ccolumn_width%2Cclip.uri%2Cclip.name%2Cclip.type%2Cclip.categories.name%2Cclip.categories.uri%2Cclip.config_url%2Cclip.pictures%2Cclip.height%2Cclip.width%2Cclip.duration%2Cclip.description%2Cclip.created_time%2C&page=1&per_page=10"


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
    result.qlt = $stream["width"].getInt() & 'p'
  else:
    result.qlt = $stream["height"].getInt() & 'p'
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


proc getVideo(vimeoUrl: string) =
  var
    configResponse: JsonNode
    id, response: string
    code: HttpCode
  if vimeoUrl.contains("/config?"):
    # NOTE: config url already obtained from getProfile
    (code, response) = doGet(vimeoUrl)
  else:
    if vimeoUrl.contains("/video/"):
      id = vimeoUrl.captureBetween('/', '?', vimeoUrl.find("video/"))
    else:
      id = vimeoUrl.captureBetween('/', '?', vimeoUrl.find(".com/"))
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
        (code, response) = doGet("https://player.vimeo.com/video/$1?app_id=122963&referrer=https%3A%2F%2Fwww.patreon.com%2F" % id)
        let embedResponse = response.captureBetween(' ', ';', response.find("""config =""") + 8)

        if embedResponse.contains("cdn_url"):
          response = embedResponse
        else:
          echo "<failed to obtain meta data>"
          return
      else:
        (code, response) = doGet(signedConfigUrl.replace("\\"))
    elif not code.is2xx:
      echo "<failed to obtain meta data>"
      return

  configResponse = parseJson(response)
  if not configResponse["video"].hasKey("owner"):
    echo "<video does not exist or is hidden>"
  else:
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
      (code, response) = doGet(cdnUrl.dequery())
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


proc vimeoDownload*(vimeoUrl: string) =
  # TODO: find a better approach?
  try:
    discard parseInt(vimeoUrl.split('/')[^1])
    getVideo(vimeoUrl)
  except ValueError:
    getProfile(vimeoUrl)
