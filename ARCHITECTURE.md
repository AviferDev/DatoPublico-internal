# Architecture — DatoPublico

> Mapa durable de módulos y fronteras. **No** es un inventario de ficheros. El
> detalle por módulo vive en las skills `ktor-backend-architecture`,
> `compose-multiplatform-architecture` y `rag-datapublico`.

## Módulos (monorepo Gradle)

- **`:shared`** — DTOs y lógica compartida con `kotlinx.serialization`.
  Namespace `es.aviferdev.datopublico`.
- **`:backend`** — Ktor: ingesta del BOE, RAG, resúmenes, destacados y API.
  Namespace `es.aviferdev.datopublico.backend`. Ya existe el **esqueleto**
  (composition root `Application.kt`, `plugins/` e `infra/`, `GET /health`,
  configuración por entorno y logging JSON) y empieza a existir **`ingesta/`**
  (`ingesta/sumario/`: cliente del sumario diario del BOE + modelo interno y
  filtrado de secciones); el resto de paquetes llega con sus features. El
  cliente de ingesta **no** se cablea en el arranque.
- **`:composeApp`** — cliente Compose Multiplatform (Android, iOS, Web).
  Namespace `es.aviferdev.datopublico`. Ya **existe y compila** para
  `androidTarget`, `iosArm64`/`iosSimulatorArm64` (framework `ComposeApp`) y
  `wasmJs` (browser, ejecutable), con la **UI compartida en `commonMain`**
  (`App()`) y un entrypoint por plataforma; además conserva `jvm()` **solo** para
  tests/dev. Aún **no** depende de `:shared` (llega con la primera UI que necesite
  DTOs, FT00032).

## Build y gate

- Raíz Gradle multi-proyecto (Kotlin DSL) con **version catalog** (`gradle/libs.versions.toml`).
- `:shared` y `:backend` son **SDK-free**; `:composeApp` aplica AGP (exige el Android SDK)
  y se incluye salvo con `-PskipClient`.
- **Gate de calidad bloqueante**: **Detekt** por módulo (`config/detekt/detekt.yml` +
  `config/detekt/<módulo>-baseline.xml`) y **CPD** global (`:cpdCheck`, PMD, umbral 100
  tokens); `check`/`build` y `.harness/init.sh` los ejecutan. Un hallazgo nuevo o un
  duplicado rompe el build.
- **Gate estándar** (`.harness/init.sh`, SDK-free): `./gradlew build -PskipClient` +
  `./gradlew detekt`. Con `--with-client`/`--with-ios`/`--with-all` se añade el cliente
  (Android/Web, iOS).
- **Migraciones** Flyway con tareas explícitas (`./gradlew :backend:flywayMigrate`), fuera
  de `check`; la CI no necesita base de datos.

## Fronteras

- **Cliente → API HTTP** (público, solo lectura). El cliente no conoce los
  internals del backend.
- **Backend → BOE** (API de datos abiertos, solo lectura, **sin clave ni
  credenciales**): `ingesta/` obtiene el sumario diario; el resto de la
  integración (parser, persistencia, job) llega con sus features. Es una
  dependencia **externa en tiempo de ejecución**, no del gate: los tests del gate
  no hacen red y las pruebas contra el BOE son opt-in.
- **Backend:** `plugins/` (HTTP) → servicios → dominio puro → repositorios y
  clientes → `infra/`.
- **IA:** embeddings **locales** (ONNX) y generación/chat **remoto** (OpenCode),
  cada uno tras una interfaz intercambiable.
- **Datos:** PostgreSQL + pgvector; migraciones Flyway. Sin cuentas ni datos
  personales.

## Reglas transversales

- El dominio es puro (sin Ktor, JDBC, ONNX ni HTTP).
- **Trazabilidad** obligatoria: todo resumen apunta a la fuente oficial.
- Secretos y claves **solo** por entorno, en el servidor.
- El texto de UI vive en recursos y en castellano.

## Convenciones de nombres

- **Todo tipo `@Serializable`/de transporte** lleva sufijo **`Dto`**: el contrato
  de **`:shared`** (las `data class` `PublicacionDto`, `ResumenDto`, `PlazoDto`,
  `ResumenDiarioDto` y los **enums de wire** `CategoriaDto`, `SeccionBoeDto`) y
  también los DTOs de transporte de **`:backend`** (`HealthDto`,
  `BoeSumarioResponseDto`, `BoeSeccionDto`…). Aplica a **cualquier** tipo
  `@Serializable`, no solo a los contenedores.
- La **configuración de serialización** (`DatoPublicoJson`) **no** es un tipo de
  contrato y va **sin** `Dto`.
- **Todo tipo `@Serializable`**: cada propiedad lleva `@SerialName` explícito,
  aunque el nombre coincida con la clave de wire (sin depender del nombre por
  defecto); los valores de los enums de wire también lo llevan.
- En las capas internas: entidades de persistencia `...Entity`, filas `...Row`,
  modelos de UI `...Ui`. Un **modelo de dominio/valor interno** que no sea
  serializable ni `Entity`/`Row`/`Ui` va **sin sufijo** (p. ej. `EntradaSumario`).
- **Sin prefijos** (nada de notación húngara).
