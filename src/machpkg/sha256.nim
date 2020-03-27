import strutils
 
const SHA256Len = 32
 
proc SHA256(d: cstring, n: culong, md: cstring = nil): cstring {.cdecl, dynlib: "c:/OpenSSL-Win64/libcrypto-1_1-x64.dll", importc.}
 
proc SHA256(s: string): string =
  result = ""
  let s = SHA256(s.cstring, s.len.culong)
  for i in 0 .. < SHA256Len:
    result.add s[i].BiggestInt.toHex(2).toLower
 
# 764faf5c61ac315f1497f9dfa542713965b785e5cc2f707d6468d7d1124cdfcf
echo SHA256("Rosetta code")