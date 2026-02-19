defmodule Modus.Nexus.RouterTest do
  use ExUnit.Case, async: true

  alias Modus.Nexus.Router

  describe "classify/1" do
    # 1. Greeting
    test "classifies greetings" do
      result = Router.classify("Merhaba!")
      assert result.intent == :chat
      assert result.sub_intent == :greeting
    end

    # 2. Farewell
    test "classifies farewells" do
      result = Router.classify("Güle güle!")
      assert result.intent == :chat
      assert result.sub_intent == :farewell
    end

    # 3. Agent query (Turkish)
    test "classifies agent query in Turkish" do
      result = Router.classify("Ajanların enerjisi ne durumda?")
      assert result.intent == :insight
      assert result.sub_intent == :agent_query
    end

    # 4. Stats query
    test "classifies stats query" do
      result = Router.classify("Toplam kaç ajan var?")
      assert result.intent == :insight
      assert result.sub_intent == :stats_query
    end

    # 5. Why query
    test "classifies why query" do
      result = Router.classify("Neden bu ajan öldü?")
      assert result.intent == :insight
      assert result.sub_intent == :why_query
    end

    # 6. Event query
    test "classifies event query" do
      result = Router.classify("Son olaylar neler?")
      assert result.intent == :insight
      assert result.sub_intent == :event_query
    end

    # 7. Spawn action
    test "classifies spawn entity action" do
      result = Router.classify("Yeni bir ajan oluştur")
      assert result.intent == :action
      assert result.sub_intent == :spawn_entity
    end

    # 8. Terrain modify action
    test "classifies terrain modify action" do
      result = Router.classify("Biome'u çöle değiştir")
      assert result.intent == :action
      assert result.sub_intent == :terrain_modify
    end

    # 9. Config change action
    test "classifies config change action" do
      result = Router.classify("Hızı ayarla, decay rate değiştir")
      assert result.intent == :action
      assert result.sub_intent == :config_change
    end

    # 10. General chat
    test "classifies general chat" do
      result = Router.classify("Bu simülasyon çok güzel")
      assert result.intent == :chat
      assert result.sub_intent == :general
    end

    # 11. English question
    test "classifies English question" do
      result = Router.classify("Where is the agent?")
      assert result.intent == :insight
    end

    # 12. Rule inject
    test "classifies rule inject action" do
      result = Router.classify("Yeni bir kural ekle")
      assert result.intent == :action
      assert result.sub_intent == :rule_inject
    end

    # 13. Question mark fallback
    test "question mark triggers insight fallback" do
      result = Router.classify("Bu doğru mu?")
      assert result.intent == :insight
    end

    # 14. Empty/nil handling
    test "handles nil input" do
      result = Router.classify(nil)
      assert result.intent == :chat
      assert result.sub_intent == :general
    end

    # 15. Confidence is present
    test "always returns confidence" do
      result = Router.classify("test")
      assert is_float(result.confidence)
      assert result.confidence >= 0.0 and result.confidence <= 1.0
    end
  end
end
