import std/[os, re, strutils, strformat, asyncdispatch, terminal, asyncfile,
            tables, times, httpclient]
from math import floor

export asyncdispatch, os, strutils, re, tables, httpclient, times


const
  extensions* = {"video/mp4": ".mp4", "video/webm": ".webm",
                 "audio/mp4": ".m4a", "audio/webm": ".weba",
                 "video/3gpp": ".3gpp"}.toTable
  audioCodecs = {"aac": "aac", "flac": "flac", "m4a": "aac",
                 "mp3": "libmp3lame", "ogg": "libopus", "wav": "pcm_s32le"}.toTable
  codecOptions = {"aac": "-f adts", "flac": "", "m4a": "-bsf:a aac_adtstoasc",
                  "mp3": "-qscale:a 0", "ogg": "", "wav": ""}.toTable
var
  currentSegment, totalSegments: int
  # HACK: a not ideal solution to erroneosly clearing terminal when no progress was made (e.g. 403 forbidden)
  madeProgress: bool
  headers* = @[("user-agent", "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/96.0.4664.45 Safari/537.36"),
               ("accept", "*/*")]


func dequery*(url: string): string =
  url.rsplit('?', 1)[0]


func makeSafe*(title: string): string =
  ## make video titles suitable for filenames
  # NOTE: subjective
  title.multiReplace((".", ""), ("/", "-"), (": ", " - "), (":", "-"), ("#", ""), ("\\", "-"))


proc zFill*(this: string, width: int, fill = '0'): string =
  if this.len >= width:
    result = this
  else:
    let distance = width - this.len
    result = fill.repeat(distance) & this


proc indexOf*[T](that: openarray[T], this: T): int =
  ## provide index of this in that
  for idx, item in that:
    if item == this:
      return idx
  raise newException(IndexDefect, "$1 not in $2" % [$this, $that.type])


proc joinStreams*(videoStream, audioStream, filename, subtitlesLanguage: string, includeCaptions: bool) =
  ## join audio and video streams using ffmpeg
  echo "[joining streams] ", videoStream, " + ", audioStream
  var command: string

  if includeCaptions:
    command = fmt"ffmpeg -y -i {videoStream} -i {audioStream} -i subtitles.srt -metadata:s:s:0 language={subtitlesLanguage} -c copy {quoteShell(filename)} > /dev/null 2>&1"
  else:
    command = fmt"ffmpeg -y -i {videoStream} -i {audioStream} -c copy {quoteShell(filename)} > /dev/null 2>&1"

  if execShellCmd(command) == 0:
    removeFile(videoStream)
    removeFile(audioStream)
    if includeCaptions:
      removeFile(addFileExt(subtitlesLanguage, "srt"))
    echo "[complete] ", filename
  else:
    echo "<error joining streams>"


proc convertAudio*(audioStream, filename, format: string) =
  ## convert audio stream to desired format
  var returnCode: int
  let fullFilename = addFileExt(filename, format)

  if not audioStream.endsWith(format):
    echo "[converting stream] ", audioStream
    if format == "ogg" and audioStream.endsWith(".weba"):
      returnCode = execShellCmd(fmt"ffmpeg -y -i {audioStream} -codec:a copy {quoteShell(fullFilename)} > /dev/null 2>&1")
    else:
      returnCode = execShellCmd(fmt"ffmpeg -y -i {audioStream} -codec:a {audioCodecs[format]} {codecOptions[format]} {quoteShell(fullFilename)} > /dev/null 2>&1")
  else:
    moveFile(audioStream, fullFilename)

  if returnCode == 0:
    removeFile(audioStream)
    echo "[complete] ", fullFilename
  else:
    echo "<error converting stream>"


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
  stdout.writeLine("size: ", formatSize(total.int, includeSpace=true),
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
  stdout.write("size: ", formatSize(total.int, includeSpace=true),
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
    echo '<', e.msg, '>'
  finally:
    client.close()


proc doGet*(url: string): tuple[httpcode: HttpCode, body: string] =
  let client = newHttpClient(headers=newHttpHeaders(headers))
  try:
    let response = client.get(url)
    result.httpcode = response.code
    result.body = response.body
  except Exception as e:
    echo '<', e.msg, '>'
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
    echo '<', e.msg, '>'
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
    echo '<', e.msg, '>'
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
    echo '<', e.msg, '>'
  finally:
    file.close()


proc grab*(url: string | seq[string], filename: string, saveLocation=getCurrentDir(), forceDl=false): HttpCode =
  ## download front end
  let filepath = joinPath(saveLocation, filename)
  if not forceDl and fileExists(filepath):
    echo "<file exists> ", filename
  else:
    result = waitFor download(url, filepath)
    if result.is2xx:
      echo "[success] ", filename
    else:
      echo '<', result, '>'
