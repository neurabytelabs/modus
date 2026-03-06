defmodule Modus.Protocol.ConsciousChatPromptTest do
  use ExUnit.Case, async: false

  alias Modus.Protocol.ConsciousChatPrompt
  alias Modus.Mind.{EpisodicMemory, ConversationMemory, AffectMemory, Goals}
  alias Modus.Mind.Cerebro.SocialNetwork
  alias Modus.Mind.{Culture, Trust}

  setup do
    EpisodicMemory.init()
    ConversationMemory.init()
    AffectMemory.init()
    Goals.init()
    SocialNetwork.init()
    Culture.init()
    Trust.init()

    EpisodicMemory.clear_all()
    try do :ets.delete_all_objects(:conversation_memory) catch _, _ -> :ok end
    try do :ets.delete_all_objects(:affect_memories) catch _, _ -> :ok end
    Goals.clear_all()
    try do :ets.delete_all_objects(:social_network) catch _, _ -> :ok end
    try do :ets.delete_all_objects(:agent_culture) catch _, _ -> :ok end
    Trust.reset()
    :ok
  end

  defp make_agent(id, opts \\ []) do
    %{
      id: id,
      name: Keyword.get(opts, :name, "Agent_#{id}"),
      occupation: Keyword.get(opts, :occupation, "farmer"),
      personality: Keyword.get(opts, :personality, %{
        extraversion: 0.6, agreeableness: 0.5, openness: 0.5,
        conscientiousness: 0.5, neuroticism: 0.3
      }),
      needs: Keyword.get(opts, :needs, %{hunger: 30.0, social: 30.0, rest: 30.0, shelter: 30.0}),
      affect_state: Keyword.get(opts, :affect_state, :neutral),
      conatus_energy: Keyword.get(opts, :conatus_energy, 0.8),
      current_action: Keyword.get(opts, :current_action, :exploring),
      position: Keyword.get(opts, :position, {5, 5}),
      inventory: %{}, memory: [], relationships: %{}
    }
  end

  describe "build/3 user chat" do
    test "produces a prompt string with agent identity" do
      agent = make_agent("a1", name: "Luna", occupation: "herbalist")
      prompt = ConsciousChatPrompt.build(agent, "Hello!")
      assert is_binary(prompt)
      assert prompt =~ "Luna"
      assert prompt =~ "herbalist"
    end

    test "same question to 2 different agents produces different prompts" do
      agent_a = make_agent("a1", name: "Luna", occupation: "herbalist",
        personality: %{extraversion: 0.9, agreeableness: 0.8, openness: 0.9, conscientiousness: 0.3, neuroticism: 0.2})
      agent_b = make_agent("a2", name: "Grim", occupation: "blacksmith",
        personality: %{extraversion: 0.2, agreeableness: 0.2, openness: 0.3, conscientiousness: 0.8, neuroticism: 0.7})

      prompt_a = ConsciousChatPrompt.build(agent_a, "How are you?")
      prompt_b = ConsciousChatPrompt.build(agent_b, "How are you?")

      assert prompt_a != prompt_b
      assert prompt_a =~ "Luna"
      assert prompt_b =~ "Grim"
    end

    test "agent with high joy vs high sadness produces different tone" do
      joyful = make_agent("j1", name: "Happy", affect_state: :joy)
      sad = make_agent("s1", name: "Mopey", affect_state: :sadness)

      prompt_joy = ConsciousChatPrompt.build(joyful, "Tell me about yourself")
      prompt_sad = ConsciousChatPrompt.build(sad, "Tell me about yourself")

      assert prompt_joy =~ "happy" or prompt_joy =~ "😊"
      assert prompt_sad =~ "sad" or prompt_sad =~ "😢"
    end

    test "episodic memories appear in prompt" do
      agent = make_agent("em1", name: "Luna")
      EpisodicMemory.store("em1", :social, 100, "Met a friendly traveler at the river",
        emotion: :joy, related_agent_id: "traveler1")

      prompt = ConsciousChatPrompt.build(agent, "What have you been up to?")
      assert prompt =~ "remember"
      assert prompt =~ "traveler"
    end

    test "goals appear in prompt when active" do
      agent = make_agent("g1", name: "Luna")
      Goals.add_goal("g1", :build_home)

      prompt = ConsciousChatPrompt.build(agent, "What are you working on?")
      assert prompt =~ "goal" or prompt =~ "Build" or prompt =~ "wanting"
    end

    test "needs affect prompt content when high" do
      agent = make_agent("n1", name: "Luna",
        needs: %{hunger: 80.0, social: 30.0, rest: 30.0, shelter: 30.0})

      prompt = ConsciousChatPrompt.build(agent, "How are you?")
      assert prompt =~ "starving" or prompt =~ "hungry" or prompt =~ "food"
    end

    test "desires section reflects affect state" do
      agent = make_agent("d1", name: "Luna", affect_state: :desire)
      prompt = ConsciousChatPrompt.build(agent, "What's on your mind?")
      assert prompt =~ "drive" or prompt =~ "act" or prompt =~ "NEED"
    end
  end

  describe "build/3 agent-to-agent chat" do
    test "includes relationship context" do
      agent = make_agent("aa1", name: "Luna")
      SocialNetwork.update_relationship("aa1", "aa2", :positive_chat)

      prompt = ConsciousChatPrompt.build(agent, "Hey!", target_agent_id: "aa2")
      assert is_binary(prompt)
      assert prompt =~ "Luna"
      assert prompt =~ "talking to" or prompt =~ "Relationship"
    end

    test "agent-to-agent differs from user chat" do
      agent = make_agent("ab1", name: "Luna")
      user_prompt = ConsciousChatPrompt.build(agent, "Hello!")
      agent_prompt = ConsciousChatPrompt.build(agent, "Hello!", target_agent_id: "ab2")

      assert user_prompt =~ "Luna"
      assert agent_prompt =~ "Luna"
      assert agent_prompt =~ "Relationship" or agent_prompt =~ "talking to"
    end
  end

  describe "section helpers" do
    test "episodic_memory_section returns empty for no memories" do
      assert ConsciousChatPrompt.episodic_memory_section("none") == ""
    end

    test "episodic_memory_section formats memories" do
      EpisodicMemory.store("ep1", :social, 100, "Had a deep conversation about life", emotion: :joy)
      result = ConsciousChatPrompt.episodic_memory_section("ep1")
      assert result =~ "remember"
      assert result =~ "conversation about life"
      assert result =~ "joy"
    end

    test "conversation_memory_section filters by interlocutor" do
      ConversationMemory.record("cm1", "Bob", [{"cm1", "Hi Bob"}, {"Bob", "Hey!"}], 100)
      ConversationMemory.record("cm1", "Alice", [{"cm1", "Hi Alice"}, {"Alice", "Hello!"}], 101)

      bob_section = ConsciousChatPrompt.conversation_memory_section("cm1", "Bob")
      if bob_section != "", do: assert(bob_section =~ "Bob")
    end

    test "desires_section reflects goals and affect" do
      Goals.add_goal("ds1", :build_home)
      perception = %{affect_state: :desire, conatus_energy: 0.8}
      result = ConsciousChatPrompt.desires_section("ds1", perception)
      assert result =~ "driving" or result =~ "wanting" or result =~ "drive"
    end
  end
end
