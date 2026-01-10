export def default_value [value, default] {
  if $value == null or $value == "" {
    return $default
  }
  return $value
}

# Returns a record which contains only the columns matching the passed parameters
# The condition can be a string or a block
export def "columns match" [condition] {
  mut block: closure = {||}
  if (($condition | describe) == "string") {
    $block = { |it| $it.key =~ $condition }
  } else {
    $block = $condition
  }
  let real_block = $block
  $in | transpose key value | where { |it| do $block $it } | transpose --header-row | first
}

export def edit [] {
  let input = $in
  let tmp = (mktemp -t nu-edit.XXXXXX)
  $input | save $tmp -f
  nu -c $"($env.EDITOR) ($tmp)"

  open $tmp
}

export def no_empty [] {
  return $in | where { |it| ($it | is-empty) == false }
}
