defmodule Modus.Protocol.DialogueSystemTest do
  use ExUnit.Case, async: false

  alias Modus.Protocol.DialogueSystem

  setup do
    DialogueSystem.init()
    # Clean up ETS
    try do
      :ets.delete_all_objects(:dialogue_history)
    catch
      _, _ -> :ok
    end

    :ok
  end

  defp make_agent(id, opts \\ []) do
    %{
      id: id,
      name: Keyword.get(opts, :name, "Agent_#{id}"),
      personality: %{
        extraversion: 0.6,
        agreeableness: 0.5,
        openness: 0.5,
        conscientiousness: 0.5,
        neuroticism: 0.3
      },
      needs: Keyword.get(opts, :needs, %{hunger: 50.0, social: 50.0, rest: 80.0, shelter: 70.0}),
      affect_state: :neutral,
      inventory: Keyword.get(opts, :inventory, %{}),
      memory: Keyword.get(opts, :memory, []),
      relationships: %{}
    }
  end

  test "topics/0 returns all conversation topics" do
    assert :trade in DialogueSystem.topics()
    assert :warning in DialogueSystem.topics()
    assert :gossip in DialogueSystem.topics()
    assert :alliance in DialogueSystem.topics()
  end

  test "topic_icon/1 returns correct icons" do
    assert DialogueSystem.topic_icon(:trade) == "💰"
    assert DialogueSystem.topic_icon(:alliance) == "🤝"
    assert DialogueSystem.topic_icon(:gossip) == "👂"
    assert DialogueSystem.topic_icon(:warning) == "⚠️"
  end

  test "determine_topic returns :trade when agent has surplus" do
    agent = make_agent("a1", inventory: %{wood: 10})
    partner = make_agent("a2", inventory: %{food: 5})
    assert DialogueSystem.determine_topic(agent, partner) == :trade
  end

  test "determine_topic returns :alliance when social need is high" do
    agent =
      make_agent("a1", needs: %{hunger: 30, social: 80, rest: 80, shelter: 70}, inventory: %{})

    partner = make_agent("a2")
    assert DialogueSystem.determine_topic(agent, partner) == :alliance
  end

  test "determine_topic returns :warning when agent has danger memories" do
    agent = make_agent("a1", memory: [{10, %{type: :danger}}], inventory: %{})
    partner = make_agent("a2")
    assert DialogueSystem.determine_topic(agent, partner) == :warning
  end

  test "start_dialogue creates and stores a dialogue" do
    Modus.Mind.Cerebro.SocialNetwork.init()
    agent = make_agent("a1")
    partner = make_agent("a2")

    assert {:ok, dialogue} = DialogueSystem.start_dialogue(agent, partner, 100)
    assert dialogue.initiator_id == "a1"
    assert dialogue.partner_id == "a2"
    assert dialogue.topic in DialogueSystem.topics()
    assert length(dialogue.messages) == 1
  end

  test "get_history returns stored dialogues" do
    Modus.Mind.Cerebro.SocialNetwork.init()
    agent = make_agent("a1")
    partner = make_agent("a2")

    DialogueSystem.start_dialogue(agent, partner, 100)
    history = DialogueSystem.get_history("a1")
    assert length(history) == 1
  end

  test "get_recent limits results" do
    Modus.Mind.Cerebro.SocialNetwork.init()
    agent = make_agent("a1")

    for i <- 1..10 do
      partner = make_agent("p#{i}")
      DialogueSystem.start_dialogue(agent, partner, i * 10)
    end

    recent = DialogueSystem.get_recent("a1", 3)
    assert length(recent) == 3
  end
end
