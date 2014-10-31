defmodule Mix.Tasks.Honeydew.Readme do
  use Mix.Task

  @shortdoc "Generate the project's README.md"

  def run(_) do
    File.write "README.md", EEx.eval_file("README.md.eex")
  end
end
