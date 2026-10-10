# Feature Implementation Spec: Contrato del resumen ciudadano

## Source Feature

- `id`: contrato-resumen-ciudadano
- `ft_id`: FT00019
- `parts`: none (atomic)
- `area`: simplificacion-ia
- `depends_on`: bootstrap-shared-dtos (FT00002, `accepted`)
- `status`: not_started (planificado 2026-10-10; rama `feat/ft00019-contrato-resumen-ciudadano` reclamada)
- `source`: `feature_list.json`

## Goal

Formalizar y **validar** el contrato del **resumen ciudadano** en el módulo
`:shared`: un resumen se compone de las secciones «¿Qué cambia?», «¿A quién
afecta?» y «Cifras clave», más la **fuente oficial obligatoria**; para las
publicaciones de **empleo público y becas** el contrato incluye además el
**plazo** (variante). Esta feature aporta un **validador puro** que comprueba
esos invariantes y los tests que los fijan (serialización de ida y vuelta +
validación), sin generar ningún resumen.

El DTO del contrato **ya existe**: `ResumenDto` se creó en FT00002 (`queCambia`,
`aQuienAfecta`, `cifrasClave`, `fuenteOficial`, `avisoIA`, `plazo`) y ya está
embebido en `PublicacionDto.resumen`. FT00019 **no** lo duplica: reutiliza
`ResumenDto` como contrato y añade la **validación de dominio pura** que hoy no
existe (la nota de `ResumenDto` delega explícitamente la obligatoriedad y
validación de `fuenteOficial` a esta feature). La generación del resumen es
FT00020.

## Non-Goals

- **Generación** del resumen (prompts, OpenCode, cita obligatoria generada) → FT00020.
- **Guardrails de contenido** y trazabilidad (validez/alcanzabilidad del enlace,
  afirmaciones fuera del contexto recuperado) → FT00022. Aquí solo se valida el
  **contrato** (estructura y presencia de la fuente), no la veracidad.
- **Confianza**, cola de revisión, estados (`pendiente`/`generado`/…), `estado` y
  `confianza` → FT00022/FT00023. El **aviso de IA** se modela (ya está en
  `ResumenDto.avisoIA`) pero su **exigencia** es de FT00023, no de este validador.
- **Cacheo** de resúmenes → FT00021.
- Persistencia/migraciones, endpoints Ktor, UI y wiring en `Application.kt`.
- Cambios en `ResumenDto` (campos, `@SerialName`, JSON de wire): el contrato de
  wire queda **congelado** salvo que un test revele una inconsistencia real.

## Job Story

When el backend genera (o el cliente muestra) el resumen ciudadano de una
publicación del BOE,
I want que el resumen cumpla siempre el contrato (tres secciones, fuente oficial
y plazo cuando es empleo/beca),
so I can garantizar que todo resumen publicado es trazable y consistente antes
de que FT00020/FT00022 lo generen y publiquen.

## Users And Permissions

- **Backend (generación/guardrails, FT00020/FT00022):** consumidor principal del
  validador; decide publicar, enviar a revisión o descartar.
- **Cliente (opcional):** puede reutilizar el validador para no renderizar
  resúmenes incompletos.
- **Usuario final (ciudadanía):** anónimo, sin cuentas; solo ve el resultado ya
  validado.

## Acceptance Scenarios

### Scenario 1: resumen completo de empleo público serializa y valida

Given un `ResumenDto` con `queCambia` y `aQuienAfecta` no vacíos, `cifrasClave`
con al menos una cifra, `fuenteOficial` absoluta (`https://…`) y un `plazo` con
`fechaLimite` no vacía
When se serializa con `DatoPublicoJson` (ida y vuelta) y se valida con categoría
`OPOSICIONES_Y_EMPLEO_PUBLICO`
Then el JSON de ida y vuelta es idéntico (mismas claves de wire) y la validación
devuelve `isValid = true` y `violations` vacía.

### Scenario 2: sin fuente oficial falla la validación

Given un `ResumenDto` con `fuenteOficial` en blanco (o sin prefijo `http(s)://`)
When se valida
Then `isValid = false` y `violations` contiene `MISSING_OFFICIAL_SOURCE`.

### Scenario 3: variante empleo/beca sin plazo falla

Given un resumen de una publicación de categoría `OPOSICIONES_Y_EMPLEO_PUBLICO`
o `BECAS_SUBVENCIONES_Y_AYUDAS` con `plazo = null` (o `plazo.fechaLimite` en
blanco)
When se valida
Then `isValid = false` y `violations` contiene `MISSING_DEADLINE`.

### Scenario 4: norma general sin plazo valida

Given un resumen de una publicación de categoría `NORMAS_Y_LEGISLACION` con las
tres secciones y fuente oficial, y `plazo = null`
When se valida
Then `isValid = true` (la variante con plazo solo aplica a empleo/becas).

### Scenario 5: secciones incompletas fallan

Given un resumen con `queCambia` o `aQuienAfecta` en blanco (o con una cifra
clave vacía)
When se valida
Then `isValid = false` y `violations` contiene `MISSING_WHAT_CHANGES`,
`MISSING_WHO_IS_AFFECTED` o `BLANK_KEY_FIGURE` según el caso.

### Scenario 6: contrato de wire congelado

Given un resumen válido serializado
When se inspecciona el JSON
Then contiene exactamente las claves `queCambia`, `aQuienAfecta`, `cifrasClave`,
`fuenteOficial`, `avisoIA` y, si procede, `plazo`/`fechaLimite` (sin renombrar el
contrato existente).

## Repository Research

### Files Inspected

- `shared/src/commonMain/kotlin/es/aviferdev/datopublico/model/ResumenDto.kt` — el
  contrato del resumen ciudadano ya existe (6 propiedades, `@SerialName`
  explícito); su KDoc delega la obligatoriedad/validación de `fuenteOficial` a
  FT00019.
- `shared/src/commonMain/kotlin/es/aviferdev/datopublico/model/PublicacionDto.kt`
  — embebe `resumen: ResumenDto?` y `plazo: PlazoDto?`.
- `shared/src/commonMain/kotlin/es/aviferdev/datopublico/model/PlazoDto.kt` —
  `fechaLimite: String` (ISO-8601) + `descripcion: String?`.
- `shared/src/commonMain/kotlin/es/aviferdev/datopublico/model/CategoriaDto.kt` —
  11 valores; `OPOSICIONES_Y_EMPLEO_PUBLICO` y `BECAS_SUBVENCIONES_Y_AYUDAS` son
  las categorías de la variante con plazo.
- `shared/src/commonMain/kotlin/es/aviferdev/datopublico/serialization/DatoPublicoJson.kt`
  — config compartida (`ignoreUnknownKeys`, `encodeDefaults`).
- `shared/src/commonTest/kotlin/es/aviferdev/datopublico/model/SerializationTest.kt`
  — ya hace round-trip de `ResumenDto` (incluido el mínimo con defaults); patrón a
  seguir.
- `backend/src/main/resources/db/migration/V2__persistencia.sql` — tabla
  `resumen` (`que_cambia`, `a_quien_afecta`, `cifras_clave text[]`,
  `fuente_oficial`, `aviso_ia`, `estado`, `confianza`); **no** guarda `plazo`
  (vive en `publicacion`). FT00019 **no** toca la persistencia.
- `docs/domain-model.md` (§Resumen ciudadano) — estados y «Un Resumen referencia 1
  Fuente oficial (obligatoria)».
- `docs/roadmap.md` 0.4-T01, `CONTEXT.md` (§Resumen ciudadano), `DESIGN.md`
  (bloques «¿Qué cambia?»/«¿A quién afecta?»/«Cifras clave» + plazo),
  `docs/build-brief.md` (Validation Plan: error en «¿Qué cambia?» y «¿A quién
  afecta?»), `.agents/skills/rag-datapublico/SKILL.md` §5 y §6.

### Existing Patterns To Follow

- **`:shared`** es el módulo de DTOs y **lógica compartida**; el namespace es
  `es.aviferdev.datopublico` (`ARCHITECTURE.md` §Módulos).
- **Convención `Dto`/`@SerialName`** (MUST): todo tipo `@Serializable` lleva
  sufijo `Dto` y cada propiedad `@SerialName` explícito. Los tipos internos no
  serializables van **sin sufijo** (`EntradaSumario`, `SearchFilter`,
  `Fragment`).
- **Validadores puros** existentes (`PgVector`, `SearchFilterSql`,
  `RetrievalGoldenSetLoader`) demuestran el patrón de validación sin red ni BD en
  el gate.
- **Estilo MUST**: un solo `return` por función, sin `else if`, ≤40 líneas por
  función, KDoc en castellano e identificadores en inglés.

### Current Gaps

- No existe ningún validador del contrato del resumen ciudadano; la obligatoriedad
  de `fuenteOficial` es hoy solo un comentario en el KDoc.
- No hay test que fije el contrato de wire del resumen completo (tres secciones +
  plazo).
- No hay un concepto explícito de **variante** (general vs. empleo/becas).

## Technical Approach

Añadir un paquete de **validación de contrato** en `:shared` (puro, sin red, BD,
reloj ni estado), junto a los DTOs:

1. **Variante** (`CitizenSummaryVariant`, enum interno **sin** `Dto` porque no es
   tipo de wire): `GENERAL` y `EMPLOYMENT_OR_SCHOLARSHIP`. Un resolver puro
   `CitizenSummaryVariantResolver.variantFor(category: CategoriaDto)` devuelve
   `EMPLOYMENT_OR_SCHOLARSHIP` para `OPOSICIONES_Y_EMPLEO_PUBLICO` y
   `BECAS_SUBVENCIONES_Y_AYUDAS`, y `GENERAL` en el resto (con `when` + `else`,
   sin `else if`).
2. **Resultado** (`CitizenSummaryValidation`): `violations: List<CitizenSummaryViolation>`
   y `isValid` derivado (`violations.isEmpty()`). El validador **no lanza**: un
   resumen inválido es un resultado esperado (lo consumirán FT00022/FT00023), no
   una excepción. Esto difiere deliberadamente de los *fail-fast* de config
   (`PgVector`), que sí son errores de programación.
3. **Violaciones** (`CitizenSummaryViolation`, enum interno sin `Dto`):
   `MISSING_OFFICIAL_SOURCE`, `MISSING_WHAT_CHANGES`, `MISSING_WHO_IS_AFFECTED`,
   `BLANK_KEY_FIGURE`, `MISSING_DEADLINE`.
4. **Validador** (`CitizenSummaryValidator`): `validate(summary: ResumenDto,
   category: CategoriaDto): CitizenSummaryValidation`. Comprueba, acumulando
   violaciones en un `buildList`:
   - fuente oficial **obligatoria**: `fuenteOficial` no en blanco y con prefijo
     `http://`/`https://` (formato de enlace absoluto; la **alcanzabilidad** es
     FT00022);
   - «¿Qué cambia?» y «¿A quién afecta?» no vacíos;
   - cada entrada de `cifrasClave` no vacía (la lista **puede** estar vacía: no
     toda publicación tiene cifras; ver Open Questions);
   - variante `EMPLOYMENT_OR_SCHOLARSHIP` ⇒ `plazo != null` con `fechaLimite` no
     vacía.

Ubicación: `shared/src/commonMain/kotlin/es/aviferdev/datopublico/validation/`.
Se **reutiliza** `ResumenDto`/`CategoriaDto`/`PlazoDto`; **no** se crea un DTO
nuevo (evita duplicar el contrato y romper el wire). `:backend` no se toca.

## Expected File Changes

- `shared/src/commonMain/kotlin/es/aviferdev/datopublico/validation/CitizenSummaryVariant.kt`
  — create; enum de variante + resolver puro.
- `shared/src/commonMain/kotlin/es/aviferdev/datopublico/validation/CitizenSummaryValidation.kt`
  — create; enum `CitizenSummaryViolation` + `CitizenSummaryValidation`.
- `shared/src/commonMain/kotlin/es/aviferdev/datopublico/validation/CitizenSummaryValidator.kt`
  — create; `object` validador puro.
- `shared/src/commonTest/kotlin/es/aviferdev/datopublico/validation/CitizenSummaryValidatorTest.kt`
  — create; escenarios 2–5 y variante.
- `shared/src/commonTest/kotlin/es/aviferdev/datopublico/model/CitizenSummaryContractTest.kt`
  — create; escenarios 1 y 6 (round-trip + claves de wire).
- `docs/specs/contrato-resumen-ciudadano.md` (este spec, en el harness) — nota de
  cierre al implementar.

Total ≈ **5 ficheros de producto** + docs: muy por debajo del límite de 30.

## Visual Design Impact

- UI involved: no (contrato y validación; la UI del detalle es FT00033).
- Design source: `DESIGN.md` (bloques y plazo) solo como referencia de los campos.
- Screens or states affected: ninguno.
- New design artifact required: no.

## Durable Documentation Impact

- `ARCHITECTURE.md`: **update** — documentar el paquete `validation/` de `:shared`
  (validación de contrato pura) y la frontera «contrato (FT00019) vs. guardrails
  de contenido (FT00022)».
- `CONSTRAINTS.md`: **update** — nueva regla MUST del contrato del resumen
  ciudadano (fuente oficial obligatoria, tres secciones, plazo para empleo/becas)
  y la distinción contrato/guardrails.
- `AGENTS.md`: **not needed** — no cambian el flujo, el arranque ni las reglas
  operativas.
- Other docs: `docs/adr/0014-validacion-contrato-resumen-shared.md` — **create**
  (decisión durable: validación de contrato en `:shared`, pura y **sin excepción**,
  variante explícita) + índice; `.agents/skills/rag-datapublico/SKILL.md` §5 —
  **update** ligero (estado actual FT00019).

## Implementation Plan

1. Crear `CitizenSummaryVariant` + resolver puro con su KDoc y, si aplica, tests
   unitarios dentro de `CitizenSummaryValidatorTest`.
2. Crear `CitizenSummaryViolation` + `CitizenSummaryValidation`.
3. Crear `CitizenSummaryValidator` (una sola salida, `buildList`, sin `else if`,
   ≤40 líneas por función) reutilizando `ResumenDto`/`CategoriaDto`/`PlazoDto`.
4. Añadir los tests de validación (escenarios 2–5) y el test de contrato de wire
   (escenarios 1 y 6) con `DatoPublicoJson`.
5. Pasar el gate (`:shared:jvmTest`, `test`, `build -PskipClient`, `detekt`/
   `:cpdCheck`, `init.sh`) y registrar evidencia.
6. Actualizar `ARCHITECTURE.md`, `CONSTRAINTS.md`, el ADR 0014 y la skill; dejar
   la nota de cierre en este spec.

## Implementation Tasks

- [ ] `CitizenSummaryVariant` + `CitizenSummaryVariantResolver` (puros, sin `Dto`).
- [ ] `CitizenSummaryViolation` + `CitizenSummaryValidation` (`isValid` derivado).
- [ ] `CitizenSummaryValidator.validate(summary, category)` sin excepciones.
- [ ] Test de validación: sin fuente falla; tres secciones validan; empleo/beca
      sin plazo falla; norma sin plazo valida; cifra vacía falla.
- [ ] Test de contrato: round-trip de `ResumenDto` completo y claves de wire.
- [ ] Gate verde (`:shared:jvmTest --rerun-tasks`, `test`, `build -PskipClient`,
      `detekt` + `:cpdCheck`, `init.sh`).
- [ ] Documentación durable (ARCHITECTURE/CONSTRAINTS/ADR 0014/skill) y nota de
      cierre en el spec.

## Verification Plan

- `./gradlew :shared:jvmTest --rerun-tasks` (desde `..`, `JAVA_HOME` del JBR 21)
  → BUILD SUCCESSFUL; XML sin `failures`/`errors` (SmokeTest 1, CategoriaWireTest
  3, SerializationTest 7 + los tests nuevos de FT00019).
- `./gradlew test --rerun-tasks` → BUILD SUCCESSFUL (agrega `:shared:jvmTest`,
  `:backend:test`, `:composeApp:jvmTest`).
- `./gradlew build --no-daemon -PskipClient` → BUILD SUCCESSFUL (incluye
  `:shared:detekt` y `:cpdCheck`).
- `./gradlew detekt --rerun-tasks` → BUILD SUCCESSFUL.
- `env -u JAVA_HOME .harness/init.sh` → exit 0.
- Comprobación negativa por test: un `ResumenDto` con `fuenteOficial` en blanco
  hace fallar la validación (`isValid = false`).
- **E2E:** no aplica. No hay flujo de usuario, ruta ni endpoint (es contrato
  compartido); la cobertura correcta es unitaria en `:shared` y no se necesita el
  harness E2E persistente. Ningún test del gate hace red ni usa BD.

## Evidence To Capture

- Salida de `:shared:jvmTest` y recuentos XML (nuevos tests de FT00019, 0 fallos).
- Salida del gate (`test`, `build -PskipClient`, `detekt`/`:cpdCheck`, `init.sh`
  exit 0).
- Confirmación de que no se tocó `ResumenDto` (wire congelado) ni `:backend`.
- Registrar en `feature_list.json` (FT00019) y `PROGRESS.md`.

## Validator Checklist

- [ ] Implementación dentro del alcance (solo `:shared` `validation/` + tests +
      docs; sin generación, guardrails, persistencia, API ni UI).
- [ ] Escenarios 1–6 pasan.
- [ ] El validador es **puro** (sin red/BD/reloj/estado), **no lanza** y respeta
      un solo `return`, sin `else if` y ≤40 líneas por función.
- [ ] No se renombra ni se cambia el JSON de wire de `ResumenDto`.
- [ ] Evidencia presente y gate verde.
- [ ] E2E no necesario y justificado (contrato puro, sin flujo observable).
- [ ] `feature_list.json` y `PROGRESS.md` actualizados correctamente.
- [ ] Sin comportamiento de producto no relacionado.

## Open Questions / Risks

- **Cifras clave vacías**: se decide permitir `cifrasClave` vacía (no toda
  publicación tiene cifras; el Validation Plan solo mide «¿Qué cambia?» y «¿A
  quién afecta?»). Si el owner exige siempre al menos una cifra, se cambia a una
  violación nueva y se actualiza el spec.
- **Convocatoria sin plazo en la fuente** (edge case de `domain-model.md`): la
  variante empleo/beca exige `plazo`; si la fuente no lo trae, el resumen quedaría
  inválido y debería ir a revisión (FT00022/FT00023) en lugar de publicarse. La
  política fina (marcador explícito vs. revisión) no se resuelve aquí.
- **`ResumenDto` no tiene `estado`/`confianza`** (sí existen en la tabla
  `resumen`): son de FT00022/FT00023; no se añaden ahora.
- **Dependencia de PRs sin fusionar**: la rama parte del stack FT00016→FT00017→
  FT00018 (`accepted`, PR #17/#18/#19 sin fusionar); el rebase/merge de esos PRs
  puede afectar al diff base, no al contenido de esta feature (solo `:shared`).

## Notas de implementación (cierre FT00019)

Implementada 2026-10-10 en la rama `feat/ft00019-contrato-resumen-ciudadano`,
**solo** en `:shared` + documentación durable.

- Creados: `validation/CitizenSummaryVariant.kt` (enum interno
  `CitizenSummaryVariant` + `CitizenSummaryVariantResolver.variantFor`),
  `validation/CitizenSummaryValidation.kt` (`CitizenSummaryViolation` +
  `CitizenSummaryValidation` con `isValid` derivado) y
  `validation/CitizenSummaryValidator.kt` (`object` puro, `buildList`, sin
  excepciones).
- Tests: `CitizenSummaryValidatorTest` (12: escenarios 2–5 + variante +
  acumulación) y `CitizenSummaryContractTest` (3: escenarios 1 y 6). No se
  encontraron desviaciones respecto al plan.
- `ResumenDto` **sin cambios** (wire congelado); `:backend`, `:composeApp`,
  migraciones, CI e `init.sh` intactos.
- Gate verde: `:shared:jvmTest --rerun-tasks` (26 tests, 0 fallos: SmokeTest 1,
  CategoriaWireTest 3, SerializationTest 7, nuevos 15), `test` (3 módulos),
  `build --no-daemon -PskipClient` (23 tareas), `detekt --rerun-tasks` (4 tareas)
  + `:cpdCheck`, `env -u JAVA_HOME .harness/init.sh` → exit 0.
- Docs durables: `ARCHITECTURE.md` (`validation/` en `:shared` + frontera
  contrato/guardrails), `CONSTRAINTS.md` §«Contrato del resumen ciudadano»,
  ADR 0014 + índice, skill `rag-datapublico` §5.
