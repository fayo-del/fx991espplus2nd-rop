# Test Runbook for CY-845 (2nd Edition) — Checklist en Français

## Préparation
1. **Réinitialisation** : Appuyez sur `[SHIFT] [9] [3] [=]` puis `[AC]` pour redémarrer l'appareil.
   *Note :* Vérifiez l'écran pour confirmer la réinitialisation.

2. **Mode LineIO** : Appuyez sur `[SHIFT] [MODE] [2]`.
   - Si l'écran affiche `Σ(` avec **boîtes aux coins** → LineIO n'a pas été activé.
   - Si l'écran affiche `Σ(` **sans boîtes** → LineIO a été activé.

## Étape 1 : Vérification de la surcharge
3. **Formule longue** : Tapez `X=Σ(X,1,1×10⁹` et appuyez sur `[=]`.
4. **Formule courte** : Re-tapez `X=Σ(X,1,1` puis appuyez sur `[CALC]` puis `[=]`.
   *Attendu* : **Erreur de syntaxe** s'affiche.
5. **Validation** : Appuyez sur `[▶]` pour sortir de l'erreur.
6. **Vérification de l'état** : Tapez `[1]` et attendez que le chiffre **ne s'affiche pas** à la première position.
   *Attendu* : Le chiffre `[1]` ne doit pas apparaître à l'écran.

## Étape 2 : Vérification du Hack #7
7. **Entrée d'un symbole** : Tapez `[5]` et attendez **2 à 3 clignotements** du curseur.
8. **Avancement du curseur** : Appuyez sur `[▶]` trois fois et notez les trois glyphes obtenus.
   *Attendu* : Les glyphes devraient être `[6]`, `[7]`, `[8]` si l'avancement est par octet.

## Étape 3 : Cibles d'octets
9. **Déplacement vers `0x4D`** : Appuyez sur `[▶]` 24 fois pour atteindre `0x4D`.
10. **Déplacement vers `0x0E`** : Appuyez sur `[◀]` 39 fois pour atteindre `0x0E`.
    - Notez les glyphes affichés à ces positions.

## Étape 4 : 100ème octet
11. **Remplissage** : Tapez `[1]` 91 fois pour remplir l'espace.
12. **Vérification du cap** : Après 91 octets, tapez un `1` supplémentaire pour dépasser le cap.
    - *Attendu* : Le compteur doit changer et l'écran doit réagir.

## Étape 5 : Payload P1 (tout tapable)
13. **Typage initial** : Tapez `8 5` quatre fois pour un PoC de 8 octets.
14. **Extension** : Tapez `8 5` 50 fois pour atteindre 100 octets (`0x3538`).

## Étape 6 : Activation (Trigger)
15. **Activation** : Appuyez sur `[AC]`, `[◀]`, puis `[=]`.
    *Attendu* : L'écran peut entrer en vrille ou se figer.
    - Redémarrez avec `[ON]` et vérifiez qu'il n'y a aucun changement permanent.

## Étape 7 : Rapport final
16. **Glyphes notés** : Rapportez les glyphes obtenus aux étapes 3 et 4.
17. **État de l'écran** : Préparez une photo de l'écran à 90ème et 91ème octet.
18. **Comportement au flood** : Notez le comportement de l'écran après l'activation.
19. **Comportement de l'écran** : Vérifiez si le comportement est cohérent avec les attentes de la surcharge et de l'avancement.

### Fallback
- Si l'écran ne réagit pas comme attendu, répétez avec une autre séquence de commandes ou réinitialisez l'appareil.

Ce test doit être mené par un opérateur expérimenté pour observer et documenter les résultats correctement.