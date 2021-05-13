import std/[os, re, strutils, strformat, asyncdispatch, terminal, asyncfile,
            tables, times]
import httpClient
from math import floor

export asyncdispatch, os, strutils, re, tables


const
  extensions* = {"video/webm": ".webm", "video/mp4": ".mp4",
                 "audio/mp4": ".mp4a", "audio/webm": ".weba"}.toTable()
  headers = [("user-agent", "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/90.0.4430.85 Safari/537.36"),
             ("accept", "*/*")]


func dequery*(url: string): string =
  url.rsplit('?', 1)[0]


proc joinStreams*(videoStreamPath, audioStreamPath, filepath: string) =
  ## join audio and video streams using ffmpeg
  let fullFilepath = addFileExt(filepath, "mkv")

  echo "[joining streams]"
  if execShellCmd(fmt"ffmpeg -i {videoStreamPath} -i {audioStreamPath} -c copy {quoteShell(fullFilepath)} > /dev/null 2>&1") == 0:
    removeFile(videoStreamPath)
    removeFile(audioStreamPath)
    echo "[complete] ", fullFilepath
  else:
    echo "<error joining streams>"


proc formatEta(eta: int): string =
  ## convert eta in seconds to hours or minutes (if applicable)
  if eta > 3599:
    result = $convert(Seconds, Hours, eta) & " hour(s)"
  elif eta > 59:
    result = $convert(Seconds, Minutes, eta) & " minute(s)"
  else:
    result = $eta & " second(s)"


proc onProgressChanged(total, progress, speed: BiggestInt) {.async.} =
  let
    bar = '#'.repeat(floor(progress.int / total.int * 30).int)
    eta = ((total - progress).int / speed.int).int
  stdout.eraseLine()
  stdout.write("[", alignLeft(bar, 30), "] ",
               "size: ", formatSize(total.int, includeSpace=true),
               " speed: ", formatSize(speed.int, includeSpace=true) , "/s",
               " eta: ", formatEta(eta))
  stdout.flushFile()


proc post*(url: string): string =
  var client = newHttpClient(headers=newHttpHeaders(headers))
  try:
    result = client.postContent(url)
  except Exception as e:
    result = e.msg
    echo '<', result, '>'


proc get*(url: string): string =
  var client = newHttpClient(headers=newHttpHeaders(headers))
  try:
    result = client.getContent(url)
  except Exception as e:
    result = e.msg
    echo '<', result, '>'


proc download(url, filepath: string): Future[string] {.async.} =
  ## download single files
  var
    client = newAsyncHttpClient(headers=newHttpHeaders(headers))
    file = openasync(filepath, fmWrite)
  client.onProgressChanged = onProgressChanged
  try:
    let resp = await client.request(url)
    await file.writeFromStream(resp.bodyStream)
    result = $resp.code()
  except Exception as e:
    result = e.msg
  finally:
    stdout.eraseLine()
    file.close()
    client.close()


proc downloadParts(parts: seq[string], filepath: string): Future[string] {.async.} =
  ## download multi-part files
  var
    client = newAsyncHttpClient(headers=newHttpHeaders(headers))
    file = openasync(filepath, fmWrite)
  client.onProgressChanged = onProgressChanged
  try:
    for url in parts:
      let resp = await client.request(url)
      await file.writeFromStream(resp.bodyStream)
      result = $resp.code()
  except Exception as e:
    result = e.msg
  finally:
    stdout.eraseLine()
    file.close()
    client.close()


proc grab*(url: string, forceFilename = "",
           saveLocation=joinPath(getHomeDir(), "Downloads"), forceDl=false): string =
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
    if result == "200 OK":
      echo "[success] ", filename
    else:
      echo '<', result, '>', filename


proc grabMulti*(urls: seq[string], forceFilename = "",
                saveLocation=joinPath(getHomeDir(), "Downloads"), forceDl=false): string =
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
    if result == "200 OK":
      echo "[success] ", filename
    else:
      echo '<', result, '>', filename
