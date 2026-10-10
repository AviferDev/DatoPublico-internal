# Validación — `ingesta-job-diario` (FT00009)

- Veredicto: **`accept`**
- Fecha: 2026-10-10
- Rol: `validator` (independiente, solo lectura; no implementa ni corrige)
- Spec: `.harness/docs/specs/ingesta-job-diario.md` (con *Implementation Note*)
- Rama: `feat/ft00009-ingesta-job-diario` (commit `chore(FT00009): claim`;
  cambios de la feature **sin commitear** en el árbol de trabajo)
- Estado en `feature_list.json`: `passing` (listo para validación)
- Repo de producto: `..` (JAVA_HOME = JBR 21 de Android Studio)

## Checks reejecutados (salidas reales)

| Comando | Resultado |
| --- | --- |
| `./gradlew :backend:test --rerun-tasks -PskipClient` | BUILD SUCCESSFUL; **80** tests, 0 fallos/errores. Nuevos: `IngestaConfigTest` 7, `IngestaScheduleTest` 5, `IngestaJobTest` 5, `IngestaSchedulerTest` 1, `IngestaJobLiveTest` 1 (opt-in). |
| `./gradlew detekt -PskipClient --rerun-tasks` | BUILD SUCCESSFUL (`:backend:detekt`, `:shared:detekt`, `:cpdCheck` sin hallazgos). |
| `env -u JAVA_HOME .harness/init.sh` | **exit 0** («Gate OK»: build -PskipClient + detekt + `:cpdCheck`). |
| `.env`(55432) + `docker compose up -d` + `:backend:flywayMigrate` | `datopublico-postgres` healthy; `V1`/`V2` en **Success**. |
| `DB_LIVE_TEST=1 ./gradlew :backend:test --tests '*IngestaJobLiveTest' --rerun-tasks` | **Verde**; `system-out` con el pool Hikari conectado a PostgreSQL real (`PgConnection`); 0 filas `FT00009-LIVE-%` tras limpieza. |
| `:backend:run` sin `POSTGRES_PASSWORD` + `curl /health` | Log `Ingesta no arrancada: Contraseña de base de datos no definida…`; **`/health` → 200 `{"status":"ok"}`**. |
| `:backend:run` con `POSTGRES_PASSWORD` (+ contenedor arriba) + `curl /health` | Log **`Ingesta programada: horas=[09:30, 18:00] zona=Europe/Madrid`**; **`/health` → 200**. |
| `git status` / `git diff --name-only` | 14 ficheros (5 modificados + 9 nuevos); **sin** tocar `settings.gradle.kts`, raíz, `gradle/libs.versions.toml`, `:shared`, `:composeApp`, CI ni migraciones. |
| Limpieza | `docker compose down -v`, `.env` borrado, procesos/puertos liberados. |

> El recuento 80 tests / 19 nuevos coincide con la autoevaluación del
> implementer: la evaluación propia es **exacta**.

## Escenarios del spec (1–7)

1. **Horario estricto** — `IngestaSchedule.nextRun` (puro) con `IngestaScheduleTest`:
   09:00→09:30, 09:31→18:00, 18:01→día siguiente 09:30 y `now == 09:30`→18:00
   en `Europe/Madrid`. ✅
2. **Descarga → parseo → persistencia** — `IngestaJobDiario`; 3 entradas →
   `total=3/guardadas=3/fallidas=0`. ✅
3. **Idempotencia (doble)** — dos ejecuciones mantienen 2 filas (upsert por `id`). ✅
4. **Fallo parcial no aborta** — `BoeTextoException` por entrada → `guardadas=2/fallidas=1`;
   fallo de repositorio también cuenta; fallo del sumario → `error` poblado sin propagar. ✅
5. **Tiempo virtual** — `IngestaSchedulerTest` con reloj/`delay` inyectados → 2
   ejecuciones (una por ventana) y el bucle sobrevive a una excepción. ✅
6. **Upsert real (opt-in)** — reproducido contra PostgreSQL real. ✅
7. **Gate sin red ni BD** — verde; los opt-in se omiten sin sus variables. ✅

## Hallazgos

**Sin hallazgos Critical/High/Medium.** Notas Low/informativas (no bloqueantes):

- **Low — fuga teórica en la construcción del runtime**: si `boeTextoHttpClient()`
  lanzara *después* de crear `dataSource`/`sumarioHttp`, esos dos recursos no se
  cerrarían (el cierre empieza tras crear ambos clientes). En la práctica las
  factorías `HttpClient(CIO)` no lanzan. Sugerencia opcional futura: envolver toda la
  construcción en un `try` con cierre de lo ya creado.
- **Low — interpretación del fail-fast**: `IngestaConfig.fromEnv()` se llama fuera del
  `try` de `configureIngesta()`, así que un `INGESTA_*` inválido **aborta el arranque**
  (incluso con `INGESTA_ENABLED=false`). Coherente con el MUST de fail-fast y con el
  patrón de `AppConfig`; solo aclaratorio respecto a la redacción «no impide el arranque».
- **Info** — `HttpClient.close()` se hace a nivel de *wiring* (`IngestaRuntime`), que es
  donde corresponde el ciclo de vida (equivalente funcional al sugerido en el spec).
- **Info** — los `*LiveTest` se autoprotegen con `if/else` y cuentan como «passed»
  (patrón ya establecido del repo: `BoeSumarioLiveTest`, `PublicationPersistenceLiveTest`);
  el gate no abre red ni BD.

## Seguridad

Sin hallazgos. Sin secretos versionados (`.env` ignorado y borrado; `DatabaseConfig.toString()`
redacta la contraseña); fail-fast de configuración de BD y de `INGESTA_*`; el arranque
no depende de la BD (verificado en vivo); `HttpTimeout` explícito en ambas factorías;
URLs construidas desde constantes/API del BOE; `CancellationException` re-lanzado
correctamente; clientes HTTP y pool cerrados en `ApplicationStopped`.

## Alcance y arquitectura

- Cambios acotados a: `ingesta/job/{IngestaConfig,IngestaSchedule,IngestaJob,IngestaScheduler}.kt`
  (nuevos), `ingesta/{sumario/BoeSumarioHttpClient,publicacion/BoeTextoHttpClient}.kt`
  (`HttpTimeout`), `Application.kt` (wiring condicional + `ApplicationStopped`),
  `backend/build.gradle.kts` (`coroutines-core`) y `docs/desarrollo-local.md`; tests en
  `ingesta/job/`.
- `ingesta/job/` sigue *feature-first* (interfaz + impl en el mismo fichero, colaboradores
  por constructor); `IngestaConfig`/`IngestaSchedule` puros y testeables; `IngestaJobDiario`
  usa `withContext(Dispatchers.IO)`; el *wiring* vive en `Application.kt` (composition root,
  sin DI), condicional y no bloqueante. Coherente con `ARCHITECTURE.md` y la skill
  `ktor-backend-architecture`.
- Estilo MUST: `return` único (grep: sin *early return* ni `return@…`), sin `else if`,
  funciones ≤40 líneas, KDoc completo. Sin nuevos `@Serializable` (no aplica `@SerialName`).

## Documentación y harness

- ADR **`docs/adr/0004-ingesta-programada-interna.md`** (+ índice), `ARCHITECTURE.md`
  (paquete `ingesta/job/`, frontera Backend→BOE en runtime, Backend→PostgreSQL condicional),
  `CONSTRAINTS.md` (MUST de `HttpTimeout`), skill `ktor-backend-architecture` §«Estado actual»,
  `docs/desarrollo-local.md` (variables `INGESTA_*`, job y prueba opt-in), `PROGRESS.md`
  (Session 037) y `feature_list.json` (FT00009 `passing`). `init.sh` sin cambios.

## Seguimiento

Ninguno bloqueante. La aceptación final la persiste el orquestador en `feature_list.json`
(estado `accepted` + evidencia). Notas Low a arrastrar: cierre defensivo en la
construcción del runtime y aclaración del fail-fast de `INGESTA_*`.
