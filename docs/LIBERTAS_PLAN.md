Harika bir aşama. v0.4.0 Cerebro'nun başarısı üzerine inşa edilecek **v0.5.0 Libertas**, MODUS evrenindeki ajanların "sadece konuşan" botlardan, "çevresinin farkında olan ve eyleme geçebilen" varlıklara dönüşeceği kritik köprü sürümüdür.

Spinoza'nın *Libertas* (Özgürlük) kavramı, "zorunluluğun bilincine varmak"tır. Ajanlar artık simülasyonun zorunluluklarını (arazi, enerji, sosyal ağ) bilecek ve buna göre tepki verecektir.

İşte v0.5.0 Libertas için hazırladığım detaylı geliştirme planı:

---

# 🏛️ MODUS v0.5.0 Libertas — Geliştirme Planı
**Odak:** Agent Protocol Bridge (Ajan Protokol Köprüsü)
**Tema:** Bağlamsal Farkındalık ve Niyet Ayrıştırma (Contextual Awareness & Intent Parsing)

## 1. Özellik Dağılımı (Feature Breakdown)

Bu sürümde ajanların "Kör Kahin" modundan çıkıp, simülasyon verisine doğrudan erişebilen "Gören Filozof" moduna geçmesini sağlayacağız.

### F1: Perception Engine (Algı Motoru)
Ajanın anlık fiziksel ve içsel durumunu sorgulanabilir bir veri yapısına dönüştürür.
*   **Açıklama:** Ajanın koordinatları, enerji seviyesi (Conatus), baskın duygusu (Affect) ve görüş menzilindeki diğer ajanları/objeleri toplayan modül.
*   **Modüller:**
    *   `Modus.Mind.Perception`: Ana toplayıcı modül.
    *   `Modus.World.Spatial`: `get_nearby_entities(agent_id, radius)` fonksiyonunu içerir.
*   **API İmzası:** `Perception.snapshot(agent_id) :: %PerceptionSchema{}`
*   **Tahmini Efor:** 3 Gün
*   **Test:** Belirli koordinattaki ajanın yanındaki nesneleri doğru raporladığını doğrulayan unit testler.

### F2: Social Graph Query (Sosyal Çizge Sorgusu)
ETS tabanlı sosyal ağın LLM bağlamına enjekte edilebilir hale gelmesi.
*   **Açıklama:** Ajanın konuştuğu kişiyle olan ilişkisini (Yabancı, Tanıdık, Dost) ve çevresindeki diğer ajanların sosyal statüsünü sorgular.
*   **Modüller:**
    *   `Modus.Social.Insight`: ETS sorgularını anlamlı metin özetlerine çevirir.
*   **API İmzası:** `Insight.report_relationship(source_id, target_id) :: {:ok, relationship_level, memory_summary}`
*   **Tahmini Efor:** 2 Gün
*   **Test:** İki ajan arasındaki ilişki seviyesinin doğru string formatına ("Close Friend" vb.) dönüştürüldüğünün testi.

### F3: Intent Parser (Niyet Ayrıştırıcı)
Kullanıcı mesajlarını ham metinden yapılandırılmış komutlara dönüştüren ara katman.
*   **Açıklama:** Kullanıcının yazdığı metni analiz ederek bunun bir "Sohbet", "Bilgi Sorgusu" (Neredeyim?) veya "Eylem Emri" (Kuzeye git) olup olmadığını belirler.
*   **Modüller:**
    *   `Modus.Protocol.Interpreter`: Hafif siklet bir LLM çağrısı (veya regex/keyword hibrit yapı) ile niyeti sınıflandırır.
*   **API İmzası:** `Interpreter.parse(user_text) :: {:chat, text} | {:query, :location} | {:command, :move, direction}`
*   **Tahmini Efor:** 4 Gün
*   **Test:** "Neredesin?" sorusunun `{:query, :location}` olarak parse edildiğini doğrulayan senaryolar.

### F4: Dynamic Context Injector (Dinamik Bağlam Enjektörü)
LLM System Prompt'unun statik halden dinamik hale geçişi.
*   **Açıklama:** F1 ve F2'den gelen verileri alıp, ajanın System Prompt'una "Şu an (10,40) noktasındasın. Enerjin %80. Karşındaki kişi senin dostun." şeklinde enjekte eder.
*   **Modüller:**
    *   `Modus.Mind.ContextBuilder`: Template motoru.
*   **API İmzası:** `ContextBuilder.hydrate_prompt(agent_struct, perception_data)`
*   **Tahmini Efor:** 3 Gün
*   **Test:** Prompt çıktısının beklenen dinamik verileri içerdiğinin string match testi.

### F5: Feedback Loop Integration (Geri Bildirim Döngüsü)
Ajanın eylemlerinin simülasyona yansıması ve sonucun sohbete dönmesi.
*   **Açıklama:** Eğer niyet bir komut ise (örn: Hareket), bu komutu simülasyonda uygular (`Modus.Simulation.Action`) ve sonucunu ("Kuzeye gidildi") ajanın hafızasına/sohbetine yazar.
*   **Modüller:**
    *   `Modus.Protocol.Bridge`: Orchestrator (Orkestra Şefi).
*   **API İmzası:** `Bridge.execute_intent(agent_id, intent_struct)`
*   **Tahmini Efor:** 4 Gün

---

## 2. Sprint Yapısı (2 Hafta)

**Hafta 1: Algı ve Anlamlandırma (The Eye & The Mind)**
*   **Pazartesi-Salı:** F1 (Perception Engine) geliştirimi. `Modus.World` entegrasyonu.
*   **Çarşamba:** F2 (Social Graph Query). ETS tablolarının okunabilir formatlara çevrilmesi.
*   **Perşembe-Cuma:** F4 (Dynamic Context Injector). Antigravity ağ geçidinde prompt şablonlarının güncellenmesi.
*   *Çıktı:* Ajanlar artık çevrelerini "biliyor" ama henüz kullanıcı komutlarını yapısal olarak ayırmıyor.

**Hafta 2: Protokol ve Köprü (The Bridge)**
*   **Pazartesi-Salı:** F3 (Intent Parser). Kullanıcı girdilerinin sınıflandırılması için LLM zinciri kurulumu.
*   **Çarşamba-Perşembe:** F5 (Feedback Loop). Komutların simülasyona gönderilmesi ve sonucun chat arayüzüne basılması.
*   **Cuma:** Entegrasyon testleri, POP 10 yük testi (yeni sorguların performansa etkisi) ve Demo hazırlığı.
*   *Çıktı:* Tam fonksiyonel v0.5.0 Libertas.

---

## 3. Teknik Mimari

Mevcut `Modus.Mind` yapısını, **Input -> Processing -> Output** akışından **Input -> Context Enrichment -> Intent Parsing -> Execution -> Output** akışına eviriyoruz.

**Yeni Veri Akışı:**
1.  **User Input:** "Sağındaki ağaca git."
2.  **Interpreter (`Modus.Protocol.Interpreter`):** Girdiyi analiz eder -> `{:command, :move_to_object, :tree, :right}`
3.  **Context Builder (`Modus.Mind.ContextBuilder`):**
    *   `Perception`: Sağda ağaç var mı? (Evet, ID: 55)
    *   `Self`: Enerjim var mı? (Evet)
4.  **LLM Generation:** Ajanın karakterine uygun yanıt üretilir: "Tamam, sağdaki yaşlı meşeye doğru yürüyorum."
5.  **Action Dispatcher (`Modus.Simulation.Action`):** Simülasyon motoruna `move_agent(id, target_id: 55)` sinyali gönderilir.

**Kritik Entegrasyon Noktası:**
`Antigravity` modülü, sadece text üretmek yerine artık `structured_output` (JSON mode) veya function calling benzeri bir yapı ile niyeti kesinleştirmelidir.

---

## 4. Risk Değerlendirmesi

1.  **Gecikme (Latency):**
    *   *Risk:* Her mesajda önce Intent Parsing, sonra Response Generation yapmak (2 LLM çağrısı) sohbeti yavaşlatabilir.
    *   *Önlem:* Intent Parsing için çok hızlı/küçük modeller (örn: GPT-4o-mini, Gemini Flash veya lokal küçük modeller) kullanılmalı. Ana karakter yanıtı için büyük model kullanılabilir.
2.  **Halüsinasyon (Hallucination):**
    *   *Risk:* Ajanın "Kuzeye gidiyorum" deyip simülasyonda hareket etmemesi (Action Dispatcher hatası).
    *   *Önlem:* "Grounding" mekanizması. Ajanın söylediği eylem ile simülasyona giden komut sıkı sıkıya bağlanmalı.
3.  **Token Maliyeti:**
    *   *Risk:* Her prompt'a tüm çevre bilgisini ve sosyal grafiği gömmek context'i şişirir.
    *   *Önlem:* `ContextBuilder` içinde filtreleme yapılmalı. Sadece en yakın 3 obje ve aktif konuşulan kişi prompt'a girmeli.

---

## 5. Başarı Kriterleri (Demo İçin)

v0.5.0 Libertas demosunda şunları gördüğümüzde başarılı sayılacağız:
1.  **Konumsal Farkındalık:** Kullanıcı "Neredesin?" dediğinde, ajan "Ormanın kenarındayım, (120, 50) koordinatındayım ve yanımda Agent X var" diyebilmeli (uydurma değil, gerçek veri).
2.  **Sosyal Hafıza:** Kullanıcı "Ahmet'i tanıyor musun?" dediğinde, ETS grafiğine bakıp "Evet, o benim yakın arkadaşım" veya "Hayır, sadece bir kez gördüm" diyebilmeli.
3.  **Eylem-Söz Uyumu:** Kullanıcı "Dur ve dinlen" dediğinde, ajanın durumu `Idle`'a geçmeli ve enerjisi artmaya başlamalı.

---

## 6. Gelecek Sürümlerle Bağlantı

*   **v0.6.0 Imperium (Commands):** Libertas'ta kurduğumuz `Intent Parser` ve `Action Dispatcher`, v0.6'da çok daha karmaşık komut setlerine (Örn: "Git, X'i bul, ona şu mesajı ilet ve geri gel") izin verecek. v0.5 sadece "tek adımlı" eylemleri ve sorguları çözer.
*   **v0.7.0 Societas (Teams):** Sosyal farkındalık modülü (`Insight`), v0.7'de ajanların kendi aralarında takım kurması ve grupça hareket etmesi için temel oluşturacak.

Bu plan, MODUS'u bir "sohbet botu"ndan yaşayan, nefes alan bir "dijital organizma"ya dönüştürecektir. Onayınızla Sprint 1'i başlatıyorum.