defmodule Modus.Protocol.SecretKeepingTest do
  use ExUnit.Case, async: false

  alias Modus.Protocol.SecretKeeping

  setup do
    SecretKeeping.init()
    try do :ets.delete_all_objects(:agent_secrets) catch _, _ -> :ok end
    :ok
  end

  test "store_secret creates a secret" do
    secret = SecretKeeping.store_secret("a1", "I know where the treasure is")
    assert secret.content == "I know where the treasure is"
    assert secret.trust_threshold == 0.6
    assert SecretKeeping.secret_count("a1") == 1
  end

  test "store_secret with custom trust threshold" do
    secret = SecretKeeping.store_secret("a1", "Top secret", trust_threshold: 0.9)
    assert secret.trust_threshold == 0.9
  end

  test "try_share succeeds with sufficient trust" do
    secret = SecretKeeping.store_secret("a1", "Hidden resource", trust_threshold: 0.5)
    assert {:ok, shared} = SecretKeeping.try_share("a1", "a2", secret.id, 0.7)
    assert "a2" in shared.shared_with

    # Target should now have a copy
    target_secrets = SecretKeeping.get_secrets("a2")
    assert length(target_secrets) == 1
  end

  test "try_share denied with insufficient trust" do
    secret = SecretKeeping.store_secret("a1", "Very secret", trust_threshold: 0.8)
    assert {:denied, :insufficient_trust} = SecretKeeping.try_share("a1", "a2", secret.id, 0.3)
  end

  test "shareable_secrets filters by trust level" do
    SecretKeeping.store_secret("a1", "Low threshold", trust_threshold: 0.3)
    SecretKeeping.store_secret("a1", "High threshold", trust_threshold: 0.9)

    low_trust = SecretKeeping.shareable_secrets("a1", 0.4)
    assert length(low_trust) == 1

    high_trust = SecretKeeping.shareable_secrets("a1", 0.95)
    assert length(high_trust) == 2
  end

  test "get_secrets returns empty list for unknown agent" do
    assert SecretKeeping.get_secrets("unknown") == []
  end

  test "secret_count returns correct count" do
    SecretKeeping.store_secret("a1", "Secret 1")
    SecretKeeping.store_secret("a1", "Secret 2")
    SecretKeeping.store_secret("a1", "Secret 3")
    assert SecretKeeping.secret_count("a1") == 3
  end
end
