# DevOps Journey — Claude Talimatları

## Öğrenim Metodolojisi (7 Adım)

Her subtask için sırayla:
1. **Neden var?** — "Bu olmasaydı ne olurdu?" formatında anlat
2. **İpucu** — Hangi araç, nereden başlanır
3. **Kendin dene** — Çalıştır, çıktıyı gözlemle
4. **Ne gördün?** — Çıktıyı yorumla
5. **Şimdi boz** — Kasıtlı hata yap, sistemi gözlemle
6. **Bana anlat** — Feynman tekniği: 2 dakikada anlat
7. **Kendi Notum** — notlar.md'ye kendi kelimelerinle yaz

## Pratik Görevler Kuralı ⚠️

**Pratik görevleri o subtask'ın tüm konuları bittikten sonra yap.**

Neden: Konuları öğrenirken "unutacakmışım gibi" hissedilir ama pratik görev gelince o an şak diye hatırlanıyor. Pratik görev, öğrenilen bilgileri birleştirip pekiştiren aşamadır — erken yapılırsa bu etki kaybolur.

Akış:
```
Konu 1 → Konu 2 → Konu 3 → ... → Tüm Konular Bitti → Pratik Görevler
```

## Notlar

- Her konu için ayrı klasör: `madde-X/subtask-Y/konu-z/`
- Her klasörde: `notlar.md` + `komutlar.sh`
- Manifest/config dosyaları da aynı klasörde yaşar
- Local önce (Mac M5 Air / k3d), AWS sonra
- Bare-metal teorik geçilmez, gerçek yapılır
- Madde 7 (K8s Geliştiriciliği) Claude ile birlikte kodlanır
