#!/bin/bash
set -e

echo "🌌 MODUS — İlk Kurulum"
echo "========================"
echo ""

# 1. Docker check
if ! command -v docker &> /dev/null; then
    echo "❌ Docker bulunamadı. Önce Docker Desktop'ı kurun."
    exit 1
fi

if ! docker info &> /dev/null; then
    echo "❌ Docker daemon çalışmıyor. Docker Desktop'ı açın."
    exit 1
fi

echo "✅ Docker hazır"

# 2. Create data directories
mkdir -p data/db data/ollama
echo "✅ Data dizinleri oluşturuldu"

# 3. Build and start containers
echo ""
echo "📦 Container'lar build ediliyor..."
docker compose up -d --build

# 4. Wait for services
echo ""
echo "⏳ Servisler başlatılıyor..."
sleep 10

# 5. Install deps and setup DB
echo ""
echo "📚 Bağımlılıklar yükleniyor..."
docker compose exec modus-app mix deps.get
docker compose exec modus-app mix ecto.create
echo "✅ Database oluşturuldu"

# 6. Pull LLM model (background)
echo ""
echo "🧠 LLM modeli indiriliyor (arka planda)..."
echo "   Bu biraz sürebilir (~2GB). İlerlemeyi 'make logs' ile takip edin."
docker compose exec -d modus-llm ollama pull llama3.2:3b-instruct-q4_K_M

# 7. Run tests
echo ""
echo "🧪 Testler çalıştırılıyor..."
docker compose exec modus-app mix test

echo ""
echo "════════════════════════════════════════"
echo "✅ MODUS hazır!"
echo ""
echo "   🌐 http://localhost:4000"
echo "   📊 http://localhost:4000/dev/dashboard"
echo ""
echo "   Komutlar:"
echo "   make up      — başlat"
echo "   make down    — durdur"
echo "   make test    — testleri çalıştır"
echo "   make logs    — logları izle"
echo "   make clean   — her şeyi sil"
echo "════════════════════════════════════════"
