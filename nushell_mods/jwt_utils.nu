use std assert
use ./utils.nu default_value

def part_to_record [part: string] {
  $part | decode new-base64 --nopad | decode | from json
}

export def jwt [token?: string] {
  let token = default_value $token $in
  let parts = $token | split row "."
  let header = part_to_record $parts.0
  let payload = part_to_record $parts.1
  let sig = $parts.2
  {
    header: $header
    payload: $payload
    signature: $sig
  }
}

export def fetch_keys [jwks_url: string] {
  (http get $jwks_url).keys
}

export def verify_signature [token: string, jwks?: string] {
  let parts = $token | split row "."
  let json_parts = $parts | first 2
  let hash = $json_parts | str join "." | hash sha256
  let parsed_jwt = jwt $token
  print "Fetching keys..."
  mut jwks = $jwks
  if $jwks == null {
    $jwks = $'($parsed_jwt.payload.iss)/.well-known/jwks.json'
    print $"Using ($jwks)"
  }
  let keys = fetch_keys $jwks

  let kid = $parsed_jwt.header.kid
  let key = ($keys | filter { |k| $k.kid == $kid and $k.use == 'sig' }).0

  # ensure we have a single key matching!
  assert ($key != null)
  print $"Found a matching key ($key.use) - ($key.kid)"

  let signer = $key | select e kty n
  print $signer.n

  let n = $signer.n | decode new-base64 --nopad --url | encode hex
  let e = $signer.e | decode new-base64 --nopad --url | encode hex


  let len = ($n | str length)

  print { len: $len, signer_n: $signer.n, enc_n: ($signer.n | encode new-base64), signer_e: $signer.e, n: $n, e: $e, hash: $hash, sig: $parts.2 } | to json
}
