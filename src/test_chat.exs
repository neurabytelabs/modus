agents = Modus.AgentRegistry |> Registry.select([{{:"$1", :_, :_}, [], [:"$1"]}])
[agent_id | rest] = agents
state1 = Modus.Simulation.Agent.get_state(agent_id)
IO.puts("Agent 1: #{state1.name} (#{state1.occupation})")

result1 = Modus.Intelligence.LlmProvider.chat(state1, "Merhaba, nasılsın?")
IO.inspect(result1, label: "Chat 1")

if rest != [] do
  [agent_id2 | _] = rest
  state2 = Modus.Simulation.Agent.get_state(agent_id2)
  IO.puts("\nAgent 2: #{state2.name} (#{state2.occupation})")
  result2 = Modus.Intelligence.LlmProvider.chat(state2, "Merhaba, nasılsın?")
  IO.inspect(result2, label: "Chat 2")
end

config = Modus.Intelligence.LlmProvider.get_config()
IO.inspect(config, label: "LLM Config")
