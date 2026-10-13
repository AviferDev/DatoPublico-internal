# ADR 0028: Pantalla de detalle del cliente como contrato y vocabulario compartido diferido

## Estado

Aceptado (2026-10-13). Decisión del dueño del proyecto al ejecutar `ui-detalle`
(FT00033), la segunda pantalla real de `:composeApp`.

## Contexto

La primera UI real (FT00032, ADR 0027) dejó `:composeApp` con tema, i18n,
`design/components/` y la capa `feature/feed/{domain,data,ui}`, con un
`FeedStateHolder` local y **sin** navegación (reservada a FT00034) ni red
(FT00035). La pantalla de detalle (FT00033) debe mostrar el resumen estructurado,
el plazo, el enlace a la fuente oficial y el aviso de IA de **una** publicación.

Restricciones que condicionan la decisión:

- La **navegación** (feed → detalle) y el **estado compartido** son de FT00034;
  el cliente HTTP/caché y el mapeo desde `:shared`, de FT00035. FT00033 no debe
  invadirlas.
- `CONSTRAINTS.md` exige i18n, `@Preview`, Material Icons, colores del tema, sin
  crashes, un solo `return`, sin `else if` y ≤40 líneas por función.
- El detekt del cliente limita a 15 funciones por fichero (`TooManyFunctions`).

## Decisión

1. **El detalle se entrega como contrato**: `DetailRoute(stateHolder, onBack)` es
   el punto de invocación de la pantalla. FT00033 **no** cablea la navegación ni
   añade `onClick` a `PublicationCard` (FT00034) ni implementa HTTP/`:shared`
   (FT00035). Consecuencia asumida: en la app final el detalle no es alcanzable
   hasta FT00034.
2. **Capas `feature/detail/{domain,data,ui}`** con el mismo patrón que
   `feature/feed` (ADR 0027): dominio propio del cliente (`PublicationDetail`,
   `CitizenSummary`, `DetailLoadResult` tipado), puerto `DetailRepository` +
   `InMemoryDetailRepository` (datos de ejemplo; modos `SAMPLE`/`NOT_FOUND`/
   `UNAVAILABLE`) y `ui/` stateless con `DetailUiState` (Loading/Content/NotFound/
   Error).
3. **Componentes reutilizables** en `design/components/`: `AiNotice`,
   `OfficialSourceLink` (con guarda `http(s)://` antes de `LocalUriHandler`) y
   `SectionBlock`. El **aviso de IA** y el **enlace a la fuente oficial** son
   siempre visibles en el detalle.
4. **Vocabulario compartido diferido**: `PublicationCategory`, `HighlightReason`,
   `Deadline` y `formatIsoDate` **siguen** en `feature/feed/domain`, y
   `feature/detail` (y `design/components/`) los importan desde ahí. La extracción
   a un `core/model` neutral se pospone (deuda declarada) para no chocar con las
   features de UI en curso (FT00034/FT00035).
5. **Fecha sin `java.time`** (reutiliza `formatIsoDate`), coherente con ADR 0027.

## Alternativas consideradas

- **Cablear la navegación aquí**: descartado; la navegación y el patrón de estado
  son FT00034 (evita dos ViewModels/navegaciones y conflictos).
- **Extraer el vocabulario compartido a `core/model` ya**: descartado en esta
  feature por el roce con las features de UI paralelas; se difiere como limpieza.
- **Añadir `:shared`/HTTP**: descartado; es FT00035 y rompería el gate SDK-free
  (ADR 0027).

## Consecuencias

- Habilita FT00034 (conectará `feed → detail` sustituyendo el placeholder por
  `DetailRoute`) y FT00035 (reemplazará `InMemoryDetailRepository` por HTTP).
- Deuda declarada (Low): `feature/detail` y `design/components/` dependen de
  `feature/feed/domain`; extraer el vocabulario a `core/model` en una limpieza
  posterior (o al llegar la segunda feature que reutilice esos tipos).
- Duplicación menor de una clave i18n (`detail_retry` frente a `feed_retry`).
- Documentación afectada: `ARCHITECTURE.md` (§`:composeApp`), `CONSTRAINTS.md`
  (§«Cliente (Compose Multiplatform)»), skill `compose-multiplatform-architecture`
  (§«Estado actual») y `docs/desarrollo-local.md` (producto).
