# FhemLogiLinkPDU8P01
FHEM Modul for LogiLink PDU8P01 und da vermutlich baugleich für die Intellinet 163682.

## Installation

### Modul
Das Modul kann (solange es noch nicht im FHEM svn verteilt wird) mit
```
update all https://markusfeist.github.io/FhemMobileAlerts/repository/master/controls_mobilealerts.txt
```
beziehen.

### Einrichtung
Das Modul legt man dann im FHEM mit dem Befehl
```
define <name> LLPDU8P01 <IP/Hostname> <Pollintervall> <Username> <Password>
```
an. Also z.B.:
```
define PDU1 LLPDU8P01 192.168.1.3 30 admin admin
```

### Module für die Steckdosen
Module für die Steckdosen legt man am besten mit dem Set-Befehl `autocreate` an.

## Fehlerbehandlung
Sollten generelle Probleme mit dem Modul auftauschen, brauche ich für eine Fehleranlyse das FHEM-Protokoll. Ggf. mit Loglevel 4 oder 5.

## Offene Punkte
Folgende Punkte sind noch offen:
* Setzen der Konfiguration ermöglichen
* Auslesen und setzen der Grenzwerte ermöglichen 
* Erweiterung um das UDP Protokoll (inklusive Mastermodul um mehr wie eine PDU gleichzeitig abzufragen (weniger Timer bei vielen PDUs))

## Lizenz
Ich veröffentliche hier das FHEM Modul unter der GPL V2 siehe auch [LICENSE](LICENSE).