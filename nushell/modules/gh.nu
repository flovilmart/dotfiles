export def "last run" [] {
}

export def "last deploy" [...args: string] {
  last deploys $"-L 1 --json databaseId ($args)"
}

export def "last deploys" [--branch: string = main, ...args: string] {
  gh run list --workflow="build-deploy.yaml" --branch $branch --event push ...$args
}
