# Roguelite Cards Layer (MVP)

El prototipo ahora incluye una capa de cartas para gamificar decisiones de run.

## Flujo

1. Inicia run con `New Run`.
2. Elige nodo en `Opciones` y pulsa `Enter Node`.
3. Tras ciertos nodos apareceran recompensas.
4. Si tomas recompensa `Draft de carta`, se abre `Draft 1 de 3`.
5. Elige una carta:
   - `passive`: efecto permanente en la run (upgrades, bonus score, economia, etc).
   - `active`: entra a la mano (`Activas`) y puedes jugarla en cualquier momento.

## Seccion Cards en UI

- `Pasivas`: lista de cartas permanentes obtenidas.
- `Activas (click para jugar)`: botones para consumir cartas activas.
- `Draft 1 de 3`: aparece al obtener recompensa de draft.

## Efectos implementados

- Pasivas: habilitar upgrades, bonus de score, bonus vs boss, heal, coins, aumento de mano activa.
- Activas: variacion procedural, reforge por track, reroll global base, score temporal, coins.

## Archivos nuevos

- `scripts/core/card_data.gd`
- `scripts/core/card_library.gd`
- `scripts/core/run_manager.gd` (expandido para recompensas de cartas)
- `scripts/main/main.gd` (integracion de estado de cartas)
- `scripts/ui/ui_controller.gd` (UI de cartas)
