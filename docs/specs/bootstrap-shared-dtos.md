# Feature Implementation Spec: DTOs compartidos con kotlinx.serialization

## Source Feature

- `id`: bootstrap-shared-dtos
- `ft_id`: FT00002
- `parts`: none (atomic)
- `area`: fundaciones
- `depends_on`: bootstrap-monorepo-gradle (FT00001, `accepted`)
- `status`: accepted (2026-10-10; reabierta para aplicar la convención de nombres `Dto` — ver nota)
- `source`: `feature_list.json`

## Nota de reparación: convención de nombres (2026-10-10)

Tras la aceptación inicial, se reabrió esta feature para aplicar la **convención
de nombres** de `:shared` (ver `ARCHITECTURE.md` §Convenciones de nombres y la
regla MUST de `CONSTRAINTS.md`). **Todos los tipos serializables del contrato**
llevan sufijo **`Dto`**: las `data class` y también los **enums de wire**:

- `Publicacion` → **`PublicacionDto`**
- `Resumen` → **`ResumenDto`**
- `Plazo` → **`PlazoDto`**
- `DailySummary` → **`ResumenDiarioDto`**
- `Categoria` → **`CategoriaDto`** (enum de wire de 11 valores)
- `SeccionBoe` → **`SeccionBoeDto`** (enum de wire)

Se mantiene **sin cambios** y **sin** `Dto` la configuración de serialización
`DatoPublicoJson` (no es un tipo de contrato). Donde en el resto de este spec se
lea `Publicacion`, `Resumen`, `Plazo`, `DailySummary`, `Categoria` o `SeccionBoe`,
debe entenderse el nombre `...Dto` correspondiente, y donde diga
`Categoria.kt`/`SeccionBoe.kt` debe entenderse `CategoriaDto.kt`/`SeccionBoeDto.kt`.
El token de wire y el JSON no cambian: es un renombrado de tipos Kotlin, no del
contrato.

## Nota de reparación: alcance 1.0.0 y `@SerialName` (2026-10-10, reapertura)

Cambio decidido por el owner (1.0.0 = **todo el sumario del BOE**; ver MUST en
`CONSTRAINTS.md` §Producto y datos) y norma de serialización nueva (MUST en
`CONSTRAINTS.md` §«Serialización»: cada propiedad lleva `@SerialName` explícito
aunque el nombre Kotlin coincida). Aplicado a esta feature sin cambiar el JSON de
wire:

- `SeccionBoeDto` amplía sus valores de 5 a **8**: se añaden `IV` (`@SerialName
  "IV"`), `V_A` (`"V.A"`) y `V_C` (`"V.C"`), conservando `I`, `II.A`, `II.B`,
  `III` y `V.B`. Ninguna sección se excluye.
- `PublicacionDto`, `ResumenDto`, `PlazoDto` y `ResumenDiarioDto`: **cada
  propiedad** lleva `@SerialName` explícito (`"id"`, `"titulo"`, `"queCambia"`…).
  El nombre JSON y los tokens de enum no cambian; es una anotación redundante
  deliberada.
- `CategoriaDto` y `SeccionBoeDto` ya anotaban sus valores de enum; se verifican
  los 11 y los 8 tokens.

Evidencia en `feature_list.json` (FT00002) y `PROGRESS.md`; tests actualizados en
`CategoriaWireTest` (8 secciones) sin tocar el JSON de wire.

## Goal

Dotar al módulo `:shared` del **contrato de datos base** que backend y cliente
comparten, serializable con `kotlinx.serialization`: los DTO de dominio
**Publicación** (`Publicacion`), **Categoría** (`Categoria`, enum curado de 11
valores), **Sección/Epígrafe** del BOE, **Plazo** de convocatoria, **Resumen
ciudadano** (`Resumen`) y el **feed diario** (`DailySummary`). Es la base de
`docs/roadmap.md` 0.1-T02 y el punto de apoyo de la ingesta, el contrato de
resumen (FT00019) y la API pública.

Esta feature **solo** define tipos y su serialización JSON. No contiene lógica de
negocio, validación de dominio, reglas de clasificación, Ktor ni persistencia.

## Non-Goals

- Reglas de clasificación epígrafe→categoría y extracción de plazos → FT00012.
- Validación del contrato de resumen (fuente obligatoria) → FT00019.
- DTO de **Consulta** (chat RAG) y sus estados → features de chat (FT00025,
  FT00031). Solo se cubre `Resumen`.
- Persistencia/repositorios, endpoints Ktor, `ktor-serialization`, UI y lógica de
  destacados o confianza (FT00013, FT00019+).

## Job Story

Cuando el backend ingiere una publicación y el cliente la consume,
quiero un contrato de datos único y estable en `:shared`,
para que ambos lados hablen el mismo JSON sin duplicar modelos ni acoplarse a
detalles internos.

## Users And Permissions

- Desarrollador: define y testea los DTO en `commonTest`. `:backend` y
  `:composeApp` son consumidores. Sin cuentas ni actores de usuario final.

## Acceptance Scenarios

### Scenario 1: ida y vuelta de una publicación

Given un `Publicacion` con id, título, fecha ISO-8601, organismo, sección,
epígrafe, categoría, URL oficial y un `Resumen` embebido,
When se serializa a JSON y se deserializa de vuelta,
Then el objeto resultante es igual al original (`equals`).

### Scenario 2: categorías con token de wire estable

Given el enum `Categoria` con sus 11 valores curados,
When se serializa cada valor,
Then usa su token `@SerialName` en `snake_case` (sin acentos ni espacios) y
deserializa al mismo valor.

### Scenario 3: campos opcionales ausentes y plazo

Given un `Publicacion` sin `plazo`, `epigrafe` ni `resumen`, y otro con un
`Plazo` de fecha límite ISO-8601,
When se serializan y deserializan,
Then los opcionales quedan `null`/vacíos sin fallar y la fecha límite viaja como
`String` ISO-8601 (sin `java.time`, válido en `commonMain`) intacta.

### Scenario 4: tolerancia a campos desconocidos

Given un JSON de `DailySummary` con un campo extra no declarado,
When se deserializa con el `Json` compartido (`ignoreUnknownKeys = true`),
Then se decodifica correctamente y el campo extra se ignora.

## Repository Research

### Files Inspected

- `.harness/feature_list.json`, `PROGRESS.md` — entrada FT00002 y estado real del
  monorepo (FT00001 `accepted`, tareas de build verdes).
- `.harness/docs/roadmap.md` §0.1.0 (0.1-T02) y `docs/domain-model.md`,
  `CONTEXT.md` — entidades `Publicación`, `Categoría` (11),
  `Sección/Epígrafe`, `Plazo`, `Resumen ciudadano`, `Fuente oficial` y glosario.
- `.harness/ARCHITECTURE.md`, `CONSTRAINTS.md` y skills
  `ktor-backend-architecture`/`compose-multiplatform-architecture` — `:shared` =
  DTOs con `kotlinx.serialization`, namespace raíz, sin `java.time` en
  `commonMain`.
- Producto `..`: `shared/build.gradle.kts` (KMP con solo `jvm()`, toolchain 21,
  `commonTest`), `shared/src/commonTest/.../SmokeTest.kt`,
  `gradle/libs.versions.toml` (ya predeclara `kotlinx-serialization-json` 1.8.0 y
  el plugin `kotlin-serialization`), `backend/build.gradle.kts`
  (`implementation(project(":shared"))`) y `settings.gradle.kts`.
- Producto: `git branch` → `feat/ft00002-bootstrap-shared-dtos`; rama en `origin`
  (claim hecho).

### Existing Patterns To Follow

- Namespace raíz `es.aviferdev.datopublico`; los DTO viven en `:shared`.
- Version catalog + Kotlin DSL; el plugin
  `org.jetbrains.kotlin.plugin.serialization` y `kotlinx-serialization-json` ya
  están declarados y sin activar.
- Solo target `jvm()` hasta FT00005: el código debe ser multiplataforma real
  (`commonMain` sin APIs JVM).
- Commits con scope `FT00002` (`docs/git-workflow.md`).

### Current Gaps

- `:shared` no aplica el plugin de serialización ni declara `commonMain`.
- No existe paquete ni fichero de DTO (solo el `SmokeTest.kt`).
- Desajuste de nombres: el roadmap usa `DailySummary`/`SourceCategory` (inglés),
  pero el dominio acordado usa **Publicación** y **Categoría**; se adopta el
  nombre de dominio en castellano.
- La verificación de `feature_list.json` cita `./gradlew :shared:test`, tarea
  inexistente en KMP (sí `:shared:jvmTest`). Ver *Verification Plan*.

## Technical Approach

Contrato de datos puro, sin lógica, en `:shared`:

1. **Activar serialización en `:shared`** (`shared/build.gradle.kts`): aplicar
   `alias(libs.plugins.kotlin.serialization)` y añadir
   `implementation(libs.kotlinx.serialization.json)` a `commonMain`.
2. **DTO y enums** en `commonMain`, bajo
   `es.aviferdev.datopublico.model`, todos anotados `@Serializable`:
   - `Categoria` (enum, 11 valores) con `@SerialName` en `snake_case`: tokens
     estables de wire (p. ej. `normas_y_legislacion`). **El token es contrato**:
     no renombrar sin migración.
   - `SeccionBoe` (enum: `I`, `II_A`, `II_B`, `III`, `V_B`) con `@SerialName`
     `"I"`, `"II.A"`, `"II.B"`, `"III"`, `"V.B"`.
   - `Plazo` (`data class`): `fechaLimite: String` (ISO-8601) y
     `descripcion: String?`. Sin `java.time` (rompe iOS/Wasm).
   - `Resumen` (`data class`): `queCambia: String`, `aQuienAfecta: String`,
     `cifrasClave: List<String> = emptyList()`, `fuenteOficial: String`,
     `avisoIA: Boolean = true`, `plazo: Plazo? = null`. La **obligatoriedad y
     validación** de `fuenteOficial` las aplica FT00019; aquí solo se modela.
   - `Publicacion` (`data class`): `id: String`, `titulo: String`,
     `fechaPublicacion: String` (ISO-8601), `organismo: String?`,
     `seccion: SeccionBoe`, `epigrafe: String?`, `categoria: Categoria`,
     `urlOficial: String`, `resumen: Resumen? = null`, `plazo: Plazo? = null`.
   - `DailySummary` (`data class`): `fecha: String` (ISO-8601) y
     `publicaciones: List<Publicacion> = emptyList()`.
3. **`Json` compartido** en `es.aviferdev.datopublico.serialization`:
   `val DatoPublicoJson = Json { ignoreUnknownKeys = true; encodeDefaults = true }`,
   coherente y tolerante a evolución para backend y cliente.
4. **Fechas como `String` ISO-8601** (sin `java.time`, válido en `commonMain`); el
   formateo localizado pertenece a cada plataforma o a features posteriores.
5. **Tests de round-trip** en `commonTest`: cada DTO, tokens de enum, opcionales y
   `ignoreUnknownKeys`.

No se añaden dependencias fuera de las ya predeclaradas ni se toca la raíz del
build ni otros módulos.

## Expected File Changes

Rutas en el repo de producto (`..`):

- `shared/build.gradle.kts` — modify; aplicar plugin serialization y dependencia
  `commonMain` de `kotlinx-serialization-json`.
- `shared/src/commonMain/kotlin/es/aviferdev/datopublico/model/` — create
  `Categoria.kt`, `SeccionBoe.kt`, `PlazoDto.kt`, `ResumenDto.kt`,
  `PublicacionDto.kt` y `ResumenDiarioDto.kt` (nombres tras la convención `Dto`).
- `shared/src/commonMain/kotlin/es/aviferdev/datopublico/serialization/DatoPublicoJson.kt` — create.
- `shared/src/commonTest/kotlin/es/aviferdev/datopublico/model/` — create
  `SerializationTest.kt` y `CategoriaWireTest.kt`.
- `shared/src/commonTest/.../SmokeTest.kt` — keep as-is (no tocar).

Provisional: el paquete `...model`/`...serialization` es una propuesta razonable
dentro del namespace raíz; si el implementer prefiere un único paquete
`es.aviferdev.datopublico`, debe justificarlo en la evidencia.

## Visual Design Impact

- UI involved: no. No hay pantallas, tokens ni textos de UI en esta feature.

## Durable Documentation Impact

- `ARCHITECTURE.md` (harness): not needed — ya describe `:shared` como DTOs con
  `kotlinx.serialization` y el namespace raíz.
- `CONSTRAINTS.md`: not needed — no introduce MUST/MUST NOT nuevos.
- `AGENTS.md` (harness): not needed — no cambia flujo ni arranque.
- Otros: ninguno. El token de wire de `Categoria` se documenta con KDoc en el
  propio enum.

## Implementation Plan

1. Activar el plugin de serialización y la dependencia JSON en `:shared`.
2. Crear enums (`Categoria`, `SeccionBoe`) con `@SerialName` de wire estable.
3. Crear `Plazo`, `Resumen`, `Publicacion` y `DailySummary` como `data class`
   inmutables `@Serializable`.
4. Añadir el `Json` compartido (`DatoPublicoJson`).
5. Escribir tests de round-trip, tokens de enum, opcionales y campos desconocidos.
6. Ejecutar `./gradlew build` y `./gradlew test` en verde; commit `FT00002`, push
   y PR (CI).

## Implementation Tasks

- [ ] `shared/build.gradle.kts`: plugin serialization + `commonMain` con
      `libs.kotlinx.serialization.json`.
- [ ] `Categoria` con los 11 valores y `@SerialName` `snake_case`.
- [ ] `SeccionBoe` con tokens `I`, `II.A`, `II.B`, `III`, `V.B`.
- [ ] `Plazo` (fecha ISO-8601 como `String`, sin `java.time`).
- [ ] `Resumen` con las secciones ciudadanas, `fuenteOficial` y `avisoIA`.
- [ ] `Publicacion` con metadatos de sección/epígrafe y categoría.
- [ ] `DailySummary` con fecha y lista de publicaciones.
- [ ] `DatoPublicoJson` (`ignoreUnknownKeys`, `encodeDefaults`).
- [ ] Tests: round-trip de cada DTO, token de enum y campos opcionales/desconocidos.
- [ ] `./gradlew build` y `./gradlew test` verdes; commit/push/PR con scope
      `FT00002`.

## Verification Plan

- Desde la raíz del producto (`..`, JDK 21 vía JBR/`JAVA_HOME`):
  - `./gradlew :shared:jvmTest` → `BUILD SUCCESSFUL` con los nuevos tests.
    **Nota:** la verificación de `feature_list.json` cita `./gradlew :shared:test`,
    tarea inexistente en KMP; la equivalencia real es `:shared:jvmTest` (y la task
    raíz `test`). El validator debe aceptar `:shared:jvmTest` como cumplimiento.
  - `./gradlew test` → ejecuta `:shared:jvmTest`, `:backend:test` y
    `:composeApp:jvmTest` en verde (task raíz agregadora de FT00001).
  - `./gradlew build` → `BUILD SUCCESSFUL` (compila `:shared` y sus consumidores).
- Comprobación manual de contrato: serializar cada enum y verificar el token de
  wire esperado (p. ej. `normas_y_legislacion`, `II.B`).
- E2E: no aplica. No hay flujo de usuario, ruta, autenticación ni API; los tests
  unitarios de round-trip en `commonTest` son la cobertura adecuada.
- `init.sh` (harness): no se modifica; sigue siendo el gate no bloqueante que
  ejecuta `./gradlew build` y no arranca servidores.

## Evidence To Capture

- Salida de `./gradlew :shared:jvmTest` y `./gradlew test` (3 módulos, tests
  nuevos verdes) y de `./gradlew build`.
- Nombres de los tests de serialización y un ejemplo de JSON round-trip de
  `Publicacion`/`Categoria`.
- Lista de ficheros del commit `FT00002` y estado de CI en el PR.
- Entrada breve en `PROGRESS.md` y `feature_list.json` (`evidence`).

## Validator Checklist

- [ ] Implementation stays within this feature's scope (sin lógica de negocio,
      clasificación, validación de resumen, Ktor, persistencia ni UI).
- [ ] Los 11 valores de `Categoria` existen con token de wire estable.
- [ ] `Publicacion`, `Resumen`, `Plazo`, `DailySummary` y `SeccionBoe` son
      `@Serializable` y hacen round-trip.
- [ ] No se usa `java.time` ni APIs JVM en `commonMain`.
- [ ] Los tests de serialización existen y pasan (`:shared:jvmTest`).
- [ ] Se respetó la equivalencia `:shared:jvmTest` ↔ `:shared:test` de la
      verificación de `feature_list.json`.
- [ ] `feature_list.json` y `PROGRESS.md` actualizados correctamente.
- [ ] No unrelated product behavior or extra feature work was added.
