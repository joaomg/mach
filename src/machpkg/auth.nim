# https://github.com/nim-lang/nimforum/blob/master/src/auth.nim

import random, md5
import hmac

proc randomSalt(): string =
  result = ""
  for i in 0..127:
    var r = rand(225)
    if r >= 32 and r <= 126:
      result.add(chr(rand(225)))

proc devRandomSalt(): string =
  when defined(posix):
    result = ""
    var f = open("/dev/urandom")
    var randomBytes: array[0..127, char]
    discard f.readBuffer(addr(randomBytes), 128)
    for i in 0..127:
      if ord(randomBytes[i]) >= 32 and ord(randomBytes[i]) <= 126:
        result.add(randomBytes[i])
    f.close()
  else:
    result = randomSalt()

proc makeSalt*(): string =
  ## Creates a salt using a cryptographically secure random number generator.
  ##
  ## Ensures that the resulting salt contains no ``\0``.
  try:
    result = devRandomSalt()
  except IOError:
    result = randomSalt()

proc makeSessionKey*(): string =
  ## Creates a random key to be used to authorize a session.
  let 
      random1:string = makeSalt()
      random2:string = makeSalt()

  return toHex(hmac.hmac_sha256(random1, random2))

proc makeSha256Hash*(value: string): string =
    ## Create a hash, using sha256, combining salt and value

    let salt = makeSalt()    
    return toHex(hmac.hmac_sha256(salt, value))

when isMainModule:
    assert makeSessionKey() == "b8d432164e46faa90687de905c5c529041e87794189d14b1bea3765616ae40a6"