export def default_value [value, default] {
  if $value == null or $value == "" {
    return $default
  }
  return $value
}
