import std/[os, re, strutils, strformat, asyncdispatch, terminal, asyncfile,
            tables, times, httpclient]
from math import floor

export asyncdispatch, os, strutils, re, tables, httpclient, times


const
  extensions* = {"video/mp4": ".mp4", "video/webm": ".webm",
                 "audio/mp4": ".m4a", "audio/webm": ".weba"}.toTable
  audioCodecs = {"aac": "aac", "flac": "flac", "m4a": "aac",
                 "mp3": "libmp3lame", "ogg": "libopus", "wav": "pcm_s32le"}.toTable
  codecOptions = {"aac": "-f adts", "flac": "", "m4a": "-bsf:a aac_adtstoasc",
                  "mp3": "-qscale:a 0", "ogg": "", "wav": ""}.toTable
var
  # HACK: a not ideal solution to erroneosly clearing progress from terminal when no progress was made (e.g. 403 forbidden)
  madeProgress: bool
  headers* = @[("user-agent", "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/92.0.4515.115 Safari/537.36"),
               ("accept", "*/*")]


func dequery*(url: string): string =
  url.rsplit('?', 1)[0]


proc makeSafe*(title: string): string =
  ## make video titles suitable for filenames
  title.multiReplace((".", ""), ("/", "-"), (": ", " - "), (":", "-"), ("#", ""), ("\\", ""))


proc joinStreams*(videoStream, audioStream, filename: string) =
  ## join audio and video streams using ffmpeg
  let fullFilename = addFileExt(filename, "mkv")

  echo "[joining streams] ", videoStream, " + ", audioStream
  if execShellCmd(fmt"ffmpeg -y -i {videoStream} -i {audioStream} -c copy {quoteShell(fullFilename)} > /dev/null 2>&1") == 0:
    removeFile(videoStream)
    removeFile(audioStream)
    echo "[complete] ", fullFilename
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


proc doPost*(url, body: string): tuple[httpcode: HttpCode, body: string] =
  let client = newHttpClient(headers=newHttpHeaders(headers))
  try:
    let response = client.post(url, body=body)
    result.httpcode = response.code
    result.body = response.body
  except Exception as e:
    echo '<', e.msg, '>'


proc doGet*(url: string): tuple[httpcode: HttpCode, body: string] =
  let client = newHttpClient(headers=newHttpHeaders(headers))
  try:
    let response = client.get(url)
    result.httpcode = response.code
    result.body = response.body
  except Exception as e:
    echo '<', e.msg, '>'


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
    clearProgress()
    file.close()
    client.close()


proc downloadParts(parts: seq[string], filepath: string): Future[HttpCode] {.async.} =
  ## download multi-part streams
  # BUG: sometimes "Error: unhandled exception: No handles or timers registered in dispatcher. [ValueError]"
  # will be thrown. this is a Nim bug and is supposedly fixed in the newest version of Nim.
  let client = newAsyncHttpClient(headers=newHttpHeaders(headers))
  var file = openasync(filepath, fmWrite)
  client.onProgressChanged = onProgressChanged

  try:
    for url in parts:
      let resp = await client.request(url)
      await file.writeFromStream(resp.bodyStream)
      result = resp.code
  except Exception as e:
    echo '<', e.msg, '>'
  finally:
    clearProgress()
    file.close()
    client.close()


proc grab*(url: string, forceFilename="", saveLocation=getCurrentDir(), forceDl=false): HttpCode =
  ## download front end
  var filename: string

  if forceFilename.isEmptyOrWhitespace():
    filename = extractFilename(url)
  else:
    filename = forceFilename

  let filepath = joinPath(saveLocation, filename)
  if not forceDl and fileExists(filepath):
    echo "<file exists> ", filename
  else:
    result = waitFor download(url, filepath)
    if result.is2xx:
      echo "[success] ", filename
    else:
      echo '<', result, '>'


proc grabMulti*(urls: seq[string], forceFilename="", saveLocation=getCurrentDir(), forceDl=false): HttpCode =
  ## downloadParts front end
  var filename: string

  if forceFilename.isEmptyOrWhitespace():
    filename = extractFilename(urls[0])
  else:
    filename = forceFilename

  let filepath = joinPath(saveLocation, filename)
  if not forceDl and fileExists(filepath):
    echo "<file exists> ", filename
  else:
    result = waitFor downloadParts(urls, filepath)
    if result.is2xx:
      echo "[success] ", filename
    else:
      echo '<', result, '>'
