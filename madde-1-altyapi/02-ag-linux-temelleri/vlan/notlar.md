# 📝 Notlar

## Neden var?
Fiziksel olarak aynı switche bağlı cihazlar varsayılan olarak birbirini görebilirler. Fabrika örneğinde olduğu gibi (ip-subnettingte geçiyor) tüm çalışanlar aynı koridorda, birbirinin masasına bakıyor. Vlan olmasa storage trafiği, mgmt trafiği birbirini görür, güvenlik açığı + performans kaybı olur. Vlan fiziksel donanımı değiştirmeden mantıksal izolasyon sağlar. Yani her bir grup masada çalışan kişiler için tek tek switch almak yerine bir switchte vlanlar oluşturup mantıksal izolasyon sağlarız. Açılımı zaten Virtual LAN = VLAN dır. Burada 2 temel kavram var, access port ve trunk port.
Farkı şudur, access port tek vlan gerektiren durumlar içindir, trunk port ise birden fazla Vlan grubu olacağı durumlardadır.

Örneğin şirkette çalışanların cihazları ile test makinesi aynı switchte ama ben bunların birbirine erişmesini istemiyorum, bu sebeple bir access port oluşturup test makinesi ile çalışanları birbirinden ayırabilirim. Ama bir cluster'ım var ve etcd/storage, mgmt trafiği, k8s-nodes trafiği var ve çok fazla varlık MetalLB aracılığı ile ip alıp iç k8s networkünde varoluyor. Bu çokluğu tek bir vlanla yönetemeyiz, bu sebeple trunk port yaparız ve her bir gruba bir Vlan grubu atarız:
VLAN 10 → mgmt      (10.0.1.0/28)
VLAN 20 → k8s-nodes (10.0.2.0/24)
VLAN 30 → storage   (10.0.3.0/29)
Hem subnet olarak birbirlerinden izole olurlar hemde switchten de ayırdığımız için varsayılan olarak birbirlerini görüp ulaşmaları neredeyse imkansızdır.

## Anahtar Kavramlar
- VLAN: Aynı fiziksel switchte mantıksal izolasyon. Grup A grubu B'yi görmez.
- Access Port: Tek VLAN içindir, son kullanıcı cihazları buraya bağlanır, tag yok.
- Trunk Port: Birden fazla VLAN'ı taşır, her frame'e 802.1Q tag eklenir. Switch-switch veya switch-router arası.
- 802.1Q: VLAN tagging standardı, Ethernet frame'ine 4 byte tag eklenir, içinde VLAN ID var.
- Native VLAN: Trunk portta tag'siz gelen trafiğin hangi VLAN'a ait olduğunu belirler. Yanlış ayarlanırsa güvenlik açığı olur.

## Kendi Notum
Şöyle anlatırdım, diyelim ki aynı ofiste üç farklı ekip çalışıyor: backend, güvenlik ve DB ekibi. Hepsinin bilgisayarı aynı switche takılı ama sen backend'in güvenlik ekibinin trafiğini görmesini istemiyorsun. Switch başına ayrı switch koyamazsın çünkü maliyetli. O zaman VLAN açıyorsun, backend VLAN 10, güvenlik VLAN 20, DB VLAN 30. Fiziksel olarak aynı kablo, ama mantıksal olarak üç ayrı ağ. Access port her ekibin kendi masasına giden kablo, trunk port ise katlardaki switch'lerin birbirine bağlandığı ana hat, hepsini taşıması gerekiyor.

K8s'de de storage trafiği, mgmt trafiği ve pod trafiği aynı switche dayanıyor genellikle, VLAN olmasa Ceph replikasyonu yaptığında o trafik diğerleriyle karışır ve performans düşer.

## Karşılaştığım Hatalar
Fiziksel switch olmadığı için k3d ortamında VLAN pratiği yapılamadı. Teorik olarak geçtik. Gerçek lab ortamında en yaygın hata native VLAN mismatch'tir: iki switch arasındaki trunk portta native VLAN farklı ayarlanınca untagged trafik yanlış VLAN'a düşer ve ağ sessizce bozulur.

## Kaynaklar
- Cisco VLAN Configuration Guide: https://www.cisco.com/c/en/us/td/docs/switches/lan/catalyst9300/software/release/16-12/configuration_guide/vlan/b_1612_vlan_9300_cg.html
- IEEE 802.1Q standard açıklaması: https://en.wikipedia.org/wiki/IEEE_802.1Q
