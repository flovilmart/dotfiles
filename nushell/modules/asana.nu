# The condition can be a string or a block
def "columns match" [condition] {
  mut block: closure = {||}
  if (($condition | describe) == "string") {
    $block = { |it| $it.key =~ $condition }
  } else {
    $block = $condition
  }
  let real_block = $block
  $in | transpose key value | where { |it| do $block $it } | transpose --header-row | first
}

export module config {
  def env_key [key: string] {
    match $key {
      "token" => {
        "ASANA_TOKEN"
      }
      "debug" => {
        "ASANA_DEBUG"
      },
      _ => {
        if ($key | str upcase | str contains "_ID") {
          $"ASANA_($key)" | str upcase
        } else {
          $"ASANA_($key)_ID" | str upcase
        }
      }
    }
  }

  export def --env set [key: string, value: string] {
    let env_key = (env_key $key)
    load-env { ($env_key): $value }
  }

  export def read [key: string] {
    let the_key = (env_key $key)
    if ($the_key in $env) {
      return ($env | get $the_key)
    } else {
      null
    }
  }

  export def get_team [] {
    if ("ASANA_TEAM_ID" in $env) {
      return $env.ASANA_TEAM_ID
    }
    null
  }

  export def get_workspace [] {
    if ("ASANA_WORKSPACE_ID" in $env) {
      return $env.ASANA_WORKSPACE_ID
    }
    null
  }

  export def get_token [] {
    if ("ASANA_TOKEN" in $env) {
      return $env.ASANA_TOKEN
    }
    null
  }

  export def main [] {
    print "Asnaa config wrapper"
    $env | columns match "ASANA"
  }
}

use config

def headers [] {
  return [
    'Content-Type', 'application/json',
    'Accept', 'application/json',
    'Authorization', $"Bearer (config get_token)"
  ]
}

export module api {
  export def get [url: string] {
    let res = (http get -H (headers) $url)

    if ($res.data | is-empty) {
      {}
    } else {
      $res.data
    }
  }

  export def post [url: string, body: record] {
    if (config read debug | is-not-empty) {
      print $"POST: ($url)"
      print $"BODY: ($body | to json)"
    }
    let res = (http post -H (headers) --allow-errors --content-type "application/json" $url $body)
    if ("errors" in $res) {
      print $res.errors
      error make --unspanned { msg: $res.errors }
    }
    if ($res.data | is-empty) {
      {}
    } else {
      $res.data
    }
  }
}

use api

export def typeahead [type: string, query: string] {
  let url = $"https://app.asana.com/api/1.0/workspaces/(config get_workspace)/typeahead"
  let params = {
      resource_type: $type,
      query: $query
  }
  api get $"($url)?resource_type=($type)&query=($query)"
}

export module project {
  export def tasks [project_id: string] {
    api get $"https://app.asana.com/api/1.0/projects/($project_id)/tasks"
  }

  export def create [name: string, owner?: string, team?: string, privacy_setting = "private"] {
    mut team = $team
    if ($team | is-empty) {
      $team = (config get_team)
    }
    let url = $"https://app.asana.com/api/1.0/projects"
    let body = {
        data: {
            name: $name,
            workspace: $env.ASANA_WORKSPACE_ID,
            team: $team,
            owner: $owner,
            privacy_setting: $privacy_setting,
        }
    }
    api post $url $body
  }
}

export module goal {
  export def create [body: record] {

    let url = $"https://app.asana.com/api/1.0/goals"
    api post $url $body
  }

  export def "create all" [list: list<record>] {
    $list | each { |it|
     (create $it)
    }
  }
}

export module time_periods {
  export def get [] {
    api get $"https://app.asana.com/api/1.0/time_periods?workspace=(config get_workspace)"
  }
}

export module task {
  export def get [task_id: string] {
    api get $"https://app.asana.com/api/1.0/tasks/($task_id)"
  }

  export def stories [task_id: string] {
    api get $"https://app.asana.com/api/1.0/tasks/($task_id)/stories"
  }

  export def subtasks [task_id: string] {
    api get $"https://app.asana.com/api/1.0/tasks/($task_id)/subtasks"
  }
}

export def main [] {
  print "Asana API Wrapper"
  help asana
}
