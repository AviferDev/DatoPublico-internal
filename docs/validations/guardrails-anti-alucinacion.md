# Validación independiente — `guardrails-anti-alucinacion` (FT00022)

- Fecha: 2026-10-11
- Rol: `validator` (feature-validator), solo lectura.
- Rama de producto: `feat/ft00022-guardrails-anti-alucinacion` (implementación
  **sin commitear**: 9 fuentes + 6 tests nuevos en `rag/guardrails/` y
  `docs/desarrollo-local.md` modificado).
- Spec: `docs/specs/guardrails-anti-alucinacion.md`.
- Veredicto: **`revise`** (un hallazgo High: la propiedad de seguridad de la
  feature no se cumple en todos los casos).

## Comandos reejecutados y resultados reales

Desde `..` con `JAVA_HOME` del JBR 21:

- `./gradlew :backend:test --rerun-tasks --no-daemon` → **BUILD SUCCESSFUL**;
  XML: **312 tests, 0 fallos, 0 errores, 0 skipped** (65 clases). Nuevos de
  `rag/guardrails/`: `SummaryTextNormalizerTest` 6, `OfficialSourceValidatorTest`
  7, `SummaryGroundingCheckerTest` 5, `SummaryGuardrailTest` 10,
  `HttpSourceReachabilityTest` 5, `SummaryGuardrailLiveTest` 1 = **34**; los
  **278** de FT00021 intactos.
- `./gradlew build -PskipClient --no-daemon` → **BUILD SUCCESSFUL** (23 tareas).
- `./gradlew test --no-daemon` → **BUILD SUCCESSFUL** (3 módulos, 63 tareas).
- `./gradlew detekt :cpdCheck --rerun-tasks --no-daemon` → **BUILD SUCCESSFUL**
  (4 tareas ejecutadas; Detekt en `:backend`/`:shared`/`:composeApp` + CPD).
- `env -u JAVA_HOME .harness/init.sh` → **exit 0** (gate SDK-free + detekt).
- Offline confirmado: los tests live imprimen «omitido» sin abrir sockets
  (`SummaryGuardrailLiveTest`, `E5EmbeddingLiveTest`, `HybridSearchLiveTest`,
  `CitizenSummaryGeneratorLiveTest`, `FragmentIndexerLiveTest`,
  `RetrievalEvaluationLiveTest`). Ningún test de gate toca red ni BD.
- Opt-in `BOE_LIVE_TEST=1 ./gradlew :backend:test --tests '*SummaryGuardrailLiveTest'`
  → **FAILED** por **truststore del JBR**: `curl` obtiene HTTP 200
  (`ssl_verify=0`) pero el `cacerts` del JBR tiene **0** entradas FNMT (el
  `keytool -list` no encuentra `fnmt`). Limitación **aceptada** y ya documentada
  (spec + `docs/desarrollo-local.md`, igual que en FT00006); el puerto HTTP sí
  está cubierto por `HttpSourceReachabilityTest` con `MockEngine`.

## Alcance (limpio)

`git status` del producto: solo `docs/desarrollo-local.md` (modificado) y los dos
directorios nuevos `rag/guardrails/` (main/test). **Intactos**: `Application.kt`
(sin menciones a guardrails), job/backfill, `ingesta/`, `persistence/`,
`HybridSearch`, `ResumenDto`, `CitizenSummaryValidator`, `CitizenSummaryGenerator`,
`CachedCitizenSummaryGenerator`, migraciones (siguen `V1`–`V4`, sin `V5`),
`:shared`, `:composeApp`, CI e `init.sh`. Sin dependencias Gradle nuevas.

## Estilo y documentación

- Sin `else if`; un solo `return` por función; funciones ≤40 líneas (máx ~10);
  identificadores en inglés, KDoc en castellano; sin `@Serializable` nuevos (no
  aplica `@SerialName`). Sufijo `Dto` solo en transporte (ninguno nuevo).
- Reutiliza `CitizenSummaryValidator` sin duplicar reglas; `categoria` nula es
  fail-fast (`IllegalArgumentException`).
- Docs durables: `ARCHITECTURE.md`, `CONSTRAINTS.md` §«Guardrails…», ADR 0017 +
  índice, skill `rag-datapublico` §6, `docs/desarrollo-local.md`; `PROGRESS.md` y
  `feature_list.json` los cierra el orquestador.
- Seguridad: sin secretos; sin red en el gate; `HttpSourceReachability` no se
  traga `CancellationException`; comparación de host con lista blanca (rechaza
  *lookalikes* y *userinfo*). Sin hallazgos de seguridad bloqueantes.

## Hallazgos

### High — `decide` puede devolver `PUBLISHABLE` con una afirmación no sustentada

- Evidencia (código): `SummaryGuardrail.kt` líneas 88–98. `decide` solo mira
  `grounding.score`: `score >= REVIEW_THRESHOLD (0.8) → PUBLISHABLE`, sin
  considerar `grounding.violations`.
- Evidencia (demostración): con el contexto del propio test, un resumen de **5
  afirmaciones** de las que **4 están sustentadas** y **1 no** («Reduce el
  impuesto especial») da `score = 4/5 = 0.8` ⇒ `decision = PUBLISHABLE`,
  `isPublishable = true`, con `guardrailViolations = [UNSUPPORTED_CLAIM]`. Mismo
  patrón con `UNSUPPORTED_FIGURE` (4/5 con una cifra fuera del contexto).
- Contradice: **Scenario 2/3** del spec (`decision != PUBLISHABLE`), el
  `user_visible_behavior` de la feature, la regla **MUST** de `CONSTRAINTS.md`
  («ningún resumen se publica … con afirmaciones no sustentadas») y el propio
  **Validator Checklist** del spec («Ningún resumen con afirmación fuera del
  contexto … queda publicable»).
- Nota: el algoritmo está **prescrito tal cual** en el spec (Technical Approach
  §6), así que el implementer siguió el spec; la inconsistencia es spec-interna
  (el algoritmo tolera hasta un 20 % de afirmaciones no sustentadas). El arreglo
  es pequeño y localizado, pero exige reconciliar spec/ADR con la garantía.

### Low — duplicados en `STOP_WORDS`

`SummaryTextNormalizer.kt` lista «sus», «sea» y «ser» dos veces. Inocuo (es un
`setOf`), pero conviene limpiarlo.

## Repair brief (para `revise`)

1. En `SummaryGuardrail.decide`, hacer que **cualquier violación de grounding
   impida `PUBLISHABLE`**. Cambio mínimo sugerido (mantiene el resto de ramas):
   ```kotlin
   private fun decide(
       contractValid: Boolean,
       sourceValid: Boolean,
       reachable: Boolean,
       grounding: GroundingAssessment,
   ): GuardrailDecision = when {
       !contractValid || !sourceValid || !reachable -> GuardrailDecision.DISCARDED
       grounding.score < DISCARD_THRESHOLD -> GuardrailDecision.DISCARDED
       grounding.score < REVIEW_THRESHOLD || grounding.violations.isNotEmpty() ->
           GuardrailDecision.NEEDS_REVIEW
       else -> GuardrailDecision.PUBLISHABLE
   }
   ```
   (Pasar `grounding` en vez de `grounding.score`; ajustar la llamada en
   `evaluate`.) Alternativa más estricta: enviar `UNSUPPORTED_CLAIM`/
   `UNSUPPORTED_FIGURE` a `DISCARDED`; el spec admite «descartado o a revisión».
2. Añadir un test de regresión del límite: 5 afirmaciones, 4 sustentadas + 1 no ⇒
   `assertFalse(result.isPublishable)` y
   `contains(UNSUPPORTED_CLAIM)` (idem con una cifra no sustentada).
3. Verificar que Scenario 1 (válido, `score = 1.0`, sin violaciones) sigue
   `PUBLISHABLE` y que Scenario 7 (`score` en `[0.5, 0.8)`) sigue `NEEDS_REVIEW`.
4. Actualizar, si aplica, la redacción del spec/ADR 0017 para dejar explícito que
   una afirmación no sustentada **nunca** publica (y limpiar los duplicados de
   `STOP_WORDS`).
5. Reejecutar: `./gradlew :backend:test --rerun-tasks`, `build -PskipClient`,
   `test`, `detekt`+`:cpdCheck`, `init.sh` → exit 0.

---

# Revalidación independiente tras la reparación (2026-10-11)

- Rol: `validator` (feature-validator), solo lectura.
- Rama de producto: `feat/ft00022-guardrails-anti-alucinacion` (implementación
  **sin commitear**: 9 fuentes + 6 tests en `rag/guardrails/` y
  `docs/desarrollo-local.md` modificado; sin otros cambios de producto).
- Veredicto: **`accept`** — el hallazgo **High** queda reparado, el **Low** está
  limpio y la garantía es consistente entre código, spec y ADR.

## Comandos reejecutados y resultados reales

Desde `..` con `JAVA_HOME` del JBR 21
(`/Applications/Android Studio.app/Contents/jbr/Contents/Home`):

- `./gradlew :backend:test --rerun-tasks --no-daemon` → **BUILD SUCCESSFUL**;
  XML: **314 tests, 0 fallos, 0 errores, 0 skipped** (65 clases). Nuevos de
  `rag/guardrails/`: `SummaryTextNormalizerTest` 6, `OfficialSourceValidatorTest`
  7, `SummaryGroundingCheckerTest` 5, `SummaryGuardrailTest` **12**,
  `HttpSourceReachabilityTest` 5, `SummaryGuardrailLiveTest` 1 = **36**; los
  **278** no-guardrails (FT00021 y anteriores) intactos.
- `./gradlew build -PskipClient --no-daemon` → **BUILD SUCCESSFUL** (23 tareas).
- `./gradlew test --no-daemon` → **BUILD SUCCESSFUL** (63 tareas, 3 módulos).
- `./gradlew detekt :cpdCheck --rerun-tasks --no-daemon` → **BUILD SUCCESSFUL**
  (4 tareas ejecutadas).
- `env -u JAVA_HOME .harness/init.sh` → **exit 0** («Gate OK.»).
- Offline confirmado: los tests live imprimen «omitido» sin abrir sockets
  (`SummaryGuardrailLiveTest` incluido); ningún test del gate toca red ni BD.

## El hallazgo High está reparado

- `SummaryGuardrail.decide` ahora recibe el `GroundingAssessment` completo
  (`SummaryGuardrail.kt` líneas 96–107): `!contractValid || !sourceValid ||
  !reachable → DISCARDED`; `score < DISCARD_THRESHOLD → DISCARDED`;
  `score < REVIEW_THRESHOLD || grounding.violations.isNotEmpty() → NEEDS_REVIEW`;
  `else → PUBLISHABLE`. Publicar exige **score ≥ 0.8 y violaciones vacías**.
- Regresión del límite (4/5 = 0.8) presente y verde:
  `an unsupported claim at the review threshold is not publishable` y
  `an unsupported figure at the review threshold is not publishable` afirman
  `groundingScore == REVIEW_THRESHOLD (0.8)`, `decision = NEEDS_REVIEW`,
  `isPublishable == false` y la violación correspondiente.
- Sin regresión legítima: `a valid supported summary is publishable`
  (Scenario 1) sigue `PUBLISHABLE` con `score = 1.0` y sin violaciones;
  `a low confidence summary goes to review without publishing` (Scenario 7)
  sigue `NEEDS_REVIEW` con `score ∈ [0.5, 0.8)`.
- Invariante consistente en los cuatro artefactos: código (KDoc + rama de
  `decide`), spec §6 (líneas 310–324), **ADR 0017** (líneas 49–58) y
  `CONSTRAINTS.md` §«Guardrails anti-alucinación y trazabilidad»; también en
  `ARCHITECTURE.md`, skill `rag-datapublico` §6 y `docs/desarrollo-local.md`.

## El hallazgo Low está limpio

- `SummaryTextNormalizer.STOP_WORDS` sin duplicados (comprobado con
  `sort | uniq -d` → vacío); «sus», «sea» y «ser» aparecen una sola vez.

## Alcance (limpio) y estilo

- `git status` del producto: solo `docs/desarrollo-local.md` (modificado) y los
  dos directorios nuevos `rag/guardrails/` (main/test). **Intactos**:
  `Application.kt` (sin menciones a guardrails), job/backfill, `ingesta/`,
  `persistence/`, `HybridSearch`, `ResumenDto`, `CitizenSummaryValidator`,
  `CitizenSummaryGenerator`, `CachedCitizenSummaryGenerator`, migraciones
  (`V1`–`V4`, sin `V5`), `:shared`, `:composeApp`, CI e `init.sh`; sin
  dependencias Gradle nuevas (diff vacío en `build.gradle.kts`/
  `libs.versions.toml`/`settings.gradle.kts`).
- Estilo MUST: sin `else if`; un solo `return` por función; funciones ≤40 líneas;
  KDoc en castellano con identificadores en inglés; sin `@Serializable` nuevos.

## Seguridad

- Sin secretos; sin red ni BD en el gate; `HttpSourceReachability` no se traga
  `CancellationException` (re-lanza) y traduce fallos de red a `false`;
  `OfficialSourceValidator.hostOf` descarta *userinfo* (`substringAfterLast('@')`)
  y lista blanca de host, con test de *lookalike* (`www.boe.es.evil.com`). Sin
  hallazgos de seguridad bloqueantes.

## Observaciones (Low, de harness; no bloquean la aceptación)

- `docs/feature-ids.md` mantiene `FT00022 … not_started` mientras
  `feature_list.json` dice `passing`; es estado que cierra el orquestador.
- `feature_list.json` (notas del registro, línea 649) conserva «`:backend` 312
  tests» como instantánea previa; la evidencia del registro ya refleja **314**.

## Recomendación

Aceptar FT00022 (`accepted`). El orquestador debe persistir el estado, actualizar
`docs/feature-ids.md` (FT00022) y cerrar `PROGRESS.md`; se sugiere alinear la nota
de `feature_list.json` a 314.
