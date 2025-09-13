defmodule MessageBlasterTest do
  use ExUnit.Case
  doctest MessageBlaster

  test "greets the world" do
    assert MessageBlaster.hello() == :world
  end
end
