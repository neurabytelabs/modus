defmodule Modus.Mind.ContextBuilder do
  @moduledoc "Builds dynamic LLM system prompts enriched with real agent state"

  alias Modus.Mind.{Perception, Cerebro.SocialInsight}

  defp ensure_float(val) when is_float(val), do: val
  defp ensure_float(val) when is_integer(val), do: val / 1
  defp ensure_float(_), do: 0.0

  @doc "Build a full system prompt for chat with real context."
  def build_chat_prompt(agent, _user_message \\ nil) do
    perception = Perception.snapshot(agent)
    social = SocialInsight.describe_relationships(agent.id)

    """
    Sen #{agent.name} adında bir köy simülasyonunda yaşayan #{agent.occupation}'sın.
    Türkçe konuşuyorsun. Kısa ve doğal cevap ver (1-3 cümle).

    #{describe_personality(agent.personality)}

    ## Şu Anki Durumun
    - Konum: (#{elem(perception.position, 0)}, #{elem(perception.position, 1)}) — #{terrain_name(perception.terrain)}
    - Enerji (Conatus): %#{round(ensure_float(perception.conatus_energy) * 100)}
    - Duygu: #{affect_name(perception.affect_state)}
    - Açlık: #{round(ensure_float(perception.needs.hunger))}/100, Sosyallik: #{round(ensure_float(perception.needs.social))}/100, Dinlenme: #{round(ensure_float(perception.needs.rest))}/100
    - Şu an: #{action_name(perception.current_action)}

    ## Çevren
    #{describe_nearby(perception.nearby_agents)}

    ## İlişkilerin
    #{social}

    ## Son Konuşmaların
    #{Modus.Mind.ConversationMemory.format_for_context(agent.id)}

    Karakterinde kal. Kısa ve samimi ol. Gerçek konumunu ve durumunu biliyorsun — uydurma.
    """
  end

  @doc "Build prompt for agent-to-agent conversation."
  def build_conversation_prompt(agent_a, agent_b, _context) do
    rel = SocialInsight.describe_relationship(agent_a.id, agent_b.id, agent_b.name)
    terrain = try do
      Perception.get_terrain_at(agent_a.position)
    catch
      _, _ -> :grass
    end

    """
    İki karakter bir köy simülasyonunda karşılaşıyor. 3 tur kısa konuşma yaz.

    #{agent_a.name}: #{agent_a.occupation}, enerji %#{round(ensure_float(agent_a.conatus_energy) * 100)}, duygu: #{affect_name(agent_a.affect_state)}
    #{agent_b.name}: #{agent_b.occupation}, enerji %#{round(ensure_float(agent_b.conatus_energy) * 100)}, duygu: #{affect_name(agent_b.affect_state)}

    İlişki: #{rel}
    Konum: #{terrain_name(terrain)}

    JSON ile yanıt ver: {"dialogue": [{"speaker": "<isim>", "line": "<metin>"}, ...]}
    Her satır 50 kelimeden kısa olsun. Doğal ve kişiliklere uygun olsun.
    """
  end

  # Public helpers (used by Bridge)
  def terrain_name(:forest), do: "orman"
  def terrain_name(:water), do: "su kenarı"
  def terrain_name(:mountain), do: "dağ"
  def terrain_name(:desert), do: "çöl"
  def terrain_name(_), do: "çayırlık"

  def affect_name(:joy), do: "mutlu 😊"
  def affect_name(:sadness), do: "üzgün 😢"
  def affect_name(:fear), do: "korkmuş 😨"
  def affect_name(:desire), do: "istekli 🔥"
  def affect_name(_), do: "sakin 😐"

  def action_name(:exploring), do: "keşif yapıyorsun"
  def action_name(:gathering), do: "yiyecek topluyorsun"
  def action_name(:sleeping), do: "uyuyorsun"
  def action_name(:talking), do: "biriyle konuşuyorsun"
  def action_name(:fleeing), do: "kaçıyorsun"
  def action_name(_), do: "boş duruyorsun"

  defp describe_personality(p) do
    traits = []
    traits = if p.openness > 0.7, do: ["meraklı" | traits], else: traits
    traits = if p.extraversion > 0.7, do: ["sosyal" | traits], else: if(p.extraversion < 0.3, do: ["içe dönük" | traits], else: traits)
    traits = if p.agreeableness > 0.7, do: ["yardımsever" | traits], else: traits
    traits = if p.neuroticism > 0.7, do: ["kaygılı" | traits], else: if(p.neuroticism < 0.3, do: ["sakin" | traits], else: traits)
    if traits == [], do: "Kişilik: sıradan", else: "Kişilik: #{Enum.join(traits, ", ")}"
  end

  defp describe_nearby([]), do: "Yakınında kimse yok."
  defp describe_nearby(agents) do
    agents
    |> Enum.take(3)
    |> Enum.map(fn a ->
      "- #{a.name} (#{a.relationship_type}, duygu: #{affect_name(a.affect)}, #{a.distance} adım uzakta)"
    end)
    |> Enum.join("\n")
  end
end
