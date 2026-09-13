project = "Ubermensch LMAOBox"
title = "Ubermensch LMAOBox API Reference"
description = [[
Internal production-module reference for the self-contained LMAOBox runtime.
]]

file = { "src/ubermensch", "tools/validation" }
dir = "build/ldoc"
format = "markdown"
package = "ubermensch"

-- Documented local functions implement meaningful internal contracts even
-- though the generated runtime exposes no library API. Event callbacks and
-- protected-call closures intentionally remain ordinary implementation detail.
all = true
sort = true
