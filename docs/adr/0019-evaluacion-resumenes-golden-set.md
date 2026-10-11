# ADR 0019: Evaluación de la calidad del resumen ciudadano con golden set versionado, métricas léxicas puras y CLI one-shot opt-in

## Estado

Aceptado (2026-10-11). Decisión del dueño del proyecto para FT00024
(`evaluacion-golden-set`). No supersede ningún ADR. Ajusta la numeración
**prevista** en el spec (que proponía `0018`, ya ocupado por la cola de revisión de
FT00023): el número durable es **0019**.

## Contexto

La simplificación con IA ya tiene el contrato del resumen (`ResumenDto` /
`CitizenSummaryValidator`, FT00019), la **generación** del resumen ciudadano tras
un proveedor de texto intercambiable (`CitizenSummaryGenerator`, FT00020), el
**cacheo** y el uso de tokens (FT00021) y los **guardrails** anti-alucinación con
el normalizador léxico puro `SummaryTextNormalizer` (FT00022). Falta la tarea
`0.4-T05`: **medir** la calidad de los resúmenes con un conjunto de prueba
versionado para detectar regresiones y decidir con datos antes de construir la cola
de revisión (FT00023), los endpoints/UI (FT00026+) y el chat encima.

Restricciones: el gate y la CI corren **sin red, sin base de datos, sin el modelo
E5 y sin `OPENCODE_API_KEY`**; la generación real depende de OpenCode y no es
determinista, así que **no** puede ser la unidad verificable del gate; PostgreSQL +
pgvector con **JDBC + HikariCP sin ORM** (ADR 0003); `:backend` es una **librería
sin wiring** hasta que la API y la operación la consuman; todo el código en inglés
con KDoc en castellano, un solo `return`, sin `else if` y funciones ≤40 líneas.
`CitizenSummaryGenerator` aún no tenía ningún consumidor de producto: la evaluación
es el primero.

## Decisión

- **Golden set versionado en recursos de `main`.** El dataset vive en
  `backend/src/main/resources/rag/eval/summary-golden-set.json`: un corpus modesto
  de publicaciones (encabezados `Artículo N` explícitos para que el `order` del
  chunker sea determinista; ids con prefijo **`EVAL-S`** para no colisionar con
  datos reales ni con el `EVAL-` de FT00018) y, en cada entrada, su **resumen de
  referencia**. Vive en recursos de `main` porque lo consume una CLI de `main`
  (como `BackfillMain` y `RetrievalEvaluationMain`), no un test.
- **DTOs `@Serializable` con sufijo `Dto` y `@SerialName` explícito en cada
  propiedad** (`SummaryGoldenSetDto`, `SummaryGoldenSetEntryDto`);
  `section`/`category` reutilizan los enums de wire `SeccionBoeDto`/`CategoriaDto`
  y **`reference` reutiliza `SummaryGenerationDto`** (FT00020), que es exactamente
  la forma del resumen de referencia. **Modelo interno sin sufijo**
  (`SummaryGoldenSet`, `SummaryGoldenSetEntry`): la entrada se mapea a `Publicacion`
  (reutilizando el modelo de dominio) para pasarla al generador.
- **Loader puro con fail-fast.** `SummaryGoldenSetLoader.parse(json)` y
  `load(path = null)` (recurso de classpath por defecto, o fichero) validan versión
  y entradas no vacías, identificadores únicos, categoría, título y texto presentes
  y referencia con «¿Qué cambia?» y «¿A quién afecta?» no vacíos. Un dataset
  inválido falla con `IllegalArgumentException` **sin** abrir conexión ni invocar
  al generador.
- **Métricas puras.** `SummaryQualityMetrics` (sin estado ni dependencias)
  reutiliza `SummaryTextNormalizer` (FT00022) y define `tokenF1(hypothesis,
  reference)` sobre el **multiconjunto** de términos de contenido
  (`precision = |∩|/|hipótesis|`, `recall = |∩|/|referencia|`,
  `F1 = 2·P·R/(P+R)`; `0.0` si `P+R = 0` o la referencia no tiene términos) y
  `figuresRecall(summary, referenceFigures)` (fracción de cifras de la referencia
  presentes en la unión de `queCambia` + `aQuienAfecta` + `cifrasClave`; `1.0` si
  la referencia no tiene cifras).
- **Evaluador con generador inyectable.** `SummaryQualityEvaluator` compone un
  `fun interface SummaryGenerator` (cuya firma satisface
  `CitizenSummaryGenerator::generate`) y `evaluate(dataset)` genera **una vez por
  entrada**, deriva `hit = whatChangesF1 >= umbral && whoIsAffectedF1 >= umbral`,
  agrega las medias con el helper `mean()` (sin `NaN`), calcula `hitRate` y cuenta
  los `CitizenSummaryResult.Invalid` como **fallo** (`0.0` en ambos F1,
  `invalid = true`), **sin lanzar**.
- **CLI one-shot sin wiring.** `SummaryEvaluationMain` (`:backend:evaluateSummary`,
  `JavaExec`, grupo `application`, **fuera** de `build`/`check`) resuelve la
  conexión de `POSTGRES_*`, la config de OpenCode (`OpenCodeConfig.fromEnv()`,
  fail-fast de `OPENCODE_API_KEY`) y las rutas del modelo
  (`EMBEDDING_MODEL_PATH`/`EMBEDDING_TOKENIZER_PATH` o
  `backend/models/multilingual-e5-small/`), indexa el corpus del dataset
  (`FragmentIndexer`, idempotente), genera y evalúa con `CitizenSummaryGenerator` y
  registra `event=summary.evaluation.started`/`completed` (log JSON con campos
  puros + `StructuredArguments`) y un resumen legible por entrada en stdout. Un
  fallo sale con código ≠ 0 y mensaje claro; cierra cliente, modelo y pool en
  `finally`. **No** se cablea en `Application.kt`/job/backfill.
- **Sin juez LLM y sin persistencia del histórico.** La métrica es **léxica y
  determinista** (F1 por campo + *recall* de cifras); se descarta el
  *LLM-as-judge* (ni determinista ni offline). «Registrar el resultado» es log JSON
  + stdout: **no** hay tabla ni migración nueva.
- **Verificación *offline* + opt-in.** El gate cubre `SummaryQualityMetricsTest`,
  `SummaryGoldenSetTest` y `SummaryQualityEvaluatorTest` con dobles deterministas,
  **sin red, BD, modelo ni OpenCode**. La ejecución real es **opt-in**
  (`OPENCODE_LIVE_TEST=1` + `DB_LIVE_TEST=1` + `EMBEDDING_LIVE_TEST=1`), con un
  umbral **conservador y documentado** (`meanWhatChangesF1 >= 0.3`,
  `hitRate >= 0.3`).

## Alternativas consideradas

- **Juez LLM (LLM-as-judge) como métrica del gate.** Descartado: no es determinista
  ni offline y añadiría una dependencia de red y de coste al gate; el objetivo es
  detectar **regresiones**, no certificar calidad absoluta.
- **Persistir el histórico de evaluaciones en una tabla.** Descartado: exigiría
  migración y es un Non-Goal explícito; el histórico por log JSON es suficiente.
- **Dataset en `src/test/resources`.** Descartado: la CLI es de `main` y necesita el
  recurso en su classpath (mismo patrón que `BackfillMain`).
- **Endpoints/UI de evaluación.** Descartado: la evaluación es una herramienta
  interna; los endpoints/UI llegan con FT00026+.
- **Reimplementar el normalizador/tokenizador en las métricas.** Descartado:
  `SummaryTextNormalizer` (FT00022) ya es puro y determinista; duplicarlo crearía dos
  definiciones de «término de contenido».
- **Acoplar el evaluador a `CitizenSummaryGenerator`.** Descartado: el
  `fun interface SummaryGenerator` mantiene las métricas ajenas a OpenCode y
  permite dobles deterministas en el gate.
- **Métricas de sistema (latencia, memoria, coste de tokens).** Descartado: fuera de
  alcance; aquí se mide **calidad** del resumen.
- **Ajustar automáticamente el prompt con el resultado.** Descartado: el resultado
  informa una decisión humana; `PROMPT_VERSION` se sube a mano.

## Consecuencias

- **Habilita** detectar regresiones del resumen ciudadano con un comando
  reproducible antes de construir encima la revisión (FT00023) y los endpoints/UI
  (FT00026+); la evaluación es el **primer consumidor de producto** de
  `CitizenSummaryGenerator` (FT00020) y del normalizador de FT00022, que se
  **reutilizan sin modificar**.
- **Cuesta** un paso opt-in más pesado que FT00018 (PostgreSQL migrado + modelo E5 +
  clave de OpenCode: tres recursos) para la verificación real; el gate no lo cubre
  (limitación aceptada). El corpus es pequeño y las cifras reales son evidencia, no
  una aserción ajustada.
- **Riesgos asumidos y documentados**: el F1 **léxico** penaliza paráfrasis válidas
  (sin *stemming* ni sinónimos), así que `DEFAULT_HIT_THRESHOLD = 0.5` es un punto
  de partida **conservador y ajustable** que se calibra con datos reales (el gate no
  depende de él); la calidad del golden set depende de la redacción a mano de las
  referencias (mitigado por la validación del loader y por publicar las cifras
  reales como evidencia); no se persiste el histórico.
- **Documentación/código**: `ARCHITECTURE.md` (`rag/evaluation/`), regla MUST en
  `CONSTRAINTS.md` §«Evaluación de resúmenes», estado actual en la skill
  `rag-datapublico` §7, sección en `docs/desarrollo-local.md` (producto) y este ADR.
- **Verificación**: `SummaryQualityMetricsTest`/`SummaryGoldenSetTest`/
  `SummaryQualityEvaluatorTest` (gate) y `SummaryEvaluationLiveTest` (opt-in); la
  tarea `:backend:evaluateSummary` **no** se engancha a `build`/`check` ni a
  `init.sh` ni a la CI.
