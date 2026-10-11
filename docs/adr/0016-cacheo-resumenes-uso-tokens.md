# ADR 0016: Cacheo del resumen ciudadano en tabla propia con clave publicación+modelo+prompt y registro de uso de tokens

## Estado

Aceptado (2026-10-11). Decisión del dueño para FT00021 (`cacheo-resumenes`).

## Contexto

La generación del resumen ciudadano ya existe como **librería sin wiring**
(FT00020, ADR 0015): `CitizenSummaryGenerator` recupera con `HybridSearch`,
construye el prompt, invoca el proveedor de texto (OpenCode) y valida el contrato.
Generar el mismo resumen de una publicación ya resumida vuelve a **pagar** una
llamada al LLM, y no había forma de **vigilar el coste**. Hacía falta:

- no regenerar un resumen idéntico mientras no cambie nada que lo invalide,
- dejar constancia de los **tokens** consumidos por generación.

El proveedor OpenAI-compatible devuelve el bloque `usage` (prompt/completion/total),
pero `GenerationResponse` no lo exponía. No existía la noción de **versión del
prompt**, así que no había manera de invalidar la caché cuando el prompt cambiaba.
La tabla `resumen` guarda el resumen **publicado** (1:1 con la publicación), un
concepto distinto de la caché.

## Decisión

Añadir en `:backend`, como **librería sin wiring**, el cacheo y el control de coste:

- **Clave determinista** `SummaryCacheKey.of(publicationId, model, promptVersion)` =
  `"$publicationId|$model|$promptVersion"` (valor **puro**, fail-fast si algún
  componente está en blanco). Incluye **modelo** y **versión de prompt** para que un
  cambio de cualquiera de los dos **no** sirva un resumen obsoleto. La versión vive
  como constante **manual** `CitizenSummaryPromptBuilder.PROMPT_VERSION` que hay que
  subir al cambiar el prompt.
- **Servicio con caché** `CachedCitizenSummaryGenerator` que **envuelve** al
  generador (no reescribe su pipeline): consulta la caché **antes** del proveedor;
  en **acierto** devuelve el resumen cacheado sin llamar a OpenCode y registra un uso
  con `cache_hit = true` y 0 tokens; en **fallo** genera, registra el uso real
  (tokens del proveedor o 0) y **cachea solo si el resultado es `Valid`**. El
  **modelo** se **inyecta** por constructor (en producción, de `OpenCodeConfig`): la
  caché no lo lee de la config.
- **Persistencia en tabla propia**: migración `V4` con `resumen_cache`
  (`cache_key` PK, FK en cascada a `publicacion`, `modelo`, `prompt_version`,
  `resumen` = `ResumenDto` serializado a JSON) y `generacion_uso` (log de tokens con
  `cache_hit`, **sin** FK a `publicacion`). Repositorios JDBC
  (`SummaryCacheRepository` con codec JSON puro, `GenerationUsageRepository` con
  `totalTokens()`), *upsert* idempotente por `cache_key`.
- **Uso de tokens en el proveedor**: `GenerationResponse` gana `usage: TokenUsage?`
  (opcional, compatible) y `OpenCodeTextGenerationProvider` parsea el bloque `usage`
  con DTOs de wire; sin `usage` en la respuesta, `usage` es `null` (no es error).
  `CitizenSummaryResult` propaga el uso de forma **compatible** (campo con default
  `null`).

## Alternativas consideradas

- **Reutilizar la tabla `resumen` como caché.** Se descarta: `resumen` guarda el
  resumen **publicado** (estado, confianza, cola de revisión, FT00023/FT00026), no
  una caché por (publicación, modelo, prompt); mezclarlas acoplaría conceptos y
  rompería el 1:1. Se usa una tabla **propia y separada**.
- **Duplicar las columnas del resumen en `resumen_cache`.** Se descarta: se guarda
  el `ResumenDto` **serializado** (JSON) y se reutiliza el contrato de wire; el coste
  es un `encode`/`decode` por operación y el acoplamiento a `ResumenDto` (que es el
  contrato). Evita duplicar el esquema y mantener dos fuentes de verdad.
- **Clave solo por publicación.** Se descarta: cambiar el modelo o el prompt
  serviría un resumen obsoleto. La clave incluye **ambos**.
- **Invalidar la caché por hash del prompt o de las reglas del validador.** Se
  descarta por ahora: la `PROMPT_VERSION` es una constante manual (riesgo
  documentado); versionar la clave por hash queda para una revisión futura si las
  reglas de `CitizenSummaryValidator` cambian de forma incompatible.
- **Fail-fast si el proveedor no devuelve `usage`.** Se descarta: no es un error de
  dominio; se registran 0 tokens (el agregado puede subestimar, riesgo aceptado).
- **Cablear la caché en el arranque/job.** Se descarta: FT00021 es la **pieza**;
  el wiring llega con FT00026+.

## Consecuencias

- Un resumen ya generado con el mismo modelo y prompt **no se vuelve a generar** y
  cada generación deja constancia de los tokens (`generacion_uso`), base del control
  de coste.
- Nueva migración `V4` y dos repositorios en `persistence/`; `GenerationResponse`
  expone `usage` y `CitizenSummaryResult` lo propaga (ambos compatibles).
- Es una **librería sin wiring**: no se cablea en `Application.kt`/job/backfill, no
  añade endpoints/UI y no toca `ResumenDto`/`CitizenSummaryValidator`/`HybridSearch`.
  La prueba real es **opt-in** (`DB_LIVE_TEST=1`, solo PostgreSQL).
- Riesgos asumidos y documentados: el **modelo inyectado** debe coincidir con el real
  (se exige coherencia en el wiring de FT00026+); la `PROMPT_VERSION` es **manual**
  (olvidar subirla serviría resúmenes obsoletos); un cambio en `CitizenSummaryValidator`
  no invalida la caché por sí solo; `usage` ausente registra 0 tokens; la caché es
  **inerte** hasta que FT00026+ construya el servicio.
