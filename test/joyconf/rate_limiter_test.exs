defmodule Joyconf.RateLimiterTest do
  use ExUnit.Case, async: false

  alias Joyconf.RateLimiter

  setup do
    :ets.delete_all_objects(:rate_limiter)
    :ok
  end

  test "allows first reaction from a session" do
    assert RateLimiter.allow?("session-1") == true
  end

  test "blocks second reaction within 5 seconds" do
    assert RateLimiter.allow?("session-2") == true
    assert RateLimiter.allow?("session-2") == false
  end

  test "allows reactions from different sessions independently" do
    assert RateLimiter.allow?("session-a") == true
    assert RateLimiter.allow?("session-b") == true
  end

  test "allows reaction after cooldown expires" do
    assert RateLimiter.allow?("session-3") == true
    # Backdate the ETS entry to simulate expired cooldown
    now = System.monotonic_time(:millisecond)
    :ets.insert(:rate_limiter, {"session-3", now - 6_000})
    assert RateLimiter.allow?("session-3") == true
  end
end
