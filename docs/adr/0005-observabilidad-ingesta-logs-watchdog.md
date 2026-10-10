# ADR 0005: Observabilidad de la ingesta por logs estructurados + vigilante interno

## Estado

Aceptado (2026-10-10). Decisión del dueño del proyecto, adoptada al implementar
`ingesta-observabilidad` (FT00010). No supersede ningún ADR; precisa la operación
de ingesta descrita en `CONSTRAINTS.md` y la decisión de programación de ADR 0004.

## Contexto

El job diario de ingesta (FT00009) ejecuta a las 09:30 y en una segunda pasada
(18:00) y persiste el corpus de forma idempotente, pero no deja rastro
**consultable**: sólo un log-resumen plano dentro del campo `message`. Si una de
las ventanas no se ejecuta (o la ejecución falla), nadie se entera salvo
revisando la base de datos a mano.

El proyecto tiene reglas duras que acotan la solución: **sin telemetría de uso**,
**sin cuentas ni datos personales**, y un despliegue en una **máquina única**
sin infraestructura adicional (nada de alerting externo gestionado en la 1.0.0).
Hay que decidir **cómo** se emite el estado de la ingesta y **cómo** se alerta de
una ventana perdida sin añadir servicios.

## Decisión

1. **Evento de log JSON estructurado por ejecución.** Cada ejecución emite una
   línea JSON con la clave estable `event` de primer nivel
   (`ingestion.run.completed` a `INFO`; `ingestion.run.failed` a `ERROR` con el
   motivo en `error`) y campos `ingestion_date`, `total_entries`,
   `publications_saved` y `publications_failed`. Se emiten con
   `StructuredArguments.entries` (LogstashEncoder), no interpolados en `message`.
2. **Vigilante interno por corrutina.** Un `IngestionWatchdog` corre en el mismo
   `CoroutineScope` que el scheduler y comprueba cada 5 min, con un detector
   **puro** (`MissedIngestionDetector`), las ventanas que vencieron su gracia y no
   se intentaron. Alerta **una sola vez por ventana** y **no muere por excepción**.
3. **La alerta es un log `ERROR` estructurado.** `event=ingestion.missed` con
   `ingestion_date`, `window` y `grace_minutes`, vía un sumidero inyectable
   (`IngestionAlertSink`). **Sin** alertas externas (email, push, webhooks) ni
   telemetría; un monitor de logs debe vigilar esa clave.
4. **Gracia configurable.** `INGESTA_GRACE_MINUTES` (default **30**, entero > 0,
   fail-fast) fija el margen tras una ventana antes de considerarla perdida; debe
   superar la duración típica de una pasada.
5. **Solo se vigilan ventanas posteriores al arranque.** Una ventana anterior a
   `startedAt` (proceso aún no en marcha) **no** se reclama: recuperarla es del
   backfill (FT00011). El estado de «ventana intentada» es **en memoria**
   (`IngestionRunState`) y el scheduler marca la ventana **antes** de ejecutarla,
   para que una pasada larga no se confunda con una ingesta ausente.
6. **Cableado condicional.** El vigilante se arranca solo cuando la ingesta se
   cablea (con `INGESTA_ENABLED` y config de BD resoluble) y se cancela en
   `ApplicationStopped`, en el mismo scope. Sin recursos nuevos que cerrar.

## Alternativas consideradas

- **Alertas externas (email, PagerDuty, webhook a un chat).** Descartado para la
  1.0.0: añade servicios externos y secretos, y contradice «sin infraestructura
  adicional» en una máquina única. Se reevaluará si el despliegue lo justifica.
- **Telemetría/métricas exportadas (Prometheus, OTLP).** Descartado: prohibido
  por `CONSTRAINTS.md` (sin telemetría de uso) y desproporcionado para el tamaño
  actual; los logs JSON ya son un canal de operación estructurado.
- **Endpoint de estado (`GET /status`) para exponer la última ingesta.** Descartado:
  fuera de alcance (endpoints y API pública son features posteriores) y no
  resuelve la alerta **proactiva** sin un monitor que consulte.
- **Almacenar el estado de ventanas en la base de datos.** Descartado: añade
  esquema y acopla la observabilidad a PostgreSQL; en memoria basta para alertar
  mientras el proceso vive.
- **Distinguir altas de actualizaciones (`created`/`updated`) en el evento.**
  Diferido: el *upsert* por `id` no lo reporta hoy y exigiría cambiar
  `PublicationRepository` y su SQL.

## Consecuencias

- **Habilita** detectar de forma temprana que el corpus del día quedó incompleto
  sin revisar la base de datos; un monitor filtra por `event` en stdout.
- **Cuesta** que la alerta dependa de un monitor de logs externo (no hay push) y
  que el vigilante solo cubra ventanas mientras el proceso está en marcha; un
  arranque posterior a la ventana no la reclama (FT00011). El reloj del host debe
  estar sincronizado.
- **Riesgo de falsos positivos** si `INGESTA_GRACE_MINUTES` es menor que la
  duración real de una pasada; en el N100 hay que vigilar el tiempo de ejecución
  (ya anotado en ADR 0004).
- Duradero: regla **MUST** en `CONSTRAINTS.md` (eventos de log con clave `event`
  estable, alerta `ERROR`, sin alertas externas ni telemetría), descripción de
  `ingesta/job/` en `ARCHITECTURE.md` y variables/eventos en
  `docs/desarrollo-local.md`.
