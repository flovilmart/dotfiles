use std assert
use ./utils.nu default_value

export def jwt [token?: string] {
  def b64_to_record [] { $in | decode base64 --nopad | decode | from json; }

  let token = default_value $token $in
  let parts = $token | split row "."
  assert (($parts | length) >= 2) "expected to have 3 components separated by ."
  let header = $parts.0 | b64_to_record
  let payload = $parts.1 | b64_to_record
  mut sig = null
  if ($parts | length) == 3 {
    $sig = $parts.2
  }
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

  let n = $signer.n | decode base64 --nopad --url | encode hex
  let e = $signer.e | decode base64 --nopad --url | encode hex


  let len = ($n | str length)

  print { len: $len, signer_n: $signer.n, enc_n: ($signer.n | encode base64), signer_e: $signer.e, n: $n, e: $e, hash: $hash, sig: $parts.2 } | to json
}
