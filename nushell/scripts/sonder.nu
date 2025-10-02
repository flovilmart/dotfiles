export def "sonder codeartifact_auth_token" [] {
  aws --profile sonder-dev/codeartifact-readonly codeartifact get-authorization-token --domain sonder-prod --domain-owner 111664848662 --region us-east-1 --query authorizationToken --output text
}

export def "sonder find secret" [value: string] {
  sonder list secrets | split row "\n" | each { |s|
    print $s;
    [$s, (sonder get secret $s | from json | transpose | find $value)]
  } | where { |e| ($e.1 | length) != 0 }
}

export def "sonder relogin" [] {
  sonder aws signout
  sonder setup
  sonder rewrap
}

export def "sonder rewrap" [] {
  warp-cli disconnect
  warp-cli connect
}

export def --env "sonder auth codeartifact" [profile?: string] {
  {CODEARTIFACT_AUTH_TOKEN: (sonder codeartifact_auth_token)} | load-env
}

export def --env "sonder auth docker" [profile?: string] {
  aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin 382627676829.dkr.ecr.us-east-1.amazonaws.com
}

export def --env "sonder config aws" [profile?: string] {
  try {
    ^sonder ...([config aws $profile] | compact)
        | lines
        | where $it =~ export | parse "export {key}={value}" | transpose -d -i -r | load-env
  }
}

export def "sonder proxy db" [db_host?: string] {
  let DB_HOST = $db_host | default "shared-aurora-pg-staging.cluster-c0kopnruetbd.us-east-1.rds.amazonaws.com"
  let USER_SOCAT = $"($env.USER)-socat"
  kubectl run $USER_SOCAT --image=marcnuri/port-forward --env=$"REMOTE_HOST=($DB_HOST)" --env="REMOTE_PORT=5432" --env="LOCAL_PORT=5433" ;
  kubectl wait --for=condition=ready --timeout=60s pod $USER_SOCAT;
  kubectl port-forward --pod-running-timeout=10s $USER_SOCAT 5433:5433;
  kubectl delete pod $USER_SOCAT;
}

export def "sonder --help" [] {
  ^sonder --help

  print "sonder relogin"
  print "sonder rewrap"
  print "sonder proxy db"
  print "sonder auth"
}
