if uci.cursor():get("aredn", "@lqm[0]", "enable") == "1" then
  return { href = "lqm", display = "Neighbor Status", hint = "See the link status to our neighbors", enable = not config_mode }
end
