# 📝 Notlar

## Neden var?
<!-- Bu konuyu 3-4 cümleyle anlat. "Bu olmasaydı ne olurdu?" formatında. -->
K8s'de yüzlerce pod, nod ve servis var. Bunları kim yönetiyor? Kim "bu pod şu node'a gitsin" diyor? Kim "bu pod öldü, yenisini aç" diyor? İşte Control PLane bunları halleder. Olmasa cluster kör uçar. Podlar nereye gideceğini bilemez, arızalar fark edilmez, hiç bir şey orkestre edilemez.

4 Temel Bileşeni vardır:
1- kube-apiserver-> Tüm K8s iletişiminin geçtiği tek kapı. kubectl komutunun, bir podun bir başka pod'a sorması, her şey buradan geçer REST-API sunar.
2- etcd->Cluster'ın beyni. Tüm state burada, hangi pod nerede, hangi node ayakta, hangi config ne, etcd ölürse cluster ne yapacağını unutur
3- kube-scheduler-> Yeni pod geldi, hangi node'a gitsin? CPU/memeroy'e bakar, affinity kurallarına bakar, en uygun node'u seçer.
4- kube-controller-manager-> "Istenen durum" ile "mevcut durumu" karsılastırır. 3 replica istiyorsun ama 2 var -> yenisini aç. Node öldü -> podları taşı. Sürekli döngüde çalışır.

Örnek soru: 
kube-apiserver çökerse clustera ne olur? Çalışan podlar ölür mü?
Cevap:
Hayır çalışan podlar ölmez kubelet node üzerinde podları ayakta tutar ancak node/cluster içinde ki iletişim durur. Eğer inbox/outbox gibi bir mekanizma varsa iletişim durduğu için cevap alamayacağından sahte çöküş görüntüleriyle de karşılaşabiliriz.
Fakat şunlar durur:
- kubectl komutları çalısmaz
- yeni pod açılamaz, scaling yapılamaz
- Controller-manager ve scheduler da apiserver üzerinden konuşur, onlarda kör kalır
- Servis discovery etkilenebilir (yeni endpointler kayıt edilemez)

## Anahtar Kavramlar
<!-- Öğrendiğin kavramları kendi cümlelerinle yaz -->
- 

## Kendi Notum
<!-- Bunu yarın takım arkadaşına 2 dakikada nasıl anlatırdın? -->

## Karşılaştığım Hatalar
<!-- Bozma senaryolarında ne oldu? Hata mesajı neydi? Neden oldu? -->

## Kaynaklar
<!-- Faydalı bulduğun linkler -->
- 
