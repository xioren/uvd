import std/[algorithm, asyncdispatch, asyncfile, httpclient, json, logging, os,
            parseutils, sequtils, sets, strformat, strutils, tables, terminal, times, uri]
from math import floor

export algorithm, asyncdispatch, httpclient, json, os, parseutils, sequtils, strformat, strutils, tables, times, uri


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

const
  extensions* = {"video/mp4": ".mp4", "video/webm": ".webm",
                 "audio/mp4": ".m4a", "audio/webm": ".weba",
                 "video/3gpp": ".3gpp"}.toTable
  audioCodecs = {"aac": "aac", "flac": "flac", "m4a": "aac",
                 "mp3": "libmp3lame", "ogg": "libopus", "wav": "pcm_s32le"}.toTable
  codecOptions = {"aac": "-f adts", "flac": "", "m4a": "-bsf:a aac_adtstoasc",
                  "mp3": "-qscale:a 0", "ogg": "", "wav": ""}.toTable
var
  globalLogLevel* = lvlInfo
  currentSegment, totalSegments: int
  # HACK: a not ideal solution to prevent erroneosly clearing terminal when no progress was made (e.g. 403 forbidden)
  madeProgress: bool
  headers* = @[("user-agent", "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/96.0.4664.45 Safari/537.36"),
               ("accept", "*/*")]

proc doGet*(url: string): tuple[httpcode: HttpCode, body: string]


# NOTE: basic logger implementation
proc formatLogMessage(context: string, messageParts: varargs[string]): string =
  var msgLen = 0
  if context != "":
    msgLen.inc(context.len)
    msgLen.inc(3)
  for m in messageParts:
    msgLen.inc(m.len)

  result = newStringOfCap(msgLen)
  if context != "":
    result.add('[')
    result.add(context)
    result.add(']')
    result.add(' ')

  for m in messageParts:
    result.add(m)


proc logGeneric*(level: Level, context: string, messageParts: varargs[string, `$`]) =
  if globalLogLevel <= level:
    let fullMessage = formatLogMessage(context, messageParts)
    stdout.writeLine(fullMessage)


proc logDebug*(messageParts: varargs[string, `$`]) =
  if globalLogLevel < lvlInfo:
    let fullMessage = formatLogMessage("debug", messageParts)
    stdout.writeLine(fullMessage)


proc logInfo*(messageParts: varargs[string, `$`]) =
  if globalLogLevel < lvlNotice:
    let fullMessage = formatLogMessage("info", messageParts)
    stdout.writeLine(fullMessage)


proc logNotice*(messageParts: varargs[string, `$`]) =
  if globalLogLevel < lvlWarn:
    let fullMessage = formatLogMessage("notice", messageParts)
    stdout.writeLine(fullMessage)


proc logWarning*(messageParts: varargs[string, `$`]) =
  if globalLogLevel < lvlError:
    let fullMessage = formatLogMessage("warning", messageParts)
    stdout.writeLine(fullMessage)


proc logError*(messageParts: varargs[string, `$`]) =
  if globalLogLevel < lvlFatal:
    let fullMessage = formatLogMessage("error", messageParts)
    stdout.writeLine(fullMessage)


proc logFatal*(messageParts: varargs[string, `$`]) =
  if globalLogLevel < lvlNone:
    let fullMessage = formatLogMessage("fatal", messageParts)
    stdout.writeLine(fullMessage)


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
        segment = ""
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


func dequery*(url: string): string =
  ## removes queries and anchors
  url.rsplit('?', 1)[0].rsplit('#', 1)[0]


func makeSafe*(title: string): string =
  ## make video titles more suitable for filenames
  # NOTE: subjective
  title.multiReplace((".", ""), ("/", "-"), (": ", " - "), (":", "-"), ("#", ""),
                     ("\\", "-"), ("|", "-"))


proc indexOf*[T](that: openarray[T], this: T): int =
  ## provide index of this in item that
  for idx, item in that:
    if item == this:
      return idx
  raise newException(IndexDefect, "$1 not in $2" % [$this, $that.type])


proc compareBitrate*[T](x, y: T): int =
  ## compare bitrates for sorting
  if x.bitrate > y.bitrate:
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
      stdout.styledWrite(fgMagenta, column.title.center(column.width))
      stdout.write(columnSeparator)
    else:
      stdout.styledWriteLine(fgMagenta, column.title.center(column.width))
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


proc streamToMkv*(stream, filename, subtitlesLanguage: string, includeSubtitles: bool) =
  ## join audio and video streams using ffmpeg
  logInfo("converting: ", stream)
  var command: string

  if includeSubtitles:
    command = fmt"ffmpeg -y -i {stream} -i subtitles.srt -metadata:s:s:0 language={quoteShell(subtitlesLanguage)} -c copy {quoteShell(filename)} > /dev/null 2>&1"
  else:
    command = fmt"ffmpeg -y -i {stream} -c copy {quoteShell(filename)} > /dev/null 2>&1"

  if execShellCmd(command) == 0:
    removeFile(stream)
    if includeSubtitles:
      removeFile(addFileExt(subtitlesLanguage, "srt"))
    logGeneric(lvlInfo, "complete", filename)
  else:
    logError("failed to convert stream")


proc streamsToMkv*(videoStream, audioStream, filename, subtitlesLanguage: string, includeSubtitles: bool) =
  ## join audio and video streams using ffmpeg
  logInfo("joining streams: ", videoStream, " + ", audioStream)
  var command: string

  if includeSubtitles:
    command = fmt"ffmpeg -y -i {videoStream} -i {audioStream} -i subtitles.srt -metadata:s:s:0 language={quoteShell(subtitlesLanguage)} -c copy {quoteShell(filename)} > /dev/null 2>&1"
  else:
    command = fmt"ffmpeg -y -i {videoStream} -i {audioStream} -c copy {quoteShell(filename)} > /dev/null 2>&1"

  if execShellCmd(command) == 0:
    removeFile(videoStream)
    removeFile(audioStream)
    if includeSubtitles:
      removeFile(addFileExt(subtitlesLanguage, "srt"))
    logGeneric(lvlInfo, "complete", filename)
  else:
    logError("failed to join streams")


proc convertAudio*(audioStream, filename, format: string) =
  ## convert audio stream to desired format
  var returnCode: int
  let fullFilename = addFileExt(filename, format)

  if not audioStream.endsWith(format):
    logInfo("converting stream: ", audioStream)
    if format == "ogg" and audioStream.endsWith(".weba"):
      returnCode = execShellCmd(fmt"ffmpeg -y -i {audioStream} -codec:a copy {quoteShell(fullFilename)} > /dev/null 2>&1")
    else:
      returnCode = execShellCmd(fmt"ffmpeg -y -i {audioStream} -codec:a {audioCodecs[format]} {codecOptions[format]} {quoteShell(fullFilename)} > /dev/null 2>&1")
  else:
    moveFile(audioStream, fullFilename)

  if returnCode == 0:
    removeFile(audioStream)
    logGeneric(lvlInfo, "complete", fullFilename)
  else:
    logError("error converting stream")


proc clearProgress() =
  if madeProgress:
    stdout.eraseLine()
    stdout.cursorDown()
    stdout.eraseLine()
    stdout.cursorUp()
    madeProgress = false


proc onProgressChanged(total, progress, speed: BiggestInt) {.async.} =
  ## for contiguous streams
  const barWidth = 50
  let
    bar = '#'.repeat(floor(progress.int / total.int * barWidth).int)
    eta = initDuration(seconds=((total - progress).int / speed.int).int)

  stdout.eraseLine()
  stdout.writeLine("> size: ", formatSize(total.int, includeSpace=true),
                   " speed: ", formatSize(speed.int, includeSpace=true), "/s",
                   " eta: ", $eta)
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


proc doPost*(url, body: string): tuple[httpcode: HttpCode, body: string] =
  let client = newHttpClient(headers=newHttpHeaders(headers))
  try:
    let response = client.post(url, body=body)
    result.httpcode = response.code
    result.body = response.body
  except Exception as e:
    logError(e.msg)
  finally:
    client.close()


proc doGet*(url: string): tuple[httpcode: HttpCode, body: string] =
  let client = newHttpClient(headers=newHttpHeaders(headers))
  try:
    let response = client.get(url)
    result.httpcode = response.code
    result.body = response.body
  except Exception as e:
    logError(e.msg)
  finally:
    client.close()


proc download(url, filepath: string): Future[HttpCode] {.async.} =
  ## download single streams
  let client = newAsyncHttpClient(headers=newHttpHeaders(headers))
  var file = openasync(filepath, fmWrite)
  client.onProgressChanged = onProgressChanged

  try:
    let resp = await client.request(url)
    await file.writeFromStream(resp.bodyStream)
    result = resp.code
  except Exception as e:
    logError(e.msg)
  finally:
    file.close()
    client.close()
    clearProgress()


proc download(parts: seq[string], filepath: string): Future[HttpCode] {.async.} =
  ## download multi-part streams
  currentSegment = 0
  totalSegments = parts.len
  let client = newAsyncHttpClient(headers=newHttpHeaders(headers))
  var file = openasync(filepath, fmWrite)
  client.onProgressChanged = onProgressChangedMulti

  try:
    for url in parts:
      let resp = await client.request(url)
      await file.writeFromStream(resp.bodyStream)
      result = resp.code
      inc currentSegment
  except Exception as e:
    logError(e.msg)
  finally:
    file.close()
    client.close()
    stdout.eraseLine()
    madeProgress = false


proc save*(content, filepath: string): bool =
  ## write content to disk
  var file = open(filepath, fmWrite)

  try:
    file.write(content)
    result = true
  except Exception as e:
    logError(e.msg)
  finally:
    file.close()


proc grab*(url: string | seq[string], filename: string, saveLocation=getCurrentDir(), forceDl=false): HttpCode =
  ## download front end
  let filepath = joinPath(saveLocation, filename)
  if not forceDl and fileExists(filepath):
    logError("file exists: ", filename)
  else:
    result = waitFor download(url, filepath)
    if result.is2xx:
      logGeneric(lvlInfo, "complete", filename)
    elif result != HttpCode(0):
      logError(result)
