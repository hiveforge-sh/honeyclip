## HTTP client abstraction for honeyclip
##
## Provides HttpClientLike interface with a real (stdlib) implementation and
## a MockHttpClient for unit testing without hitting the real network.
##
## RealHttpClient delegates to std/httpclient (sync).
## MockHttpClient lets tests register fixed responses keyed by (method, urlSubstring)
## and asserts call count.

import std/[httpclient, tables, strutils]

type
  HttpResponse* = tuple[statusCode: int, body: string]

  HttpClientLike* = ref object of RootObj

  RealHttpClient* = ref object of HttpClientLike
    inner*: HttpClient

  MockResponseKey = tuple[meth: string, urlSubstring: string]

  MockHttpClient* = ref object of HttpClientLike
    responses: Table[MockResponseKey, HttpResponse]
    calls*: seq[tuple[meth: string, url: string, body: string]]
    lastHeaders*: seq[tuple[key, val: string]]

method get*(c: HttpClientLike, url: string): HttpResponse {.base.} =
  raise newException(CatchableError, "abstract")

method post*(c: HttpClientLike, url: string, body: string,
             contentType: string = "application/json"): HttpResponse {.base.} =
  raise newException(CatchableError, "abstract")

method postMultipart*(c: HttpClientLike, url: string,
                      fieldName: string, fileBytes: string,
                      filename: string,
                      extraHeaders: openArray[tuple[key, val: string]] = @[]
                     ): HttpResponse {.base.} =
  raise newException(CatchableError, "abstract")

proc newRealHttpClient*(timeoutMs: int = 30_000): RealHttpClient =
  result = RealHttpClient(inner: newHttpClient(timeout = timeoutMs))

method get*(c: RealHttpClient, url: string): HttpResponse =
  let resp = c.inner.get(url)
  result = (resp.code.int, resp.body)

method post*(c: RealHttpClient, url: string, body: string,
             contentType: string = "application/json"): HttpResponse =
  c.inner.headers = newHttpHeaders({"Content-Type": contentType})
  let resp = c.inner.post(url, body = body)
  result = (resp.code.int, resp.body)
  c.inner.headers = newHttpHeaders()  # reset after use to avoid leaking Content-Type to subsequent requests

method postMultipart*(c: RealHttpClient, url: string,
                      fieldName: string, fileBytes: string,
                      filename: string,
                      extraHeaders: openArray[tuple[key, val: string]] = @[]
                     ): HttpResponse =
  var mp = newMultipartData()
  mp.add(fieldName, fileBytes, filename, "audio/wav")
  var hdrs = newHttpHeaders()
  for (k, v) in extraHeaders:
    hdrs[k] = v
  c.inner.headers = hdrs
  try:
    let resp = c.inner.post(url, multipart = mp)
    result = (resp.code.int, resp.body)
  finally:
    c.inner.headers = newHttpHeaders()  # never leak API-key headers to later requests

proc newMockHttpClient*(): MockHttpClient =
  MockHttpClient(responses: initTable[MockResponseKey, HttpResponse](), calls: @[])

proc register*(m: MockHttpClient, meth: string, urlSubstring: string,
               status: int, body: string) =
  m.responses[(meth.toUpperAscii, urlSubstring)] = (status, body)

proc lookup(m: MockHttpClient, meth: string, url: string): HttpResponse =
  for (k, v) in m.responses.pairs:
    if k.meth == meth.toUpperAscii and url.contains(k.urlSubstring):
      return v
  raise newException(ValueError, "MockHttpClient: no response registered for " & meth & " " & url)

method get*(c: MockHttpClient, url: string): HttpResponse =
  c.calls.add (meth: "GET", url: url, body: "")
  result = c.lookup("GET", url)

method post*(c: MockHttpClient, url: string, body: string,
             contentType: string = "application/json"): HttpResponse =
  c.calls.add (meth: "POST", url: url, body: body)
  result = c.lookup("POST", url)

method postMultipart*(c: MockHttpClient, url: string,
                      fieldName: string, fileBytes: string,
                      filename: string,
                      extraHeaders: openArray[tuple[key, val: string]] = @[]
                     ): HttpResponse =
  c.calls.add (meth: "POST_MULTIPART", url: url, body: fieldName & ":" & filename)
  c.lastHeaders = @extraHeaders
  result = c.lookup("POST", url)

proc callCount*(m: MockHttpClient, meth: string, urlSubstring: string): int =
  for c in m.calls:
    if c.meth.toUpperAscii == meth.toUpperAscii and c.url.contains(urlSubstring):
      inc result
