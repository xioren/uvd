import std/[algorithm, asyncdispatch, asyncfile, httpclient, json, os, parseutils,
            sequtils, sets, strformat, strutils, tables, terminal, times, uri]
from net import TimeoutError
from math import floor

export algorithm, asyncdispatch, httpclient, json, os, parseutils, sequtils,
       strformat, strutils, tables, times, uri


type
  Level* = enum
    lvlDebug,
    lvlInfo,
    lvlNotice,
    lvlWarn,
    lvlError,
    lvlFatal,
    lvlNone

  Stream* = object
    kind*: string
    id*: string
    mime*: string
    ext*: string
    codec*: string
    size*: int
    sizeShort*: string
    quality*: string
    resolution*: string
    semiperimeter*: int
    fps*: string
    duration*: int
    bitrate*: int
    bitrateShort*: string
    format*: string
    url*: string
    urlSegments*: seq[string]
    filename*: string
    exists*: bool

  Download* = object
    title*: string
    videoId*: string
    url*: string
    thumbnailUrl*: string
    audioStream*: Stream
    videoStream*: Stream
    includeAudio*: bool
    includeVideo*: bool
    includeThumb*: bool
    includeSubs*: bool
    headers*: seq[tuple[key, val: string]]

const
  globalTimeout = 60
  globalTimeoutInMilliseconds = globalTimeout * 1000
  globalRetryCount = 10
  extensions* = {"video/mp4": ".mp4", "video/webm": ".webm",
                 "audio/mp4": ".m4a", "audio/webm": ".weba",
                 "video/3gpp": ".3gpp"}.toTable
  audioCodecs = {"aac": "aac", "flac": "flac", "m4a": "aac",
                 "mp3": "libmp3lame", "ogg": "libopus", "wav": "pcm_s32le"}.toTable
  codecOptions = {"aac": "-f adts", "flac": "", "m4a": "-bsf:a aac_adtstoasc",
                  "mp3": "-qscale:a 0", "ogg": "", "wav": ""}.toTable
let
  termWidth = terminalWidth()
var
  globalHeaders* = @[("user-agent", "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/100.0.4896.79 Safari/537.36"),
                     ("accept", "text/html,application/xhtml+xml,application/xml;q=0.9,*/*"),
                     ("accept-Language", "en-us,en;q=0.5"),
                     ("accept-encoding", "identity"),
                     ("sec-fetch-mode", "navigate")]
  globalIncludeAudio*, globalIncludeVideo*, globalIncludeThumb*, globalIncludeSubs*: bool
  globalLogLevel* = lvlInfo
  currentSegment, totalSegments: int
  # HACK: a not ideal solution to prevent erroneosly clearing terminal when no progress was made (e.g. 403 forbidden)
  madeProgress: bool
  #[ NOTE: all streams are now throttled by bitrate/filesize despite correct n value translation.
    using identity encoding and bytes=0-resource size bypasses this ]#

proc doGet*(url: string, headers=globalHeaders): tuple[httpcode: HttpCode, body: string]


########################################################
# basic logger implementation
########################################################


proc formatLogMessage(context: string, messageParts: varargs[string]): string =
  var msgLen = 0
  if context != "":
    msgLen.inc(context.len + 3)
  for m in messageParts:
    msgLen.inc(m.len)

  result = newStringOfCap(msgLen)
  if context != "":
    result.add('[')
    result.add(context)
    result.add("] ")

  for m in messageParts:
    result.add(m)


proc logGeneric*(level: Level, context: string, messageParts: varargs[string, `$`]) {.inline.} =
  if globalLogLevel <= level:
    let fullMessage = formatLogMessage(context, messageParts)
    stdout.writeLine(fullMessage)


proc logDebug*(messageParts: varargs[string, `$`]) {.inline.} =
  if globalLogLevel < lvlInfo:
    let fullMessage = formatLogMessage("debug", messageParts)
    stdout.writeLine(fullMessage)


proc logInfo*(messageParts: varargs[string, `$`]) {.inline.} =
  if globalLogLevel < lvlNotice:
    let fullMessage = formatLogMessage("info", messageParts)
    stdout.writeLine(fullMessage)


proc logNotice*(messageParts: varargs[string, `$`]) {.inline.} =
  if globalLogLevel < lvlWarn:
    let fullMessage = formatLogMessage("notice", messageParts)
    stdout.writeLine(fullMessage)


proc logWarning*(messageParts: varargs[string, `$`]) {.inline.} =
  if globalLogLevel < lvlError:
    let fullMessage = formatLogMessage("warning", messageParts)
    stdout.writeLine(fullMessage)


proc logError*(messageParts: varargs[string, `$`]) {.inline.} =
  if globalLogLevel < lvlFatal:
    let fullMessage = formatLogMessage("error", messageParts)
    stdout.writeLine(fullMessage)


proc logFatal*(messageParts: varargs[string, `$`]) {.inline.} =
  if globalLogLevel < lvlNone:
    let fullMessage = formatLogMessage("fatal", messageParts)
    stdout.writeLine(fullMessage)


########################################################
# common
########################################################


proc newDownload*(title, url, thumbnailUrl, videoId: string): Download =
  result.title = title
  result.url = url
  result.videoId = videoId
  result.thumbnailUrl = thumbnailUrl
  result.includeAudio = globalIncludeAudio
  result.includeVideo = globalIncludeVideo
  result.includeThumb = globalIncludeThumb
  result.includeSubs = globalIncludeSubs
  result.headers = globalHeaders


########################################################
# hls / dash manifest parsing
########################################################


proc extractDashStreams*(dashManifestUrl: string): seq[string] =
  ## extract dash stream data from dash xml
  logDebug("requesting dash stream manifest")
  let (_, xml) = doGet(dashManifestUrl)
  var
    dashEntry: string
    idx = xml.find("<Representation")

  while true:
    idx.inc(xml.skipUntil(' ', idx))
    idx.inc(xml.parseUntil(dashEntry, "<Representation", idx))
    if dashEntry.contains("/MPD"):
      result.add("<Representation" & dashEntry.split("</AdaptationSet>")[0])
      break
    result.add("<Representation" & dashEntry)
    inc idx


proc extractDashSegments*(dashEntry: string): seq[string] =
  ## extract individual segment urls from dash entry
  logDebug("requesting dash segment manifest")
  var
    segments: string
    capture: bool
    segment: string

  let baseUrl = parseUri(dashEntry.captureBetween('>', '<', dashEntry.find("<BaseURL>") + 8))
  discard dashEntry.parseUntil(segments, """</SegmentList>""", dashEntry.find("""<SegmentList>"""))

  for c in segments:
    if c == '"':
      if capture:
        result.add($(baseUrl / segment))
        segment.reset()
      capture = not capture
    elif capture:
      segment.add(c)


proc extractHlsStreams*(hlsStreamsUrl: string): seq[string] =
  logDebug("requesting hls stream manifest")
  let (_, xml) = doGet(hlsStreamsUrl)
  var
    idx: int
    hlsEntry: string

  while idx < xml.high:
    idx.inc(xml.skipUntil(':', idx))
    inc idx
    idx.inc(xml.parseUntil(hlsEntry, '#', idx))
    result.add(hlsEntry)


proc extractHlsSegments*(hlsSegmentsUrl: string): seq[string] =
  logDebug("requesting hls segment manifest")
  let (_, xml) = doGet(hlsSegmentsUrl)
  var
    idx = xml.find("#EXTINF:")
    url: string
  while true:
    url = xml.captureBetween('\n', '\n', idx)
    if url == "#EXT-X-ENDLIST" or url == "":
      break
    result.add(url)
    idx.inc(xml.skipUntil('#', idx))
    inc idx


########################################################
# misc
########################################################


func dequery*(url: string): string =
  ## removes queries and anchors
  url.rsplit('?', 1)[0].rsplit('#', 1)[0]


func makeSafe*(title: string): string =
  ## make video titles more suitable for filenames
  # NOTE: subjective
  title.multiReplace((".", ""), ("/", "-"), (": ", " - "), (":", "-"), ("#", ""),
                     ("\\", "-"), ("|", "-"), ("*", ""), ("?", ""), ("\"", ""),
                     ("<", ""), (">", ""), ("^", "")).strip(chars={'-'})


proc indexOf*[T](that: openarray[T], this: T): int =
  ## provide index of element "this" in item "that"
  for idx, item in that:
    if item == this:
      return idx
  raise newException(IndexDefect, "$1 not in $2" % [$this, $that.type])


proc compareBitrate*[T](this, that: T): int =
  ## compare bitrates for sorting
  if this.bitrate > that.bitrate:
    result = -1
  else:
    result = 1


proc selectVideoByBitrate*(streams: seq[Stream], codec: string): Stream =
  ## select $codec video stream with highest bitrate (and resolution)
  var
    maxBitrate, idx, maxSemiperimeter: int
    select = -1

  for stream in streams:
    if stream.codec.contains(codec) and stream.kind != "audio":
      if stream.semiperimeter >= maxSemiperimeter:
        if stream.semiperimeter > maxSemiperimeter:
          maxSemiperimeter = stream.semiperimeter

        if stream.bitrate > maxBitrate:
          maxBitrate = stream.bitrate
          select = idx
    inc idx

  if select > -1:
    result = streams[select]


proc selectAudioByBitrate*(streams: seq[Stream], codec: string): Stream =
  ## select $codec audo stream with highest bitrate
  var
    maxBitrate, idx: int
    select = -1

  for stream in streams:
    # NOTE: for streams where codec is not known
    if stream.codec.contains(codec) and stream.kind == "audio":
      if stream.bitrate > maxBitrate:
        maxBitrate = stream.bitrate
        select = idx
    inc idx

  if select > -1:
    result = streams[select]


proc displayStreams*(streams: seq[Stream]) =
  ## display stream metadata in a readable layout
  # NOTE: inspiration taken from yt-dlp
  type Column = object
    title: string
    width: int
  const
    columnSeparator = "│"
    columnDivider = "─"
  var
    totalWidth: int
    headerKind = Column(title: "kind", width: 6)
    headerId = Column(title: "id", width: 6)
    headerQuality = Column(title: "quality", width: 9)
    headerResolution = Column(title: "resolution", width: 12)
    headerFps = Column(title: "fps", width: 5)
    headerBitrate = Column(title: "bitrate", width: 9)
    headerMime = Column(title: "mime", width: 6)
    headerExtension = Column(title: "extension", width: 11)
    headerCodec = Column(title: "codec", width: 7)
    headerSize = Column(title: "size", width: 6)
    headerFormat = Column(title: "format", width: 8)

  # NOTE: expand column widths as necessary
  for stream in streams:
    if stream.kind.len > headerKind.width - 2:
      headerKind.width = stream.kind.len + 2
    if stream.id.len > headerId.width - 2:
      headerId.width = stream.id.len + 2
    if stream.quality.len > headerQuality.width - 2:
      headerQuality.width = stream.quality.len + 2
    if stream.resolution.len > headerResolution.width - 2:
      headerResolution.width = stream.resolution.len + 2
    if stream.fps.len > headerFps.width - 2:
      headerFps.width = stream.fps.len + 2
    if stream.bitrateShort.len > headerBitrate.width - 2:
      headerBitrate.width = stream.bitrateShort.len + 2
    if stream.mime.len > headerMime.width - 2:
      headerMime.width = stream.mime.len + 2
    if stream.ext.len > headerExtension.width - 2:
      headerExtension.width = stream.ext.len + 2
    if stream.codec.len > headerCodec.width - 2:
      headerCodec.width = stream.codec.len + 2
    if stream.sizeShort.len > headerSize.width - 2:
      headerSize.width = stream.sizeShort.len + 2
    if stream.format.len > headerFormat.width - 2:
      headerFormat.width = stream.format.len + 2

  let headers = [
                 headerKind,
                 headerId,
                 headerQuality,
                 headerResolution,
                 headerFps,
                 headerBitrate,
                 headerMime,
                 headerExtension,
                 headerCodec,
                 headerSize,
                 headerFormat
                 ]

  # NOTE: write headers
  for idx, column in headers:
    if idx < headers.high:
      stdout.styledWrite(fgCyan, column.title.center(column.width))
      stdout.write(columnSeparator)
    else:
      stdout.styledWriteLine(fgCyan, column.title.center(column.width))
    totalWidth.inc(column.width)

  echo columnDivider.repeat(totalWidth + headers.len.pred)

  # NOTE: write stream data
  for stream in streams:
    stdout.write(stream.kind.center(headerKind.width), columnSeparator)
    stdout.write(stream.id.center(headerId.width), columnSeparator)
    stdout.write(stream.quality.center(headerQuality.width), columnSeparator)
    stdout.write(stream.resolution.center(headerResolution.width), columnSeparator)
    stdout.write(stream.fps.center(headerFps.width), columnSeparator)
    stdout.write(stream.bitrateShort.center(headerBitrate.width), columnSeparator)
    stdout.write(stream.mime.center(headerMime.width), columnSeparator)
    stdout.write(stream.ext.strip(trailing=false, chars={'.'}).center(headerExtension.width), columnSeparator)
    stdout.write(stream.codec.center(headerCodec.width), columnSeparator)
    stdout.write(stream.sizeShort.center(headerSize.width), columnSeparator)
    stdout.writeLine(stream.format.center(headerFormat.width))


proc clearProgress() =
  if madeProgress:
    stdout.eraseLine()
    stdout.cursorDown()
    stdout.eraseLine()
    stdout.cursorUp()
    madeProgress = false


proc onProgressChanged(total, progress, speed: BiggestInt) {.async.} =
  ## for progressive streams
  const barWidth = 50
  let
    bar = '#'.repeat(floor(progress.int / total.int * barWidth).int)
  var
    eta = $initDuration(seconds=((total - progress).int / speed.int).int)

  if eta.len >= termWidth:
    eta = eta[0..<termWidth]

  stdout.eraseLine()
  stdout.writeLine("> size: ", formatSize(total.int, includeSpace=true),
                   " speed: ", formatSize(speed.int, includeSpace=true), "/s",
                   " eta: ", eta)
  stdout.eraseLine()
  stdout.write("[", alignLeft(bar, barWidth), "]")
  stdout.setCursorXPos(0)
  stdout.cursorUp()
  stdout.flushFile()
  if not madeProgress:
    madeProgress = true


proc onProgressChangedMulti(total, progress, speed: BiggestInt) {.async.} =
  ## for segmented streams (e.g. DASH)
  stdout.eraseLine()
  stdout.write("> size: ", formatSize(total.int, includeSpace=true),
               " segment: ", currentSegment, " of ", totalSegments)
  stdout.setCursorXPos(0)
  stdout.flushFile()
  if not madeProgress:
    madeProgress = true


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


########################################################
# net and io
########################################################


proc update*(headers: var seq[tuple[key, val: string]], newEntry: tuple[key, val: string]) =
  ## update header entry or add if it doesn't exist
  for idx, existing in headers:
    if existing.key == newEntry.key:
      headers[idx] = newEntry
      return
  headers.add(newEntry)


proc streamToMkv*(stream, filename, subtitlesLanguage: string, includeSubtitles: bool): bool =
  ## put single stream in mkv container
  logInfo("converting: ", stream)
  var command: string

  if includeSubtitles:
    command = fmt"ffmpeg -y -loglevel panic -i {stream} -i {quoteShell(subtitlesLanguage)}.srt -metadata:s:s:0 language={quoteShell(subtitlesLanguage)} -c copy {quoteShell(filename)}"
  else:
    command = fmt"ffmpeg -y -loglevel panic -i {stream} -c copy {quoteShell(filename)}"

  logDebug("ffmpeg command: ", command)

  if execShellCmd(command) == 0:
    removeFile(stream)
    if includeSubtitles:
      removeFile(addFileExt(subtitlesLanguage, "srt"))
    logGeneric(lvlInfo, "complete", filename)
    result = true
  else:
    logError("failed to convert stream")


proc streamsToMkv*(videoStream, audioStream, filename, subtitlesLanguage: string, includeSubtitles: bool): bool =
  ## join audio and video streams in mkv container
  logInfo("joining streams: ", videoStream, " + ", audioStream)
  var command: string

  if includeSubtitles:
    command = fmt"ffmpeg -y -loglevel panic -i {videoStream} -i {audioStream} -i {quoteShell(subtitlesLanguage)}.srt -metadata:s:s:0 language={quoteShell(subtitlesLanguage)} -c copy {quoteShell(filename)}"
  else:
    command = fmt"ffmpeg -y -loglevel panic -i {videoStream} -i {audioStream} -c copy {quoteShell(filename)}"

  logDebug("ffmpeg command: ", command)

  if execShellCmd(command) == 0:
    removeFile(videoStream)
    removeFile(audioStream)
    if includeSubtitles:
      removeFile(addFileExt(subtitlesLanguage, "srt"))
    logGeneric(lvlInfo, "complete", filename)
    result = true
  else:
    logError("failed to join streams")


proc convertAudio*(audioStream, filename, format: string): bool =
  ## convert audio stream to desired format
  var returnCode: int
  let fullFilename = addFileExt(filename, format)

  if not audioStream.endsWith(format):
    logInfo("converting stream: ", audioStream)
    if format == "ogg" and audioStream.endsWith(".weba"):
      returnCode = execShellCmd(fmt"ffmpeg -y -loglevel panic -i {audioStream} -codec:a copy {quoteShell(fullFilename)}")
    else:
      returnCode = execShellCmd(fmt"ffmpeg -y -loglevel panic -i {audioStream} -codec:a {audioCodecs[format]} {codecOptions[format]} {quoteShell(fullFilename)}")
  else:
    moveFile(audioStream, fullFilename)

  if returnCode == 0:
    removeFile(audioStream)
    logGeneric(lvlInfo, "complete", fullFilename)
    result = true
  else:
    logError("error converting stream")


proc writeFromStream(f: AsyncFile, fs: FutureStream[string]): Future[int] {.async.} =
  ## in house version of stdlib proc with timeout
  var
    hasValue: bool
    value: string
    attempt: Future[(bool, string)]

  while true:
    attempt = fs.read()
    if await attempt.withTimeout(globalTimeoutInMilliseconds):
      (hasValue, value) = attempt.read()
      if hasValue:
        await f.write(value)
        result.inc(value.len)
      else:
        break
    else:
      raise newException(TimeoutError, "the server did not respond in time")


proc doPost*(url, body: string, headers=globalHeaders): tuple[httpcode: HttpCode, body: string] =
  let client = newHttpClient(headers=newHttpHeaders(headers))
  try:
    let response = client.post(url, body=body)
    result.httpcode = response.code
    result.body = response.body
  except Exception as e:
    logError(e.msg)
  finally:
    client.close()


proc doGet*(url: string, headers=globalHeaders): tuple[httpcode: HttpCode, body: string] =
  let client = newHttpClient(headers=newHttpHeaders(headers))
  try:
    let response = client.get(url)
    result.httpcode = response.code
    result.body = response.body
  except Exception as e:
    logError(e.msg)
  finally:
    client.close()


proc doDownload(url, filepath: string, headers: seq[tuple[key, val: string]]): Future[HttpCode] {.async.} =
  ## download progressive streams
  var
    file: AsyncFile
    attempt: Future[AsyncResponse]
    resp: AsyncResponse
    fMode: FileMode
    bytesRead: int
    tempHeaders = headers

  logDebug("download url: ", url)

  for n in 0..<globalRetryCount:
    if n > 0:
      logWarning("retry attempt: ", n)
    if bytesRead > 0:
      fMode = fmAppend
      tempHeaders.update(("range", "bytes=$1-" % $bytesRead))
    else:
      fMode = fmWrite

    let client = newAsyncHttpClient(headers=newHttpHeaders(tempHeaders))
    client.onProgressChanged = onProgressChanged
    logDebug("request headers: ", tempHeaders)

    attempt = client.request(url)
    try:
      if await attempt.withTimeout(globalTimeoutInMilliseconds):
        resp = attempt.read()
      else:
        result = Http408
        raise newException(TimeoutError, "the server did not respond in time")
      result = resp.code
    except Exception as e:
      logError(e.msg)
      client.close()
      return

    logDebug(result)

    if result == Http429:
      let waitTime = resp.headers.getOrDefault("retry-after").parseInt()
      logWarning("too many requests --> waiting: ", waitTime, " seconds")
      await sleepAsync(waitTime * 1000)
      continue

    file = openasync(filepath, fMode)
    logDebug("file opened at: ", filepath)
    try:
      bytesRead = await file.writeFromStream(resp.bodyStream)
    except TimeoutError:
      result = Http408
      logError("aborting after waiting $1 seconds for a response" % $globalTimeout)
    except Exception as catchall:
      logError(catchall.msg)
      result = HttpCode(0)
    finally:
      file.close()
      client.close()
      # QUESTION: reasoning behind this?
      stdout.eraseLine()
      madeProgress = false

    # NOTE: only retry on timeout
    if result != Http408:
      break


proc doDownload(parts: seq[string], filepath: string, headers: seq[tuple[key, val: string]]): Future[HttpCode] {.async.} =
  ## download dash/hls streams
  # NOTE: global vars used by onProgressChangedMulti
  currentSegment = 0
  totalSegments = parts.len
  var
    file: AsyncFile
    attempt: Future[AsyncResponse]
    resp: AsyncResponse
    bytesRead: int
    tempHeaders = headers

  let client = newAsyncHttpClient(headers=newHttpHeaders(tempHeaders))
  client.onProgressChanged = onProgressChangedMulti

  file = openasync(filepath, fmWrite)
  logDebug("file opened at: ", filepath)

  for url in parts:
    logDebug("download url: ", url)
    for n in 0..<globalRetryCount:
      if n > 0:
        logWarning("retry attempt: ", n)
      if bytesRead > 0:
        tempHeaders.update(("range", "bytes=$1-" % $bytesRead))
      logDebug("request headers: ", tempHeaders)

      attempt = client.request(url)
      try:
        if await attempt.withTimeout(globalTimeoutInMilliseconds):
          resp = attempt.read()
        else:
          result = Http408
          raise newException(TimeoutError, "the server did not respond in time")
        result = resp.code
      except Exception as e:
        logError(e.msg)
        client.close()
        file.close()
        return

      logDebug(result)

      if result == Http429:
        # NOTE: close file while we wait
        file.close()
        let waitTime = resp.headers.getOrDefault("retry-after").parseInt()
        logWarning("too many requests --> waiting: ", waitTime, " seconds")
        await sleepAsync(waitTime * 1000)
        file = openasync(filepath, fmAppend)
        continue

      try:
        bytesRead = await file.writeFromStream(resp.bodyStream)
      except TimeoutError:
        logError("aborting after waiting $1 seconds for a response" % $globalTimeout)
      except Exception as catchall:
        logError(catchall.msg)
        result = HttpCode(0)
      finally:
        # QUESTION: reasoning behind this?
        stdout.eraseLine()
        madeProgress = false

      # NOTE: only retry on timeout
      if result != Http408:
        bytesRead.reset()
        break
  client.close()
  file.close()


proc save*(content, filename: string): bool =
  ## write content to disk
  var file = open(filename, fmWrite)

  try:
    file.write(content)
    result = true
  except Exception as e:
    logError(e.msg)
  finally:
    file.close()


proc grab*(url: string | seq[string], filename: string, saveLocation=getCurrentDir(), overwrite=false, headers=globalHeaders): HttpCode =
  ## simple download fron end
  let filepath = joinPath(saveLocation, filename)
  if not overwrite and fileExists(filepath):
    logError("file exists: ", filename)
  else:
    result = waitFor doDownload(url, filepath, headers)
    if result.is2xx:
      logGeneric(lvlInfo, "complete", filename)
    elif result != HttpCode(0):
      logError(result)


proc complete*(download: Download, fullFilename, safeTitle, subtitlesLanguage, audioFormat: string): bool =
  ## download streams and finalize
  var
    attempt: HttpCode

  if download.includeVideo:
    reportStreamInfo(download.videoStream)
    if download.videoStream.format == "dash":
      attempt = grab(download.videoStream.urlSegments, download.videoStream.filename, overwrite=true, headers=download.headers)
    else:
      attempt = grab(download.videoStream.url, download.videoStream.filename, overwrite=true, headers=download.headers)
    if not attempt.is2xx:
      logDebug(attempt)
      logError("failed to download video stream")
      # NOTE: remove empty file
      discard tryRemoveFile(download.videoStream.filename)
      return

  if download.includeAudio and download.audioStream.exists:
    reportStreamInfo(download.audioStream)
    if download.audioStream.format == "dash":
      attempt = grab(download.audioStream.urlSegments, download.audioStream.filename, overwrite=true, headers=download.headers)
    else:
      attempt = grab(download.audioStream.url, download.audioStream.filename, overwrite=true, headers=download.headers)
    if not attempt.is2xx:
      logDebug(attempt)
      logError("failed to download audio stream")
      # NOTE: remove empty file
      discard tryRemoveFile(download.audioStream.filename)
      return

  # QUESTION: should we abort if either audio or video streams failed to download?
  if download.includeAudio and download.includeVideo:
    result = streamsToMkv(download.videoStream.filename, download.audioStream.filename, fullFilename, subtitlesLanguage, download.includeSubs)
  elif download.includeAudio and not download.includeVideo:
    result = convertAudio(download.audioStream.filename, safeTitle & " [" & download.audioStream.id & ']', audioFormat)
  elif download.includeVideo:
    result = streamToMkv(download.videoStream.filename, fullFilename, subtitlesLanguage, download.includeSubs)
  else:
    logError("no streams were downloaded")
