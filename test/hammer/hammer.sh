#!/bin/sh
mix compile.protocols
elixir -pa _build/$MIX_ENV/consolidated  --erl "+P 134217727" -S mix run `dirname $0`/hammer.exs
