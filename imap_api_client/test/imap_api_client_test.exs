defmodule ImapApiClientTest do
  use ExUnit.Case
  doctest ImapApiClient

  test "greets the world" do
    assert ImapApiClient.hello() == :world
  end
end
