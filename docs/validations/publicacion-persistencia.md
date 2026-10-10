# Validación — `publicacion-persistencia` (FT00008)

- Veredicto: **`accept`**
- Fecha: 2026-10-10
- Rol: `validator` (independiente, solo lectura; no implementa ni corrige)
- Spec: `.harness/docs/specs/publicacion-persistencia.md`
- Rama: `feat/ft00008-publicacion-persistencia` (commit `chore(FT00008): claim`;
  cambios de la feature **sin commitear** en el árbol de trabajo)
- Estado en `feature_list.json`: `passing` (listo para validación)
- Repo de producto: `..` (JAVA_HOME = JBR 21 de Android Studio)

## Checks reejecutados (salidas reales)

| Comando | Resultado |
| --- | --- |
| `./gradlew :backend:test --rerun-tasks -PskipClient --no-daemon` | BUILD SUCCESSFUL; **61** tests, 0 fallos. Nuevos: `ConfiguracionBdTest` 8, `MigracionSqlTest` 4, `PublicacionPersistenciaTest` 5, `PublicacionPersistenciaLiveTest` 1 (no-op sin `DB_LIVE_TEST`). |
| `./gradlew build --no-daemon -PskipClient` | BUILD SUCCESSFUL (23 tareas). |
| `./gradlew test --no-daemon` (con Android SDK) | BUILD SUCCESSFUL; `:shared:jvmTest` + `:backend:test` + `:composeApp:jvmTest`. |
| `./gradlew detekt -PskipClient --rerun-tasks --no-daemon` | BUILD SUCCESSFUL; Detekt + `:cpdCheck` sin hallazgos (analiza el código nuevo). |
| `.harness/init.sh` | **exit 0** («Gate OK»; build -PskipClient + detekt). |
| `cp .env.example .env && docker compose up -d` | `datopublico-postgres` **healthy**; sin conflicto en `127.0.0.1:5432`. |
| `./gradlew :backend:flywayMigrate` | BUILD SUCCESSFUL. |
| `./gradlew :backend:flywayInfo` | V1 `esquema base` **Success** y V2 `persistencia publicaciones` **Success**. |
| `information_schema.tables` / FK | Cuatro tablas presentes (`publicacion`, `fragmento`, `resumen`, `cola_revision`) + `esquema_info`/`flyway_schema_history`; 3 FK con `delete_rule = CASCADE`. |
| `DB_LIVE_TEST=1 ./gradlew :backend:test --tests '*PublicacionPersistenciaLiveTest' --rerun-tasks` | BUILD SUCCESSFUL; 1 test, 0 fallos. El `system-out` muestra el pool Hikari arrancando y añadiendo conexión (cuerpo **ejecutado**, no omitido); al terminar, las 4 tablas quedan vacías (limpieza correcta). |
| `docker compose down -v` + `rm .env` | Contenedor, volumen y red `datopublico_*` eliminados; `.env` borrado; `.env` nunca aparece en `git status` (ignorado). |

> Evidencia de recuento: parser de los XML de `backend/build/test-results/test/` →
> `TOTAL tests=61 failures=0 errors=0 skipped=0`. Los tests `*LiveTest` (BOE y
> persistencia) no usan el flag *skip* de JUnit: se autoprotegen por variable de
> entorno, por lo que el gate confirma que **no** abren red ni BD.

## Escenarios del spec

1. **Guardar/recuperar con metadatos** — cubierto por `PublicacionPersistenciaLiveTest`
   (categoría/sección/epígrafe/plazo idénticos, `assertEquals(publicacion, recuperada)`);
   mapeo dominio↔entidad también probado sin BD en `PublicacionPersistenciaTest`.
2. **Cuatro tablas vía Flyway** — comprobado con BD real: `flywayInfo` V1+V2 Success y
   `information_schema.tables` con las cuatro tablas.
3. **Upsert idempotente** — `ON CONFLICT (id) DO UPDATE`; el test live relanza el guardado,
   verifica 1 fila, título actualizado y `actualizado_en` avanzado.
4. **Metadatos opcionales nulos** — `PublicacionPersistenciaTest` (sin BD) y
   `comprobarNulos` (live); nulos conservados sin excepción.
5. **Fragmento/resumen/cola + FK CASCADE** — `comprobarCascada` guarda y relee los tres
   ligados a la publicación, y tras borrar la publicación los tres desaparecen (CASCADE).
6. **Gate sin BD** — `:backend:test`, `build -PskipClient`, `test`, `detekt` e `init.sh`
   en verde con Docker parado; los repositorios no se cablean al arranque.

## Hallazgos

**Sin hallazgos Critical/High/Medium.**

- **Low (nota de alcance, aceptable):** el implementador actualizó
  `.agents/skills/ktor-backend-architecture/SKILL.md` (§Estado actual). El spec no lo
  listaba entre los docs durables, y además menciona `ingesta/` (FT00006/FT00007), no
  solo `persistencia/`. Se acepta: el texto era **obsoleto** («los paquetes de dominio
  … aún no existen») y ahora es **exacto**; es un doc de arquitectura vivo del harness,
  sin impacto en producto ni en el gate, y no introduce comportamiento.
- **Low (deuda):** `cola_revision` no tiene índice dedicado por `resumen_id`
  (solo el índice por `estado`). El `ON DELETE CASCADE` de `resumen` puede requerir
  *scan* de `cola_revision`; irrelevante a esta escala y **no exigido por el spec**
  (que solo pedía índice por `estado`). Apuntar a FT00023 si la cola crece.
- **Low (nota):** `FragmentoRepositorioJdbc`/`ResumenRepositorioJdbc`/`ColaRevisionRepositorioJdbc.guardar`
  usan `.first()` sobre el `RETURNING id` (lanza si no hay fila). Es seguro para
  `INSERT … RETURNING` y respeta el `return` único; sólo una observación.

## Seguridad (checklist *feature-scoped*)

- **Sin hallazgos**. Sin secretos en el diff: `.env` ignorado (`.gitignore`), `.env.example`
  con placeholder «cambia_esta_clave_local»; ningún literal de credencial en el código.
- **Fail-fast**: `ConfiguracionBd.fromEnv` aborta con `IllegalStateException` si falta
  `POSTGRES_PASSWORD`; puerto validado (1–65535). `toString` **redacta** la contraseña
  (`password=***`), con test que lo verifica. `loadDotEnv`/Flyway conservan el mismo
  patrón de mensaje.
- **Inyección SQL**: todo el SQL es parametrizado (`PreparedStatement`, `?`); no hay
  concatenación de valores (solo identificadores/columnas constantes `const val`).
- **Superficie**: sin endpoints, sin autenticación (datos públicos del BOE), sin wiring
  en el arranque; no se abren sockets en el gate.

## Alcance y arquitectura

- Cambios acotados a: migración `V2` (nueva), `infra/{ConfiguracionBd,BaseDatos}.kt`,
  paquete `persistencia/` (4 repositorios + `Jdbc.kt`), campo aditivo `Publicacion.plazo`,
  `libs.versions.toml` + `backend/build.gradle.kts` (driver PostgreSQL + HikariCP en
  `implementation`) y `docs/desarrollo-local.md`. `git status` confirma que
  **`Application.kt`, `:shared`, `:composeApp`, la raíz del build, `settings.gradle.kts`
  y `.github/workflows/ci.yml` están intactos**; `V1__esquema_base.sql` no se editó.
- JDBC + HikariCP **sin ORM** (ADR 0003); repositorios traducen a modelos internos
  (`Publicacion`) y exponen entidades `...Entity`; config/pool en `infra/`. Coherente
  con `ARCHITECTURE.md` y la skill `ktor-backend-architecture`. El paquete transversal
  `persistencia/` es la decisión explícita del spec (esquema compartido).
- Diferido **no** anticipado: sin `embedding`/`vector(`/HNSW (test explícito lo verifica);
  `categoria`/`plazo_*` nullable. Driver PostgreSQL en el classpath de producción.
- Estilo MUST: sin `else if`, `return` único por función (Detekt `ReturnCount max: 1`),
  funciones ≤40 líneas (la mayor, `comprobarCascada`, 38 líneas sin blancos), KDoc en
  todo lo nuevo.

## Documentación y harness

- `ARCHITECTURE.md` (frontera **Backend → PostgreSQL**, `persistencia/` e `infra/`,
  V1/V2), `CONSTRAINTS.md` (§«Persistencia y base de datos»: JDBC+HikariCP sin ORM,
  upsert idempotente, pruebas de BD opt-in), **ADR `docs/adr/0003-jdbc-hikari-sin-orm.md`**
  indexado en `docs/adr/README.md`, `docs/desarrollo-local.md` (esquema, pool, opt-in),
  `PROGRESS.md` (Session 036) y `feature_list.json` (FT00008 `passing`, 7 evidencias).
- `docs/feature-ids.md`: FT00008 → `passing`. `AGENTS.md` intacto (no aplicaba).
  `init.sh` sin cambios y ejecuta el gate real (no solo imprime).
- `feature_list.json` parsea como JSON válido y contiene `ft_id`/`status`/`evidence`.

## Seguimiento

Ninguno bloqueante. La aceptación final la persiste el orquestador en
`feature_list.json` (estado `accepted` + evidencia). Deuda Low a arrastrar: índice
`cola_revision(resumen_id)` (FT00023) y nota documental del `SKILL.md`.

## Nota posterior (2026-10-10, limpieza solicitada por el dueño)

Tras la aceptación, el orquestador aplicó una limpieza **sin cambio de
comportamiento** sobre el código nuevo de FT00008: (1) los identificadores
nuevos pasan a **inglés** (p. ej. `ConfiguracionBd`→`DatabaseConfig`,
`BaseDatos`→`Database`, `PublicacionRepositorio`→`PublicationRepository`,
`FragmentoRepositorio`→`FragmentRepository`, `ResumenRepositorio`→`SummaryRepository`,
`ColaRevisionRepositorio`→`ReviewQueueRepository`, `PublicacionEntity`→`PublicationEntity`,
etc.; entidades con propiedades en inglés; paquete `persistencia/`→`persistence/`;
métodos `save`/`findById`/`listByDate`), conservando los tipos de dominio
existentes (`Publicacion`, `PlazoDto`, `SeccionBoeDto`, `CategoriaDto`); y (2) se
eliminaron las referencias al hardware («N100 / 8 GB», «carga baja») del código y
docs de la feature. Los nombres citados en las tablas de arriba corresponden al
estado **previo** a esa limpieza; el comportamiento, el SQL y los escenarios
validados no cambian. Gate reejecutado en verde.
