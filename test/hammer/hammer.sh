#!/bin/sh
mix compile.protocols
elixir -pa _build/$MIX_ENV/consolidated  --erl "+P 134217727 +C multi_time_warp" -S mix run `dirname $0`/hammer.exs
