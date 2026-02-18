defmodule Modus.I18nTest do
  use ExUnit.Case, async: true

  alias Modus.I18n

  test "supported_languages returns all 6 languages" do
    langs = I18n.supported_languages()
    assert length(langs) == 6
    assert "en" in langs
    assert "tr" in langs
    assert "de" in langs
    assert "fr" in langs
    assert "es" in langs
    assert "ja" in langs
  end

  test "flag returns correct emoji" do
    assert I18n.flag("en") == "🇬🇧"
    assert I18n.flag("tr") == "🇹🇷"
    assert I18n.flag("de") == "🇩🇪"
    assert I18n.flag("ja") == "🇯🇵"
    assert I18n.flag("unknown") == "🇬🇧"
  end

  test "label returns correct name" do
    assert I18n.label("en") == "English"
    assert I18n.label("tr") == "Türkçe"
    assert I18n.label("de") == "Deutsch"
  end

  test "language_options returns tuples" do
    opts = I18n.language_options()
    assert length(opts) == 6
    assert {"en", "🇬🇧", "English"} in opts
    assert {"tr", "🇹🇷", "Türkçe"} in opts
  end

  test "random_name returns a string" do
    for lang <- ~w(en tr de fr es ja) do
      name = I18n.random_name(lang)
      assert is_binary(name)
      assert String.length(name) > 0
    end
  end

  test "names returns pool for language" do
    tr_names = I18n.names("tr")
    assert "Ayşe" in tr_names
    assert "Mehmet" in tr_names
    assert length(tr_names) == 50

    de_names = I18n.names("de")
    assert "Hans" in de_names
  end

  test "catchphrases returns language-specific pools" do
    tr_pool = I18n.catchphrases("tr")
    assert is_map(tr_pool)
    assert Map.has_key?(tr_pool, :hunger_critical)
    assert "Aç ayı oynamaz!" in tr_pool.hunger_critical
  end

  test "season_toast returns localized toast" do
    assert I18n.season_toast("en", :spring) =~ "Spring"
    assert I18n.season_toast("tr", :spring) =~ "Bahar"
    assert I18n.season_toast("de", :winter) =~ "Winter"
    assert I18n.season_toast("ja", :summer) =~ "夏"
  end

  test "era_name returns localized era" do
    assert I18n.era_name("en", :founding) == "The Founding"
    assert I18n.era_name("tr", :founding) == "Kuruluş Çağı"
    assert I18n.era_name("de", :golden_age) == "Das Goldene Zeitalter"
    assert I18n.era_name("tr", :famine) == "Büyük Kıtlık"
  end

  test "language_instruction returns correct instruction" do
    assert I18n.language_instruction("en") =~ "English"
    assert I18n.language_instruction("tr") =~ "Türkçe"
    assert I18n.language_instruction("de") =~ "Deutsch"
  end

  test "identity_prompt interpolates name and occupation" do
    prompt = I18n.identity_prompt("tr", "Ayşe", "farmer")
    assert prompt =~ "Ayşe"
    assert prompt =~ "farmer"
    assert prompt =~ "varlıksın"

    prompt_en = I18n.identity_prompt("en", "Alex", "builder")
    assert prompt_en =~ "Alex"
    assert prompt_en =~ "builder"
  end

  test "conversation_instruction returns correct instruction" do
    assert I18n.conversation_instruction("tr") =~ "Türkçe"
    assert I18n.conversation_instruction("en") =~ "English"
  end
end
