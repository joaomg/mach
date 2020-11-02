# Copyright (C) 2020 João Marques Gomes
import unittest
import httpclient
import asyncdispatch
import asynctools
import terminal
import strutils
import os
import json # parse json
from osproc import execCmd

const
  srcServer = "src/mach.nim"
  port = 5200
  address = "http://localhost:" & $port
  
var serverProcess: AsyncProcess

const testConfig = "tests/test_localhost.cfg"

proc readLoop(process: AsyncProcess) {.async.} =
  while process.running:
    var buf = newString(256)
    let len = await readInto(process.outputHandle, addr buf[0], 256)
    buf.setLen(len)
    styledEcho(fgBlue, "Process: ", resetStyle, strip(buf))

  styledEcho(fgRed, "Process terminated")

proc startServer(file: string, useStdLib: bool) {.async.} =
  if not serverProcess.isNil and serverProcess.running:
    serverProcess.terminate()
    # TODO: https://github.com/cheatfate/asynctools/issues/9
    doAssert execCmd("kill -15 " & $serverProcess.processID()) == QuitSuccess
    serverProcess = nil

  # The nim process doesn't behave well when using `-r`, if we kill it, the
  # process continues running...
  let stdLibFlag =
    if useStdLib:
      " -d:useStdLib "
    else:
      ""
  doAssert execCmd("nimble c --hints:off -y " & stdLibFlag & file) == QuitSuccess

  serverProcess = startProcess(file.changeFileExt(ExeExt), workingDir="", args=[testConfig])
  asyncCheck readLoop(serverProcess)

  # Wait until server responds:

  for i in 0..10:
    var client = newAsyncHttpClient()
    styledEcho(fgBlue, "Getting ", address)
    let fut = client.get(address)
    yield fut or sleepAsync(3000)
    if not fut.finished:
      styledEcho(fgYellow, "Timed out")
    elif not fut.failed:
      styledEcho(fgGreen, "Server started!")
      return
    else: 
        styledEcho(fgYellow, "Other error!")
        echo fut.error.msg
    client.close()
    await sleepAsync(1000)

  doAssert false, "Failed to start server."

proc testTenant(useStdLib: bool) =
  waitFor startServer(srcServer, useStdLib)
  var client = newAsyncHttpClient(maxRedirects = 0)
  
  suite "Tenant useStdLib=" & $useStdLib:
    test "can get march root":      
      let resp = waitFor client.get(address)
      check resp.code == Http200

    test "get all tenants":      
      let resp = waitFor client.get(address & "/tenant")
      check resp.code == Http200
      check (waitFor resp.body) == """[]"""

    test "tenant Jerry doesn't exit":
      let resp = waitFor client.get(address & "/tenant/Jerry")
      check resp.code == Http404
      check (waitFor resp.body) == """{"msg":"Tenant not found"}"""

    test "create tenant Tom":      
      let resp = waitFor client.post(address & "/tenant", """{"name": "Tom"}""")
      check resp.code == Http200
      let data: JsonNode = (waitFor resp.body).parseJson
      check data["msg"].getStr == "Tenant created"

    test "create tenant Jerry":      
      let resp = waitFor client.post(address & "/tenant", """{"name": "Jerry"}""")
      check resp.code == Http200
      let data: JsonNode = (waitFor resp.body).parseJson
      check data["msg"].getStr == "Tenant created"

    test "create tenant Calvin":      
      let resp = waitFor client.post(address & "/tenant", """{"name": "Calvin"}""")
      check resp.code == Http200
      let data = (waitFor resp.body).parseJson
      check data["msg"].getStr == "Tenant created"

    test "create tenant Hobbes":      
      let resp = waitFor client.post(address & "/tenant", """{"name": "Hobbes"}""")
      check resp.code == Http200
      let data = (waitFor resp.body).parseJson
      check data["msg"].getStr == "Tenant created"

    test "we have four tenants":      
      let resp = waitFor client.get(address & "/tenant")
      check resp.code == Http200
      let data = (waitFor resp.body).parseJson
      check data.len == 4

      check pretty(data) == """[
  {
    "id": 3,
    "name": "Tom",
    "hash": "6ef4e23ae042e266714df9e60a5c49414b96a45267577ef2c0b1b1ec811185cd",
    "hashShort": ""
  },
  {
    "id": 4,
    "name": "Jerry",
    "hash": "34e977b29a5ea97f4d05b08842c38fbda2b60b5a288ce876e8ec0f204604ee2e",
    "hashShort": ""
  },
  {
    "id": 5,
    "name": "Calvin",
    "hash": "d03b620caaca8b7867ba9a630f8decc411bf90e69b62d6309210d090b2405981",
    "hashShort": ""
  },
  {
    "id": 6,
    "name": "Hobbes",
    "hash": "50cd46e8abe16f3b7e8945aa6c139f746e505bcacdea9fcee8be9127c3f0b343",
    "hashShort": ""
  }
]"""

when isMainModule:
  try:
    # testTenant(useStdLib=false) # with useStdLib=false doesn't work
    testTenant(useStdLib=true)

  finally:
    doAssert execCmd("kill -15 " & $serverProcess.processID()) == QuitSuccess