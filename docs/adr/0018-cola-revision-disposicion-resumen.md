# ADR 0018: Disposición del resumen guardado: estado + confianza persistidos y cola de revisión idempotente

## Estado

Aceptado (2026-10-11). Decisión del dueño para FT00023
(`cola-revision-confianza`).

## Contexto

Los guardrails anti-alucinación (FT00022, ADR 0017) ya **deciden** de forma tipada
si un resumen ciudadano es `PUBLISHABLE`, `NEEDS_REVIEW` o `DISCARDED`, con una
**puntuación de grounding** `[0,1]`. Pero esa decisión **no persiste nada**: no se
guarda el **estado** del resumen en la tabla `resumen` (que existe desde `V2` con
`estado` y `confianza`), la **cola de revisión** `cola_revision` no se rellena, y no
hay forma de **encolar de baja confianza sin publicar** ni de listar lo pendiente.
El modelo de dominio (`docs/domain-model.md`) fija además la máquina de estados del
resumen (`pendiente → generado → validado_por_guardrails → publicado |
en_cola_revision → revisado → publicado|descartado`).

La regla del producto es dura: **nunca** publicar un resumen dudoso, pero la **cola
no debe bloquear el feed**. Hacía falta una pieza que **consumiera** la decisión de
FT00022, persistiera el estado y la confianza y encolara los de baja confianza de
forma **idempotente**, sin duplicar umbrales ni cablearse en el arranque.

## Decisión

Añadir en `:backend`, como **librería sin wiring**, el paquete `rag/review/` y
extender la persistencia de la cola:

- **Consumir la decisión de FT00022, sin umbral nuevo**: `SummaryDispositionService`
  recibe `SummaryGuardrailResult` y ramifica de forma **exhaustiva** por
  `GuardrailDecision`. Los umbrales (`DISCARD_THRESHOLD` = 0.5,
  `REVIEW_THRESHOLD` = 0.8) y el grounding siguen siendo de FT00022; aquí **no** se
  redefinen.
- **Persistir estado y confianza en `resumen`** (tabla existente de `V2`, sin
  columnas nuevas): `PUBLISHABLE` ⇒ `estado = publicado`; `NEEDS_REVIEW` ⇒
  `en_cola_revision` + entrada `pendiente` en `cola_revision`; `DISCARDED` ⇒
  `descartado`. La `confianza` persistida es el **`groundingScore`**; el resumen
  publicado lleva `aviso_ia = true` (el aviso **visible** es FT00033). Se reutiliza
  el *upsert* de `SummaryRepository` (1:1 por `publicacion_id`).
- **Representar los estados del dominio** (`SummaryState`): los siete tokens de
  `docs/domain-model.md`, que coinciden con `resumen.estado`/`cola_revision.estado`
  (sin migración de datos). El identificador Kotlin va en inglés; el token es dato.
- **Encolar de forma idempotente** con un **índice único parcial** (migración `V5`:
  `ON cola_revision (resumen_id) WHERE estado = 'pendiente'`) y un *upsert*
  (`ON CONFLICT … DO UPDATE SET motivo = EXCLUDED.motivo RETURNING id`). Reencolar
  un resumen ya pendiente **actualiza** el motivo sin duplicar la fila; el
  historial de revisiones cerradas se conserva. Se añade `listPending()` para el
  consumidor (FT00026+) y el test.
- **No-bloqueo**: encolar es un efecto local; un `NEEDS_REVIEW` **nunca** publica y
  el servicio **no** lanza por baja confianza. El `motivo` es un **diagnóstico
  interno** (nombres de violación en inglés), no texto de UI.
- **Sin wiring y sin anticipar lo diferido**: `Application.kt`/job/backfill,
  `SummaryGuardrail`, `ResumenDto`/`CitizenSummaryValidator`, `HybridSearch`,
  `:shared`, `:composeApp`, CI e `init.sh` quedan intactos. El **feed** (consulta por
  `estado = publicado`), los endpoints, la UI y la **revisión manual**
  (`revisado → publicado|descartado`) son de FT00026+/FT00033. La prueba real es
  **opt-in** (`DB_LIVE_TEST=1`, solo PostgreSQL).

## Alternativas consideradas

- **Tabla de cola propia nueva.** Se descarta: `cola_revision` ya existe (`V2`) con
  `resumen_id`, `motivo`, `estado` y FK en cascada; basta un índice parcial para la
  idempotencia.
- **Umbral de revisión nuevo o grounding duplicado.** Se descarta: redefinir el
  umbral aquí duplicaría la decisión de FT00022 (ADR 0017); el servicio **consume**
  la `GuardrailDecision`.
- **Publicar solo (sin registrar `descartado`).** Se descarta: el estado
  `descartado` se persiste para **observabilidad**; un descarte sin rastro dificulta
  diagnosticar.
- **Diferir toda la escritura a FT00026+.** Se descarta: la disposición es una
  unidad coherente (estado + confianza + cola) que el feed necesita ya resuelta;
  diferirla esparciría la lógica por el endpoint.
- **Bloquear el feed ante baja confianza.** Se descarta: el feed filtra por
  `estado = publicado`; un resumen dudoso simplemente queda fuera y la cola es
  interna, sin bloquear el resto.

## Consecuencias

- Ningún resumen `NEEDS_REVIEW` se publica; queda `en_cola_revision` con su
  `confianza` y una entrada `pendiente` con el motivo, lista para revisión interna.
  El feed futuro solo sirve `publicado`.
- La frontera con FT00022 queda fijada: el guardrail **decide**, FT00023 **dispone**;
  no se duplica el modelo de umbral.
- `ReviewQueueRepository` se **extiende** (FT00008) de forma compatible: `save` pasa
  a *upsert* idempotente y se añade `listPending()`; `listBySummary` se mantiene.
  `SummaryRepository` **no** se toca.
- Es una **librería sin wiring**: no toca `Application.kt`/job/backfill, no añade
  endpoints/UI y la prueba real es **opt-in** (`DB_LIVE_TEST=1`).
- Riesgos asumidos y documentados: crear el índice único parcial **falla** si
  ya existieran duplicados pendientes (en la práctica la tabla está vacía porque
  nadie escribía en ella hasta FT00023); la disposición es **inerte** hasta que
  FT00026+ construya el servicio; el grounding y los estados `generado`/
  `validado_por_guardrails`/`revisado` quedan reservados al wiring/operador; el
  aviso de IA **visible** y la revisión manual llegan con FT00033/FT00026+.
