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
    mut url = $url
    if ($url | str starts-with "http") {
      $url
    } else {
      $url = $"https://app.asana.com/api/1.0/($url)"
    }
    let res = (http get --allow-errors -H (headers) $url)
    if ("errors" in $res) {
      print $res.errors
    }

    if ("data" in $res) {
      $res.data
    } else {
      $res
    }
  }

  export def post [url: string, body: record] {
    mut url = $url
    if ($url | str starts-with "http") {
      $url
    } else {
      $url = $"https://app.asana.com/api/1.0/($url)"
    }
    if (config read debug | is-not-empty) {
      print $"POST: ($url)"
      print $"BODY: ($body | to json)"
    }
    let res = (http post -H (headers) --allow-errors --content-type "application/json" $url $body)
    if ("errors" in $res) {
      print $res.errors
    }
    if ("data" in $res) {
      $res.data
    } else {
      $res
    }
  }

  export def put [url: string, body: record] {
    mut url = $url
    if ($url | str starts-with "http") {
      $url
    } else {
      $url = $"https://app.asana.com/api/1.0/($url)"
    }
    if (config read debug | is-not-empty) {
      print $"POST: ($url)"
      print $"BODY: ($body | to json)"
    }
    let res = (http put -H (headers) --allow-errors --content-type "application/json" $url $body)
    if ("errors" in $res) {
      print $res.errors
    }
    if ("data" in $res) {
      $res.data
    } else {
      $res
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


export def "ai function declarations" [] {
  return [
    {
      type: "function",
      function: {
        name: "asana_api_get"
        description: "
makes   a get api call on the asana API.

Notabl  e APIs:

When n  eeding to pass a workspace ID add it to the url query parameters in the form workspace=ASANA_WORKSPACE_ID
When n  eeding to pass assignee, always use the global id (GID) of the user unless specified othewise.

GET ti  me period: https://app.asana.com/api/1.0/time_periods
Search  ing for tasks: https://app.asana.com/api/1.0/workspaces/ASANA_WORKSPACE_ID/tasks/search

GET us  er: https://app.asana.com/api/1.0/users/USER_GID (USER_GID is the user's global id)
GET th  e current user: https://app.asana.com/api/1.0/users/me
"
        parameters: {
          type: "object"
          properties: {
            "url": {
              "type": "string"
              "description": "The URL to make the get request to"
            }
          }
        }
      }
      handler: { |args, state|
        return (api get $args.url)
      }
    }
    {
      type: "function"
      function: {
        name: "asana_api_post",
        description: "
makes a post api call on the asana API

Notable APIs:

Create task: https://app.asana.com/api/1.0/tasks
Create goal: https://app.asana.com/api/1.0/goals
"
        parameters: {
          type: "object"
          properties: {
            "url": {
              "type": "string",
              "description": "The URL to make the post request to"
            }
            "body": {
              "type": "string",
              "description": "The body of the post request in a JSON stringified format. All asana API request have a top level data key."
            }
          }
        }
      }
      handler: { |args, state|
        return (api post $args.url ($args.body | from json))
      }
    },
    {
      type: "function"
      function: {
        name: "asana_api_put"
        description: "
makes a PUT api call on the asana API.

This is use to update a resource.

Notable APIs:

Update task: https://app.asana.com/api/1.0/tasks/RESOURCE_ID
Update goal: https://app.asana.com/api/1.0/goals/RESOURCE_ID
"
        parameters: {
          type: "object"
          properties: {
            "url": {
              "type": "string",
              "description": "The URL to make the post request to"
            },
            "body": {
              "type": "string",
              "description": "The body of the post request in a JSON stringified format. All asana API request have a top level data key."
            }
          }
        }
      }
      handler: { |args, state|
        return (api put $args.url ($args.body | from json))
      }
    } {
      type: "function"
      function: {
        name: "asana_typeahead"
        description: "Allows to find user, project, tasks etc... by their name",
        parameters: {
          type: "object",
          properties: {
            "type": {
              "type": "string",
              "description": "The type of resource to search for"
            },
            "query": {
              "type": "string",
              "description": "The query to search for"
            }
          }
        }
      }
      handler: { |args, state|
        return (typeahead $args.type $args.query)
      }
    }
  ]
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
