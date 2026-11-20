## Exploit de la fx-991ES PLUS 2nd (CY-845) : Explication Pédagogique

### Introduction
Étudiez l’exploit de la fx-991ES PLUS 2nd (CY-845) pour comprendre comment exploiter ses vulnérabilités de manière éthique et sécurisée, **sans risque pour le matériel**.


## 1. La Machine : Composants

### CPU
Le cerveau de la calculatrice qui exécute les instructions.

### ROM (Mémoire en lecture seule)
Le programme gravé à l'usine, non modifiable, stocké en mémoire permanente.

### RAM (Mémoire temporaire)
La RAM est alimentée par une pile de batterie et conserve ses données même après un simple arrêt (ON). Pour effacer la RAM, il faut une réinitialisation (SHIFT 9 3 =) ou retirer la pile.

### Écran LCD
Affiche les résultats et les messages.


## 2. Quand on Tape : Les Tokens

Chaque touche envoie un *token* (1 ou 2 octets) dans la ligne d'entrée (`0x8154`). Cette ligne a une limite de 99 octets. Si on dépasse cette limite, un bug survient.

### Découplage du curseur et Overflow
L'éditeur de la calculatrice perd le contrôle de la longueur de la ligne d'entrée. Au 100ᵉ octet, la copie de sauvegarde (`strcpy(0x81B8, 0x8154)`) tombe sur un octet NUL et s'auto-alimente, remplissant la RAM avec nos octets.


## 3. Le Bug : L'Overflow

### Résultat du Flood
Le flood de la RAM bloque la calculatrice : écran figé et tous les indicateurs s'allument.

### Status de l'exploit
Le flood est prouvé sur matériel réel. L'objectif suivant est de contrôler une cellule via `memcpy` à `0xF810`, étape non encore démontrée.


## 4. La Pile et le ROP

### La Pile
La pile contient des adresses de retour. En remplissant la pile avec des gadgets ROM (`0x3538`, `0x35BE`, `0x4D0E`), on peut forcer l'exécution de **code existant détourné**.


## 5. Les Touches Spéciales

Certaines touches n'envoient pas directement les octets attendus. Pour contourner cela, on utilise des techniques comme taper `5`, attendre le clignotement, puis utiliser les flèches (`▶`/`◀`) pour manipuler les symboles.


## 6. Expérience Réelle

### Étapes Clés
1. **LineIO : mode d'affichage en ligne (`SHIFT MODE 2`)** qui simplifie la saisie.
2. Envoyer des données au-delà de 99 octets pour déclencher l'overflow.
3. **Marqueurs visuels** : Les marqueurs `90×1` (`◄`) et `91ᵉ` (`X►`) indiquent que la ligne est pleine.
4. Envoyer un payload (`8 5` répété 50 fois) suivi de `AC ◀ =` pour déclencher le flood.

### Résultat
- Écran figé.
- Tous les indicateurs s'allument.
- La calculatrice est bloquée, mais la ROM reste intacte.


## 7. Sécurité et Éthique

- **Propriété personnelle** : Utilisation uniquement sur votre propre calculatrice.
- **Pas de destruction** : Étude uniquement du fonctionnement interne.
- **Le mask ROM ne peut pas être modifié : il est gravé à l'usine.**


## 8. Plan de Cours

### Objectifs
- Comprendre les composants internes.
- Identifier les vulnérabilités liées à l'overflow.
- Explorer la pile et le ROP.

### Durée : 60–90 minutes

### Démos
1. Présentation des composants.
2. Simulation de l'overflow.
3. Utilisation des marqueurs `90×1` et `91ᵉ`.

### Quiz
1. Qu'est-ce que la ROM dans une calculatrice ?
2. Pourquoi l'overflow est-il dangereux dans ce contexte ?
3. Qu'est-ce que la pile dans le contexte d'un ordinateur ?
4. Comment les gadgets sont-ils utilisés dans cet exploit ?
5. **Pourquoi la ROM reste-t-elle intacte après un flood ?**
6. Qu'indiquent les marqueurs `90×1` et `91ᵉ` ?

### Glossaire
- **ROM** : Mémoire en lecture seule (Read-Only Memory, programme gravé à l'usine).
- **RAM** : Mémoire temporaire alimentée par une pile.
- **Token** : Un petit morceau de données (1 ou 2 octets) envoyé par chaque touche.
- **Pile** : Structure de stockage des adresses de retour.
- **Gadget** : Fragment de code ROM exploitable.
- **ROP** : Programmation par Retour.
- **Flood** : Remplissage de la RAM bloquant la calculatrice.

