# ADR 0006: Backfill histórico como herramienta CLI *one-shot* por lotes

## Estado

Aceptado (2026-10-10). Decisión del dueño del proyecto, adoptada al implementar
`backfill-historico` (FT00011). No supersede ningún ADR; precisa la operación de
ingesta de `docs/roadmap.md` 0.2-T09 y reutiliza el job de ADR 0004.

## Contexto

Para que la búsqueda y el feed tengan corpus desde el primer día hay que poblar
**todo el sumario del BOE** (secciones I, II.A, II.B, III, IV, V.A, V.B y V.C) del
**último año** sin esperar a que la ingesta diaria lo acumule día a día. La
máquina de despliegue es única y pequeña (~8 GB), con un job programado (FT00009)
que ingiere **una** fecha por ventana: inviable para ~365 días.

Hasta FT00011 existían las piezas (cliente del sumario FT00006, parser FT00007,
*upsert* FT00008, `DailyIngestionJob` FT00009) pero ningún mecanismo de carga
masiva. Había que decidir **cómo** se lanza el backfill, **cómo** se controla su
ritmo en baja carga, **cómo** se reanuda si se interrumpe y **dónde** vive el
progreso, sin añadir infraestructura ni tocar el arranque del servidor.

## Decisión

1. **Herramienta CLI *one-shot*, no programada.** El backfill es una tarea Gradle
   explícita (`./gradlew :backend:backfill`) que ejecuta `BackfillMain`; **no** se
   cablea en `Application.kt`, no añade endpoints y no se engancha a
   `build`/`check`. Nada de cron externo ni scheduler interno: se lanza a mano.
2. **Reutiliza el job diario.** El runner (`BackfillRunner`) recorre el rango y
   llama a `DailyIngestionJob.run(date)`; no reimplementa la ingesta
   (sumario → parser → *upsert*) ni filtra secciones.
3. **Idempotencia por *upsert*.** El progreso se guarda por fecha, pero rehacer es
   seguro: `PublicationRepository.save` es un *upsert* por `id`.
4. **Reanudación con checkpoint local en fichero.**
   `FileBackfillCheckpointStore` escribe un fichero de texto (línea de rango +
   fechas ISO) de forma **atómica** (temporal + `Files.move`). Fichero ausente →
   sin progreso; formato inválido → fail-fast. El runner solo reanuda si el
   `(from, to)` guardado coincide con el configurado. Se descarta persistir el
   checkpoint en base de datos para no añadir una migración al alcance.
5. **Ritmo por lotes para la máquina única.** El rango se trocea en lotes
   (`BACKFILL_BATCH_DAYS`, default 7) con una pausa entre fechas
   (`BACKFILL_DELAY_MS`, default 500 ms); el trabajo de E/S corre en
   `Dispatchers.IO`. El checkpoint se persiste **tras cada lote**.
6. **Reintento por fecha.** Una fecha cuenta como completada solo si el job no
   reporta error **y** no deja entradas fallidas; si no, se registra y se
   reintenta en el siguiente run. El fallo de una fecha nunca aborta el run.

## Alternativas consideradas

- **Cron/scheduler interno para el backfill.** Descartado: es una carga puntual de
  puesta en marcha, no una operación recurrente; el job diario ya cubre el día a
  día.
- **Checkpoint en base de datos (migración V3 + repositorio).** Descartado: añade
  esquema y complejidad para una herramienta manual en una máquina única; el
  *upsert* hace seguro rehacer si se pierde el fichero.
- **Omitir fechas ya presentes en `publicacion`.** Descartado: perdería
  correcciones que el BOE publica sobre la misma fecha y complicaría el criterio
  de reanudación; el checkpoint marca progreso, no el corpus.
- **Backfill en paralelo con muchas hebras.** Descartado: en 8 GB y una sola API
  externa, lotes secuenciales con pausa son predecibles y respetuosos.

## Consecuencias

- **Habilita** que la clasificación (FT00012) y la búsqueda operen sobre un corpus
  histórico poblado; deja el backfill listo antes de la UI.
- **Cuesta** que el progreso viva en un fichero local (no replica ni sobrevive a
  su borrado); asumido porque la máquina es única y el *upsert* es idempotente. El
  backfill asume el **esquema migrado** (`:backend:flywayMigrate`), no migra.
- **Riesgo operativo**: ~365 días de todo el BOE son horas de ejecución; se mitiga
  con lotes, pausa configurable y horario de baja carga.
- Duradero: regla **MUST** en `CONSTRAINTS.md` y descripción de `ingesta/backfill/`
  en `ARCHITECTURE.md`; guía en `docs/desarrollo-local.md`.
