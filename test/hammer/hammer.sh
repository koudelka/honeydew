#!/bin/sh
mix compile.protocols
elixir -pa _build/$MIX_ENV/consolidated  --erl "-P 268435456" -S mix run `dirname $0`/hammer.exs
