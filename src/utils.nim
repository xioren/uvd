import std/[os, re, strutils, strformat, asyncdispatch, terminal, asyncfile,
            tables, times, httpclient]
from math import floor

export asyncdispatch, os, strutils, re, tables, httpclient


const
  extensions* = {"video/webm": ".webm", "video/mp4": ".mp4",
                 "audio/mp4": ".mp4a", "audio/webm": ".weba"}.toTable
var
  headers* = @[("user-agent", "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/90.0.4430.85 Safari/537.36"),
               ("accept", "*/*")]


func dequery*(url: string): string =
  url.rsplit('?', 1)[0]


proc joinStreams*(videoStream, audioStream, filename: string) =
  ## join audio and video streams using ffmpeg
  let fullFilename = addFileExt(filename, "mkv")

  echo "[joining streams] ", videoStream, " + ", audioStream
  if execShellCmd(fmt"ffmpeg -i {videoStream} -i {audioStream} -c copy {quoteShell(fullFilename)} > /dev/null 2>&1") == 0:
    removeFile(videoStream)
    removeFile(audioStream)
    echo "[complete] ", fullFilename
  else:
    echo "<error joining streams>"


proc clearProgress() =
  stdout.eraseLine()
  stdout.cursorDown()
  stdout.eraseLine()
  stdout.cursorUp()


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


proc grab*(url: string, forceFilename = "",
           saveLocation=joinPath(getHomeDir(), "Downloads"), forceDl=false): HttpCode =
  ## download front end
  var filename: string

  if forceFilename == "":
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


proc grabMulti*(urls: seq[string], forceFilename = "",
                saveLocation=joinPath(getHomeDir(), "Downloads"), forceDl=false): HttpCode =
  ## downloadParts front end
  var filename: string

  if forceFilename == "":
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
