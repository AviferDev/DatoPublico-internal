# ADR 0003: Capa de datos con JDBC + HikariCP (sin ORM) y esquema relacional inicial

## Estado

Aceptado (2026-10-10). Decisión del dueño del proyecto, adoptada al implementar
`publicacion-persistencia` (FT00008). No supersede ningún ADR.

## Contexto

DatoPublico necesita persistir en PostgreSQL las publicaciones del BOE, sus
fragmentos (para el RAG), los resúmenes ciudadanos y la cola de revisión. Hasta
FT00008 el backend no tenía capa de datos: el driver PostgreSQL solo estaba en la
classpath de la tarea Flyway y no existía ningún pool ni repositorio.

El modelo de datos es **específico del dominio** (una `publicacion` con una
sección/epígrafe del BOE, un `fragmento` por chunk con embeddings futuros de
pgvector, un `resumen` 1:1 y una `cola_revision`) y el volumen esperado es
reducido. Las features siguientes (job de ingesta
FT00009, clasificación FT00012, chunking/embeddings FT00014/FT00016, resúmenes
FT00019, cola FT00023) van a escribir sobre estas tablas.

## Decisión

1. **Acceso a datos con JDBC + HikariCP, sin ORM.** No se usa Exposed,
   Hibernate ni ningún mapeador de objetos. Los repositorios escriben SQL
   parametrizado y traducen a modelos internos de dominio; el pool lo construye
   una fábrica en `infra/` (`Database`, tamaño pequeño ≤5) y lo cierra quien lo
   crea (job o test).
2. **Esquema relacional explícito con migraciones Flyway versionadas.** La
   migración `V2__persistencia_publicaciones.sql` crea `publicacion`, `fragmento`,
   `resumen` y `cola_revision` con PK/FK/índices. `V1` (extensión `vector` +
   `esquema_info`) no se edita.
3. **Lo diferido no se anticipa:** la columna `embedding vector(384)` de
   `fragmento` y su índice **HNSW** llegan con FT00016; los **valores** de
   `categoria` y `plazo` los rellena FT00012 (las columnas existen y son
   `nullable`).
4. **Idempotencia en la escritura de publicación:** `save` es un *upsert* por
   `id` (`INSERT … ON CONFLICT (id) DO UPDATE`), base de la idempotencia del job
   diario (FT00009).
5. **Configuración por entorno con fail-fast.** La conexión se **deriva** de
   `POSTGRES_*` (fuente única de verdad, compartida con `docker-compose` y
   Flyway); falta de `POSTGRES_PASSWORD` aborta con mensaje claro.
6. **Sin wiring en el arranque.** `Application.kt` no construye el pool; las
   features consumidoras lo inyectan.

## Alternativas consideradas

- **ORM (Exposed/Hibernate).** Descartado: añade dependencia y magia de mapeo
  para un modelo pequeño y muy específico; el SQL explícito es más simple y
  trazable, y encaja con el gate sin base de datos (los tests de contrato SQL no
  necesitan motor).
- **Driver JDBC sin pool.** Descartado: abrir/cerrar una conexión por operación
  encarece el job y no da límites; HikariCP es el pool estándar, ligero y sin
  dependencias pesadas.
- **`jsonb` para `cifras_clave`.** Descartado: `text[]` nativo es suficiente y
  más simple; si el contrato cambia se ajusta antes de producción.
- **Fuente de conexión propia (variables nuevas).** Descartado: duplicaría la
  configuración de Flyway/Compose; `POSTGRES_*` sigue siendo la única fuente.

## Consecuencias

- **Habilita** la ingesta persistente (FT00009), el chunking/embeddings
  (FT00014/FT00016), los resúmenes (FT00019) y la cola de revisión (FT00023) sin
  reescribir SQL cada vez.
- **Cuesta** escribir y mantener SQL a mano y mapear fila ↔ dominio; los
  repositorios secundarios son mínimos y provisionales hasta sus features.
- El **gate no ejecuta la verificación real** (necesita PostgreSQL): cubre config
  de conexión, mapeo y contrato SQL. La prueba real es **opt-in** por
  `DB_LIVE_TEST=1` contra el `docker-compose`, fuera de `build`/`test`/CI.
- Duradero: regla **MUST** en `CONSTRAINTS.md` (JDBC + HikariCP sin ORM; pruebas
  de BD opt-in; *upsert* idempotente) y descripción en `ARCHITECTURE.md`.
