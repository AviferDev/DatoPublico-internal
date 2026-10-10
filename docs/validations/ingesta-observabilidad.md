# Validación — `ingesta-observabilidad` (FT00010)

- Veredicto: **`accept`**
- Fecha: 2026-10-10
- Rol: `validator` (independiente, solo lectura; no implementa ni corrige)
- Spec: `.harness/docs/specs/ingesta-observabilidad.md`
- Rama: `feat/ft00010-ingesta-observabilidad` (commit `chore(FT00010): claim`;
  cambios de la feature **sin commitear** en el árbol de trabajo)
- Estado en `feature_list.json`: `not_started` (lo persiste el orquestador; ver
  observación H1)
- Repo de producto: `..` (JAVA_HOME = JBR 21 de Android Studio, `21.0.10`)

## Checks reejecutados (salidas reales)

| Comando | Resultado |
| --- | --- |
| `./gradlew :backend:test --rerun-tasks -PskipClient` | BUILD SUCCESSFUL; **91 tests, 0 fallos/errores** (XML). Nuevos: `IngestionLogTest` 2, `MissedIngestionDetectorTest` 4, `IngestionWatchdogTest` 2; ampliados `IngestionConfigTest` 8, `IngestionScheduleTest` 7, `IngestionSchedulerTest` 1. |
| `./gradlew build --no-daemon -PskipClient` | BUILD SUCCESSFUL (23 tareas). |
| `./gradlew test` | BUILD SUCCESSFUL (63 tareas; `:shared:jvmTest` + `:backend:test` + `:composeApp:jvmTest`). |
| `./gradlew detekt --rerun-tasks` | BUILD SUCCESSFUL (Detekt por módulo + `:cpdCheck`, sin hallazgos). |
| `env -u JAVA_HOME .harness/init.sh` | **exit 0** («Gate OK»: build -PskipClient + detekt + `:cpdCheck`). |
| Docker | **caído** (`docker ps` → no daemon); sin `.env` ni `POSTGRES_*`/`INGESTA_*` en el entorno: gate sin BD ni red. |
| `git status` / `git diff --stat` | 8 modificados + 8 nuevos, todos dentro de `ingesta/job/`, `Application.kt` y `docs/desarrollo-local.md`. |

> El recuento 91 tests coincide con la autoevaluación del implementer.

## Escenarios del spec (1–8)

1. **Log estructurado de ejecución correcta** — `IngestionLogTest`: `runFields`
   de `2026-10-09`, total/saved 205, failed 0 → `event=ingestion.run.completed` +
   `ingestion_date`/`total_entries`/`publications_saved`/`publications_failed` y
   **sin** `error`. ✅
2. **Ejecución fallida** — `IngestionLogTest`: `error="BOE caído"` →
   `event=ingestion.run.failed` con `error`; `logRun` emite a nivel `ERROR`. ✅
3. **Ventana de la tarde sin ejecutar** — `MissedIngestionDetectorTest`:
   `{09:30,18:00}`, startedAt 08:00, grace 30, attempted `{09:30}`, now 19:00 →
   `[18:00]`. ✅
4. **Sin falsos positivos** — attempted `{09:30,18:00}`, now 19:00 → vacío. ✅
5. **Ventanas anteriores al arranque** — startedAt 10:00 → `[18:00]` (09:30 no se
   reclama). ✅
6. **Dentro de gracia** — now 18:15 → vacío. ✅
7. **Alerta única por ventana (tiempo virtual)** — `IngestionWatchdogTest` con
   `runTest`/`advanceTimeBy` (20 h) y varios ticks → exactamente `[18:00]`;
   sumidero de prueba; test adicional de resiliencia (el sumidero lanza y el bucle
   sigue activo). ✅
8. **Gate sin red ni BD** — verde (ver tabla); los tests nuevos son puros y no
   usan `HttpClient`/`DataSource`/sockets; los `*LiveTest` están guardados por
   `BOE_LIVE_TEST`/`DB_LIVE_TEST` (omitidos). ✅

El mecanismo `StructuredArguments.entries(...)` de `logstash-logback-encoder` 8.0
devuelve un `StructuredArgument` (confirmado con `javap`) y `ArgumentsJsonProvider`
lo escribe como **campos de primer nivel**; la emisión real de JSON se apoya en la
API documentada de la librería (el test de gate verifica el mapeo puro, como marca
el spec).

## Hallazgos

### H1 (Low, harness) — `feature_list.json` aún en `not_started` sin evidencia

- Evidencia: la entrada FT00010 sigue con `status: "not_started"` y `evidence: []`;
  `PROGRESS.md` (Session 039) y el flujo atribuyen esa actualización al orquestador.
- Impacto: solo de estado/harness; no afecta al comportamiento de la feature.
- Acción: el orquestador debe pasar FT00010 a `accepted` con evidencia al cerrar.

### H2 (Low) — nivel de log y emisión real no asertados en el gate

- Evidencia: `IngestionLogTest` verifica el mapeo puro (`runFields`) pero no el
  nivel `ERROR` ni la línea JSON final; `LoggingAlertSink` no tiene test dedicado.
- Impacto: menor; el spec reconoce que «el gate no puede probar el JSON real de
  Logstash en firme, se prueba el mapeo puro». `logRun` fija el nivel de forma
  trivial y la verificación del JSON real quedó como evidencia de la sesión de
  implementación (test de usar y tirar, no versionado).
- Acción (opcional, no bloqueante): añadir un test con appender en memoria si se
  quiere fijar nivel/evento de `LoggingAlertSink`.

Sin hallazgos Critical/High/Medium.

## Seguridad

Revisión acotada al diff (checklist `security-checklist`): **sin hallazgos**.
Sin secretos/credenciales (sin `.env`, sin literales); sin datos personales (los
logs solo llevan fecha, recuentos, ventana y mensaje de error interno); sin
entradas no validadas (`INGESTA_GRACE_MINUTES` con fail-fast entero > 0); sin
llamadas de red/BD en el gate ni dependencias nuevas; sin alerting externo ni
telemetría (la alerta es un log `ERROR`), conforme a `CONSTRAINTS.md`.

## Arquitectura, alcance y calidad

- Alcance exacto del spec: eventos estructurados por ejecución + vigilante +
  config de gracia + cableado. **Sin** clasificación (FT00012), backfill (FT00011),
  endpoints, migraciones, `logback.xml`, `:shared`, `:composeApp`, raíz, `settings`
  ni CI.
- MUST de `CONSTRAINTS.md`: `return` único y sin `else if` (verificado por grep);
  `createIngestionRuntime` 39 líneas < 40 (resto de funciones nuevas pequeñas);
  KDoc en castellano e identificadores en inglés; sin crashes (el vigilante y el
  scheduler capturan excepciones y no matan el bucle).
- Cableado condicional en `Application.kt`: arranca sin BD (`Ingesta no arrancada:
  Contraseña de base de datos no definida…`) y `/health` responde 200 (visto en el
  log de `:backend:test`); el vigilante va en el **mismo** `CoroutineScope` y se
  cancela en `ApplicationStopped` (`IngestionRuntime.close()` → `scope.cancel()`).

## Documentación / harness

- `ARCHITECTURE.md` (§`:backend`/`ingesta/job/` + cableado del vigilante),
  `CONSTRAINTS.md` (§«Operación», MUST de eventos `event` estables y alerta `ERROR`,
  sin alertas externas ni telemetría), **ADR 0005** + índice,
  `docs/desarrollo-local.md` (`INGESTA_GRACE_MINUTES` y cómo leer los eventos) y
  `PROGRESS.md` (Session 039): actualizados y coherentes con el código.
- `AGENTS.md` sin cambios (según el spec). `init.sh` sin cambios y ejecutándose
  de verdad (no solo imprime comandos). `feature_list.json`: pendiente de
  orquestador (H1).

## Follow-up

- Ninguno bloqueante. Al cerrar: que el orquestador persista `accepted` en
  `feature_list.json` con la evidencia del gate.
