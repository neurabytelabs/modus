defmodule Modus.I18n do
  @moduledoc """
  I18n — Internationalization module for MODUS worlds.
  Lingua Mundi: The world is born in a language.

  Provides language-specific name pools, catchphrases, season names,
  era names, system prompts, and UI labels.
  """

  @supported_languages ~w(en tr de fr es ja)

  @language_flags %{
    "en" => "🇬🇧",
    "tr" => "🇹🇷",
    "de" => "🇩🇪",
    "fr" => "🇫🇷",
    "es" => "🇪🇸",
    "ja" => "🇯🇵"
  }

  @language_labels %{
    "en" => "English",
    "tr" => "Türkçe",
    "de" => "Deutsch",
    "fr" => "Français",
    "es" => "Español",
    "ja" => "日本語"
  }

  # ── Name Pools ──────────────────────────────────────────

  @name_pools %{
    "en" => [
      "Alex",
      "Maya",
      "River",
      "Sage",
      "Finn",
      "Luna",
      "Kai",
      "Nova",
      "Zoe",
      "Atlas",
      "Iris",
      "Leo",
      "Mira",
      "Jude",
      "Aria",
      "Rowan",
      "Niko",
      "Ivy",
      "Theo",
      "Lila",
      "Orion",
      "Jade",
      "Ravi",
      "Suki",
      "Omar",
      "Nyla",
      "Ezra",
      "Cleo",
      "Amir",
      "Willow",
      "Bodhi",
      "Vera",
      "Kira",
      "Dara",
      "Ren",
      "Yara",
      "Soren",
      "Mika",
      "Inara",
      "Leila",
      "Zephyr",
      "Priya",
      "Hugo",
      "Amara",
      "Idris",
      "Noor",
      "Koda",
      "Lumi",
      "Astrid",
      "Nico"
    ],
    "tr" => [
      "Ayşe",
      "Mehmet",
      "Zeynep",
      "Ali",
      "Elif",
      "Emre",
      "Fatma",
      "Mustafa",
      "Defne",
      "Burak",
      "Yasemin",
      "Deniz",
      "Ebru",
      "Can",
      "Selin",
      "Baran",
      "Derya",
      "Hakan",
      "Merve",
      "Kerem",
      "Gizem",
      "Arda",
      "Naz",
      "Oğuz",
      "Esra",
      "Kaan",
      "İrem",
      "Serhan",
      "Ceren",
      "Volkan",
      "Başak",
      "Emir",
      "Asya",
      "Tuna",
      "Melisa",
      "Onur",
      "Ece",
      "Barış",
      "Pınar",
      "Tolga",
      "Leyla",
      "Mert",
      "Sibel",
      "Yiğit",
      "Damla",
      "Cem",
      "Nehir",
      "Alp",
      "Lale",
      "Koray"
    ],
    "de" => [
      "Hans",
      "Greta",
      "Friedrich",
      "Anna",
      "Wilhelm",
      "Elsa",
      "Karl",
      "Lena",
      "Maximilian",
      "Sophie",
      "Heinrich",
      "Marie",
      "Ludwig",
      "Clara",
      "Stefan",
      "Heidi",
      "Dieter",
      "Hanna",
      "Werner",
      "Liesel",
      "Otto",
      "Frieda",
      "Klaus",
      "Maren",
      "Rainer",
      "Ingrid",
      "Bernd",
      "Helga",
      "Günther",
      "Petra",
      "Horst",
      "Brigitte",
      "Volker",
      "Ursula",
      "Manfred",
      "Erika",
      "Dietrich",
      "Sabine",
      "Gerhard",
      "Monika",
      "Ernst",
      "Renate",
      "Albert",
      "Hildegard",
      "Konrad",
      "Irmgard",
      "Walter",
      "Christa",
      "Roland",
      "Gisela"
    ],
    "fr" => [
      "Pierre",
      "Marie",
      "Jean",
      "Claire",
      "Louis",
      "Amélie",
      "François",
      "Sophie",
      "Antoine",
      "Juliette",
      "Mathieu",
      "Camille",
      "Nicolas",
      "Élise",
      "Guillaume",
      "Margaux",
      "Étienne",
      "Chloé",
      "Henri",
      "Léa",
      "Jacques",
      "Manon",
      "Luc",
      "Émilie",
      "Rémy",
      "Fleur",
      "Alain",
      "Noémie",
      "Yves",
      "Colette",
      "Marcel",
      "Isabelle",
      "Olivier",
      "Brigitte",
      "Thierry",
      "Madeleine",
      "René",
      "Odette",
      "Bernard",
      "Geneviève",
      "Philippe",
      "Monique",
      "André",
      "Simone",
      "Gaston",
      "Hélène",
      "Lucien",
      "Claudine",
      "Maurice",
      "Céleste"
    ],
    "es" => [
      "Carlos",
      "María",
      "Pablo",
      "Lucía",
      "Miguel",
      "Ana",
      "Alejandro",
      "Carmen",
      "Diego",
      "Elena",
      "Javier",
      "Isabel",
      "Mateo",
      "Sofía",
      "Fernando",
      "Valentina",
      "Andrés",
      "Luna",
      "Rodrigo",
      "Camila",
      "Sebastián",
      "Daniela",
      "Emilio",
      "Paula",
      "Rafael",
      "Mariana",
      "Gabriel",
      "Jimena",
      "Tomás",
      "Catalina",
      "Santiago",
      "Alma",
      "Nicolás",
      "Renata",
      "Eduardo",
      "Victoria",
      "Marcos",
      "Paloma",
      "Ramón",
      "Inés",
      "Martín",
      "Esperanza",
      "Hugo",
      "Rosa",
      "Álvaro",
      "Pilar",
      "Iker",
      "Consuelo",
      "Adrián",
      "Dolores"
    ],
    "ja" => [
      "Haruto",
      "Yui",
      "Sota",
      "Hina",
      "Ren",
      "Aoi",
      "Yuto",
      "Sakura",
      "Minato",
      "Himari",
      "Riku",
      "Mei",
      "Kaito",
      "Rin",
      "Asahi",
      "Yuna",
      "Sora",
      "Akari",
      "Hinata",
      "Mio",
      "Yamato",
      "Kokona",
      "Itsuki",
      "Hana",
      "Takumi",
      "Koharu",
      "Hayato",
      "Saki",
      "Kota",
      "Riko",
      "Yuki",
      "Nana",
      "Ryota",
      "Miku",
      "Daichi",
      "Ayaka",
      "Shun",
      "Kanna",
      "Tsubasa",
      "Miyu",
      "Naoki",
      "Shiori",
      "Kenji",
      "Yuki",
      "Akira",
      "Misaki",
      "Ryo",
      "Haruka",
      "Shota",
      "Nanami"
    ]
  }

  # ── Catchphrase Pools ──────────────────────────────────

  @catchphrase_pools %{
    "en" => %{
      hunger_critical: [
        "My stomach speaks louder than my words!",
        "Food first, philosophy later.",
        "The belly knows no patience."
      ],
      action_success: [
        "Fortune favors the persistent!",
        "Another day, another victory!",
        "Hard work is its own reward."
      ],
      social_positive: [
        "Together we are the substance!",
        "A friend found is a world expanded.",
        "No soul walks alone by nature."
      ],
      joy: [
        "What a time to be alive!",
        "Joy shared is joy doubled!",
        "The world smiles with us today."
      ],
      sadness: [
        "Even this shall pass...",
        "Tears water the roots of wisdom.",
        "The heart remembers what the mind forgets."
      ],
      fear: [
        "Courage is fear that has said its prayers.",
        "We face the dark together.",
        "What we fear, we can overcome."
      ]
    },
    "tr" => %{
      hunger_critical: [
        "Aç ayı oynamaz!",
        "Karnım zil çalıyor!",
        "Aç tavuk kendini buğday ambarında sanır."
      ],
      action_success: [
        "Damlaya damlaya göl olur!",
        "Sabır acıdır, meyvesi tatlıdır.",
        "Bir elin nesi var, iki elin sesi var!"
      ],
      social_positive: [
        "Bir elin nesi var, iki elin sesi var!",
        "Dost kara günde belli olur.",
        "Komşu komşunun külüne muhtaçtır."
      ],
      joy: [
        "Bugün güzel bir gün!",
        "Hayat güzel, yaşamak güzel!",
        "Her şey gönlünce olsun!"
      ],
      sadness: [
        "Bu da geçer yahu...",
        "Her kışın bir baharı vardır.",
        "Ağlamayan çocuğa meme vermezler."
      ],
      fear: [
        "Korkunun ecele faydası yok.",
        "Nerede birlik, orada dirlik.",
        "Allah büyüktür."
      ]
    },
    "de" => %{
      hunger_critical: [
        "Ein leerer Magen hat keine Ohren!",
        "Hunger ist der beste Koch!",
        "Erst die Arbeit, dann das Vergnügen."
      ],
      action_success: [
        "Übung macht den Meister!",
        "Wer wagt, gewinnt!",
        "Steter Tropfen höhlt den Stein."
      ],
      social_positive: [
        "Zusammen sind wir stark!",
        "Geteilte Freude ist doppelte Freude.",
        "Ein guter Nachbar ist besser als ein ferner Freund."
      ],
      joy: [
        "Was für ein wunderbarer Tag!",
        "Das Leben ist schön!",
        "Man lebt nur einmal!"
      ],
      sadness: [
        "Auch das geht vorbei...",
        "Nach dem Regen kommt Sonnenschein.",
        "Die Zeit heilt alle Wunden."
      ],
      fear: [
        "Mut ist nicht die Abwesenheit von Angst.",
        "Gemeinsam schaffen wir das!",
        "Es wird schon werden."
      ]
    },
    "fr" => %{
      hunger_critical: [
        "Ventre affamé n'a point d'oreilles!",
        "La faim chasse le loup du bois.",
        "Il faut manger pour vivre."
      ],
      action_success: [
        "Petit à petit, l'oiseau fait son nid!",
        "C'est en forgeant qu'on devient forgeron.",
        "La persévérance vient à bout de tout."
      ],
      social_positive: [
        "L'union fait la force!",
        "Un ami est un trésor.",
        "Qui se ressemble s'assemble."
      ],
      joy: [
        "Quelle belle journée!",
        "La vie est belle!",
        "Carpe diem!"
      ],
      sadness: [
        "Cela aussi passera...",
        "Après la pluie, le beau temps.",
        "Le temps guérit toutes les blessures."
      ],
      fear: [
        "Le courage n'est pas l'absence de peur.",
        "Ensemble, nous sommes forts!",
        "Tout ira bien."
      ]
    },
    "es" => %{
      hunger_critical: [
        "¡Barriga llena, corazón contento!",
        "A buen hambre, no hay pan duro.",
        "¡Tengo un hambre que no veo!"
      ],
      action_success: [
        "¡Poco a poco se va lejos!",
        "El que la sigue, la consigue.",
        "No hay mal que por bien no venga."
      ],
      social_positive: [
        "¡La unión hace la fuerza!",
        "Dime con quién andas y te diré quién eres.",
        "Un amigo en la necesidad es un amigo de verdad."
      ],
      joy: [
        "¡Qué día tan maravilloso!",
        "¡La vida es bella!",
        "¡A vivir que son dos días!"
      ],
      sadness: [
        "Esto también pasará...",
        "Después de la tormenta viene la calma.",
        "El tiempo todo lo cura."
      ],
      fear: [
        "El valiente vive hasta que el cobarde quiere.",
        "¡Juntos somos más fuertes!",
        "Todo saldrá bien."
      ]
    },
    "ja" => %{
      hunger_critical: [
        "腹が減っては戦はできぬ！",
        "花より団子！",
        "空腹は最高の調味料。"
      ],
      action_success: [
        "継続は力なり！",
        "七転び八起き！",
        "石の上にも三年。"
      ],
      social_positive: [
        "一人より二人！",
        "持つべきものは友。",
        "和を以て貴しとなす。"
      ],
      joy: [
        "なんて素晴らしい日だ！",
        "人生は美しい！",
        "笑う門には福来たる！"
      ],
      sadness: [
        "これもまた過ぎ去る...",
        "雨降って地固まる。",
        "明けない夜はない。"
      ],
      fear: [
        "案ずるより産むが易し。",
        "一致団結！",
        "なんとかなる。"
      ]
    }
  }

  # ── Season Names ────────────────────────────────────────

  @season_names %{
    "en" => %{
      spring: "🌸 Spring has arrived!",
      summer: "☀️ Summer blazes!",
      autumn: "🍂 Autumn descends!",
      winter: "❄️ Winter grips the world!"
    },
    "tr" => %{
      spring: "🌸 Bahar geldi!",
      summer: "☀️ Yaz başladı!",
      autumn: "🍂 Sonbahar geldi!",
      winter: "❄️ Kış kapıda!"
    },
    "de" => %{
      spring: "🌸 Der Frühling ist da!",
      summer: "☀️ Sommer ist gekommen!",
      autumn: "🍂 Der Herbst ist da!",
      winter: "❄️ Der Winter hat begonnen!"
    },
    "fr" => %{
      spring: "🌸 Le printemps est arrivé!",
      summer: "☀️ L'été brûle!",
      autumn: "🍂 L'automne descend!",
      winter: "❄️ L'hiver s'installe!"
    },
    "es" => %{
      spring: "🌸 ¡Llegó la primavera!",
      summer: "☀️ ¡El verano arde!",
      autumn: "🍂 ¡Llegó el otoño!",
      winter: "❄️ ¡El invierno llega!"
    },
    "ja" => %{spring: "🌸 春が来た！", summer: "☀️ 夏が始まった！", autumn: "🍂 秋が来た！", winter: "❄️ 冬が来た！"}
  }

  # ── Era Names ───────────────────────────────────────────

  @era_names %{
    "en" => %{
      founding: "The Founding",
      famine: "The Great Famine",
      expansion: "The Expansion",
      golden_age: "The Golden Age",
      renaissance: "The Renaissance",
      conflict: "Age of Conflict"
    },
    "tr" => %{
      founding: "Kuruluş Çağı",
      famine: "Büyük Kıtlık",
      expansion: "Genişleme Dönemi",
      golden_age: "Altın Devir",
      renaissance: "Yeniden Doğuş",
      conflict: "Çatışma Çağı"
    },
    "de" => %{
      founding: "Die Gründung",
      famine: "Die Große Hungersnot",
      expansion: "Die Expansion",
      golden_age: "Das Goldene Zeitalter",
      renaissance: "Die Renaissance",
      conflict: "Zeitalter der Konflikte"
    },
    "fr" => %{
      founding: "La Fondation",
      famine: "La Grande Famine",
      expansion: "L'Expansion",
      golden_age: "L'Âge d'Or",
      renaissance: "La Renaissance",
      conflict: "L'Âge des Conflits"
    },
    "es" => %{
      founding: "La Fundación",
      famine: "La Gran Hambruna",
      expansion: "La Expansión",
      golden_age: "La Edad de Oro",
      renaissance: "El Renacimiento",
      conflict: "Era de Conflictos"
    },
    "ja" => %{
      founding: "創設の時代",
      famine: "大飢饉",
      expansion: "拡大の時代",
      golden_age: "黄金時代",
      renaissance: "復興の時代",
      conflict: "争いの時代"
    }
  }

  # ── System Prompt Templates ────────────────────────────

  @language_instructions %{
    "en" => "Always respond in English.",
    "tr" => "Her zaman Türkçe yanıt ver.",
    "de" => "Antworte immer auf Deutsch.",
    "fr" => "Réponds toujours en français.",
    "es" => "Responde siempre en español.",
    "ja" => "常に日本語で回答してください。"
  }

  @identity_templates %{
    "en" => "You are {name}, living as a {occupation}.",
    "tr" => "Sen {name}, {occupation} olarak yaşayan bir varlıksın.",
    "de" => "Du bist {name}, du lebst als {occupation}.",
    "fr" => "Tu es {name}, tu vis en tant que {occupation}.",
    "es" => "Eres {name}, vives como {occupation}.",
    "ja" => "あなたは{name}、{occupation}として生きています。"
  }

  @conversation_instructions %{
    "en" => "Write the dialogue in English.",
    "tr" => "Diyaloğu Türkçe yaz.",
    "de" => "Schreibe den Dialog auf Deutsch.",
    "fr" => "Écris le dialogue en français.",
    "es" => "Escribe el diálogo en español.",
    "ja" => "対話を日本語で書いてください。"
  }

  # ── Public API ──────────────────────────────────────────

  @doc "List of supported language codes."
  @spec supported_languages() :: [String.t()]
  def supported_languages, do: @supported_languages

  @doc "Get flag emoji for a language code."
  @spec flag(String.t()) :: String.t()
  def flag(lang), do: Map.get(@language_flags, lang, "🇬🇧")

  @doc "Get label for a language code."
  @spec label(String.t()) :: String.t()
  def label(lang), do: Map.get(@language_labels, lang, "English")

  @doc "Get language options for UI as [{code, flag, label}]."
  @spec language_options() :: [{String.t(), String.t(), String.t()}]
  def language_options do
    Enum.map(@supported_languages, fn lang ->
      {lang, flag(lang), label(lang)}
    end)
  end

  @doc "Get a random name for the given language."
  @spec random_name(String.t()) :: String.t()
  def random_name(lang) do
    pool = Map.get(@name_pools, lang, @name_pools["en"])
    Enum.random(pool)
  end

  @doc "Get name pool for a language."
  @spec names(String.t()) :: [String.t()]
  def names(lang), do: Map.get(@name_pools, lang, @name_pools["en"])

  @doc "Get catchphrase templates for a language."
  @spec catchphrases(String.t()) :: map()
  def catchphrases(lang), do: Map.get(@catchphrase_pools, lang, @catchphrase_pools["en"])

  @doc "Get season toast for a language and season."
  @spec season_toast(String.t(), atom()) :: String.t()
  def season_toast(lang, season) do
    lang_seasons = Map.get(@season_names, lang, @season_names["en"])
    Map.get(lang_seasons, season, "The season changes!")
  end

  @doc "Get era name for a language and era type."
  @spec era_name(String.t(), atom()) :: String.t()
  def era_name(lang, era_type) do
    lang_eras = Map.get(@era_names, lang, @era_names["en"])
    Map.get(lang_eras, era_type, to_string(era_type))
  end

  @doc "Get language instruction for system prompt."
  @spec language_instruction(String.t()) :: String.t()
  def language_instruction(lang),
    do: Map.get(@language_instructions, lang, @language_instructions["en"])

  @doc "Get identity template for system prompt."
  @spec identity_prompt(String.t(), String.t(), String.t()) :: String.t()
  def identity_prompt(lang, name, occupation) do
    template = Map.get(@identity_templates, lang, @identity_templates["en"])

    template
    |> String.replace("{name}", name)
    |> String.replace("{occupation}", to_string(occupation))
  end

  @doc "Get conversation language instruction."
  @spec conversation_instruction(String.t()) :: String.t()
  def conversation_instruction(lang),
    do: Map.get(@conversation_instructions, lang, @conversation_instructions["en"])

  @doc "Get the current world language from RulesEngine."
  @spec current_language() :: String.t()
  def current_language do
    try do
      Modus.Simulation.RulesEngine.get(:language) || "en"
    catch
      _, _ -> "en"
    end
  end
end
