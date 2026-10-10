---
name: ktor-backend-architecture
description: Guía de arquitectura del backend Kotlin + Ktor (módulo :backend) de DatoPublico. Úsala al añadir o modificar endpoints/plugins, servicios de aplicación, dominio, repositorios y migraciones (PostgreSQL/pgvector/Flyway), ingesta del BOE, pipeline RAG (embeddings ONNX + pgvector), generación de resúmenes y chat con OpenCode, destacados, configuración por entorno, composición de dependencias, errores, observabilidad, Docker o tests. Define la dirección de dependencias, el layout de paquetes y las reglas, y distingue el patrón objetivo del estado actual (aún no bootstrapped).
---

# Arquitectura del backend Ktor — DatoPublico

Guía práctica para trabajar en `:backend`. Antes de tocar el backend, lee
`docs/technical-discovery.md`, `docs/domain-model.md` y `docs/roadmap.md`.
`CONTEXT.md` fija el lenguaje de dominio: usa esos términos (**Publicación**,
Norma, Empleo público, Becas y subvenciones, Fragmento, Resumen ciudadano,
Consulta, Destacado).

**Estado actual:** ya existe el **esqueleto del backend** (FT00004): composition
root en `Application.kt`, paquetes `plugins/` e `infra/`, endpoint `GET /health`,
configuración por entorno y logging JSON (Logback). Los paquetes de dominio
(`ingesta/`, `clasificacion/`, `rag/`, `resumen/`, `destacados/`, `consulta/`,
`api/`) aún no existen. El resto del documento sigue siendo el **patrón objetivo
acordado**, derivado de `docs/technical-discovery.md` y `docs/roadmap.md`; deriva
los detalles reales del código cuando existan.

## Stack y topología de build (decidido)

- Kotlin/JVM (toolchain **JDK 21**) + **Ktor 3.x** con motor **Netty**;
  `application` plugin de Gradle.
- Multi-proyecto Gradle (Kotlin DSL) con **version catalog** y módulos
  `shared`, `backend`, `composeApp`. `:backend` depende de `:shared`.
- **Namespace raíz:** `es.aviferdev.datopublico` (compartido por todos los
  módulos). El backend usa `es.aviferdev.datopublico.backend`.
- Serialización `kotlinx.serialization` + `ktor-serialization-kotlinx-json`;
  corrutinas para I/O paralelo.
- Persistencia **PostgreSQL + pgvector** (JDBC + **HikariCP**; migraciones
  **Flyway**). No hay Redis ni caché externa en la 1.0.0.
- IA: **OpenAI-compatible** contra OpenCode; **embeddings locales** con
  **ONNX Runtime (CPU)**.
- Infra local con **Docker Compose** (`postgres` con pgvector + `backend`) y
  `Dockerfile` multi-stage.
- Gate estándar: `./init.sh` (desde `.harness/`). Compilar/tests desde la raíz
  del repo público: `./gradlew build`, `./gradlew :backend:test`.

## Regla de dependencia (invariante)

```
plugins/ (HTTP Ktor)  ->  <feature>/ servicios de aplicación  ->  <feature>/ dominio puro
                                     |                                      ^
                                     v                                      |
                        <feature>/ repositorios y clientes  -->  infra/ (config, pools, migraciones)
```

- La capa HTTP (`plugins/`) conoce Ktor y los DTOs de transporte; **no** contiene
  lógica de negocio.
- Los **servicios** orquestan (validación, coordinación de I/O, transacciones
  lógicas). No conocen tipos de Ktor (`ApplicationCall`, `Route`,
  `HttpStatusCode`).
- El **dominio** es puro: sin E/S, sin Ktor, sin BD, sin ONNX, sin OpenCode. Es lo
  más fácil de testear.
- Los **repositorios y clientes** implementan interfaces declaradas por el
  consumidor (el servicio); encapsulan SQL o HTTP y traducen a modelos de dominio.
- Prohibido: una ruta que consulte la BD directamente; un servicio que importe
  `io.ktor.server.*`; dominio que dependa de JDBC, ONNX o HTTP.

## Layout de paquetes (feature-first con roles)

```
backend/src/main/kotlin/es/aviferdev/datopublico/backend/
  Application.kt          # composition root: config, wiring manual y arranque
  plugins/                # Ktor: serialization, routing por área, CORS, rate limit, health, errors, docs
  ingesta/                # sumario BOE, parser por sección, job (9:30 + 2ª pasada), backfill, dedup
  clasificacion/          # categoría (Norma/Empleo/Becas) y extracción de plazos
  rag/                    # chunking, embeddings ONNX, indexado pgvector, recuperación híbrida
  resumen/                # generación ciudadana, contrato, guardrails, caché, cola de revisión
  destacados/             # ranking diario por señales objetivas
  consulta/               # chat: pregunta/verificación contra el corpus
  api/                    # endpoints de solo lectura (feed, detalle, búsqueda, chat)
  infra/                  # config, DataSource/Hikari, migraciones, cliente OpenCode, runtime ONNX
backend/src/main/resources/
  db/migration/           # Flyway: V1__descripcion.sql, V2__..., nunca editar una ya aplicada
  openapi/openapi.json
  logback.xml
backend/src/test/kotlin/es/aviferdev/datopublico/backend/   # tests espejo del paquete de producción
```

Un paquete por feature, no por capa técnica. Dentro del paquete conviven su
servicio, su(s) repositorio(s), sus modelos y sus clientes; lo transversal
(config, DB, HTTP, ONNX, OpenCode) va en `infra/` y `plugins/`.

## Composition root y wiring

- Todo el cableado vive en `Application.kt`. **Sin framework de DI** (no
  Koin/Hilt/Spring en el backend).
- Los subsistemas se construyen **condicionalmente** según sus dependencias
  (config de entorno, `dataSource`, clave de OpenCode, runtime ONNX) y pueden
  quedar a `null`. El arranque **solo registra las rutas cuyas dependencias
  existen**, para levantar en entornos parciales (p. ej. solo salud).
- Los recursos con ciclo de vida (pool JDBC, runtime ONNX, cliente HTTP) se
  cierran al parar el servidor. No uses estado global mutable: pasa por
  constructor.
- `configureRouting(...)` recibe colaboradores opcionales; las rutas se declaran
  como `fun Route.xRoutes(dep)`.

## Dominio

- Términos canónicos en `CONTEXT.md`. El feed es de **Publicaciones** con una
  **Categoría** (enum curado de 11) y metadatos de **Sección/Epígrafe** del BOE;
  "Norma" es solo la Sección I.
- Estados: `Resumen ciudadano` (`pendiente → generado → validado_por_guardrails →
  publicado | en_cola_revision`) y `Consulta` (`recibida → respondida |
  refutada | sin_fundamento`). Ver `docs/domain-model.md`.
- Regla dura: **trazabilidad**. Ningún resumen se publica sin enlace a la fuente
  oficial.

## Persistencia y migraciones

- Tablas base: `publicacion` (con categoría y plazo), `fragmento` (con embedding),
  `resumen`, `cola_revision`. Ver `docs/technical-discovery.md`.
- `pgvector`: dimensión de embedding **384** (`multilingual-e5-small`), índice
  **HNSW**; filtros SQL por metadatos (fecha, categoría, organismo).
- Migraciones con Flyway versionadas; **nunca** edites una migración ya aplicada.
- Idempotencia y deduplicación en la ingesta; el job puede reejecutarse sin
  duplicar.

## IA (abstracción de proveedor)

- **Embeddings:** `intfloat/multilingual-e5-small` **int8** vía ONNX Runtime en
  CPU (384 dims, 512 tokens, prefijos `query:`/`passage:`). El modelo vive tras
  una interfaz de proveedor (`-base` como alternativa). Detalles en la skill
  `rag-datopublico`.
- **Generación y chat:** **OpenCode** (endpoint OpenAI-compatible, candidato
  `deepseek-v4.1-flash`) tras una interfaz intercambiable. La **clave vive solo
  en el servidor** (variable de entorno), nunca en el cliente ni en logs.
- OpenCode **no** ofrece embeddings: por eso los embeddings son locales.

## Ingesta y operación

- Job diario a las **9:30** (cron) con **segunda pasada** por la tarde.
- Ingesta de las **Secciones I, II.A, II.B, III y V.B** (fuera IV y V.A);
  clasificación en las **11 categorías** curadas a partir de sección/epígrafe del
  BOE y extracción de **plazos** de convocatorias.
- Backfill del **último año** por lotes, en horario de baja carga.
- Observabilidad: logs estructurados; alerta si falta la ingesta de las 9:30 o la
  segunda pasada; métrica de tokens/consultas del chat. **Sin telemetría de uso.**

## API

- Solo lectura y pública: `feed` (con destacados y categorías), `detalle`,
  `búsqueda` (filtros de categoría/fecha) y `chat` (pregunta/verificación).
- Contratos **OpenAPI** versionados; **CORS**; **rate limiting**; errores JSON
  consistentes.
- Sin cuentas ni datos personales: el servidor solo trata información pública. El
  chat no persiste historial.

## Tests

- Unitarios de ingesta, parsers por sección, clasificación, guardrails y
  destacados.
- Fixtures reales del BOE de las tres secciones.
- Evaluación de recuperación (precision/recall) y **golden set** de resúmenes.
- Chat: respuestas con citas, refutación de afirmaciones falsas y `sin_fundamento`.

## Docker y entorno local

- `docker compose up -d` levanta PostgreSQL con pgvector (+ el backend en prod).
  En **local**, las migraciones se aplican con una tarea **explícita**
  (`./gradlew :backend:flywayMigrate`; `flywayInfo` para inspeccionar), **no**
  enganchada a `build`/`check` (la CI corre sin BD). El backend en producción
  aplicará migraciones al arrancar (feature posterior a FT00004; el esqueleto de
  FT00004 no cablea Flyway).
- En macOS el proyecto usa **Colima**; si se rompe la red host↔contenedor,
  `colima restart` (los contenedores con `restart=unless-stopped` vuelven solos).
- Servidor real: **Intel N100 / 8 GB**. Ajustes: `shared_buffers` PostgreSQL
  ~1 GB, heap JVM ~1 GB, swap activado; el backfill se ejecuta por lotes.

## Anti-patrones (prohibido)

- SQL en una ruta de Ktor; lógica de negocio en `plugins/`.
- Dominio que importe Ktor/JDBC/ONNX/OpenCode.
- Clave de OpenCode o del modelo en el cliente o en el repositorio.
- Publicar un resumen sin enlace a la fuente oficial.
- Añadir analítica de uso o almacenar datos personales.
