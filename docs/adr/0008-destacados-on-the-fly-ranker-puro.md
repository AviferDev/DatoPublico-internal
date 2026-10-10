# ADR 0008: Destacados calculados *on-the-fly* por un ranker puro y explicable (sin persistencia ni IA)

## Estado

Aceptado (2026-10-10). Decisión del dueño del proyecto. No supersede ningún ADR.

## Contexto

El feed diario (FT00026) debe marcar un **subconjunto** de las publicaciones de una
fecha como **destacadas**, explicando de forma breve **por qué** lo son. El corpus
de la 1.0.0 es **todo el sumario del BOE** y las señales ya están persistidas por
FT00008/FT00012 (`titulo`, `organismo`, `rango`, `seccion`, `categoria`, `plazo`).

Hay dos decisiones que conviene fijar por adelantado:

1. **Persistir o calcular.** El destacado es **relativo al conjunto del día**
   (orden por puntuación, umbral y tope), no una propiedad intrínseca de cada
   publicación. Persistirlo exigiría, tras los *upserts* del día, una **segunda
   pasada** que releyera el día completo y reescribiera cada fila, más cableado en
   el job (FT00009), el backfill (FT00011) y `Application.kt`, y una migración
   nueva.
2. **Cómo puntuar sin sesgo.** La planificación descarta cualquier criterio
   editorial o subjetivo (`risks-and-open-questions.md`): nada de IA/LLM,
   personalización ni analítica, para evitar la **percepción de sesgo**.

Se necesita una base **verificable en el gate** (sin red ni BD), determinista y
explicable, que no toque el arranque ni el contrato de `:shared`.

## Decisión

- **Calcular *on-the-fly*, sin persistir.** El paquete de dominio
  `es.aviferdev.datopublico.backend.relevance` expone `HighlightRanker.rank(
  List<Publicacion>): List<Highlight>`; el feed (FT00026) le pasará el resultado de
  `PublicationRepository.listByDate(fecha)`. **No** hay migración, columna,
  repositorio ni cableado en `Application.kt`/job/backfill. El coste de puntuar en
  memoria unos cientos de elementos es despreciable y no añade I/O por petición.
- **Ranking objetivo, determinista y explicable.** La puntuación es **aditiva**
  sobre señales **objetivas y documentadas**: sección I (normas), rango normativo
  (ley > real decreto-ley/legislativo > real decreto > orden/instrucción >
  resolución/acuerdo/circular), categoría curada de interés ciudadano (empleo
  público, becas/subvenciones, premios; **reutiliza** la de FT00012), plazo de
  solicitud abierto y organismo emisor en una **lista curada y modesta**. El
  organismo pesa **+1** y **nunca** decide por sí solo un destacado. Cada
  `Highlight` expone su `score` y una lista **no vacía** de `HighlightReason`.
- **Puro.** Sin red, BD, IA/LLM, reloj, aleatoriedad ni estado compartido; la
  salida **no depende del orden de entrada** (orden por `score` desc, `id` asc,
  con tope). Un día sin señales devuelve lista vacía (no se fuerza un mínimo).
- **Semilla determinista documentada.** Umbral y tope son constantes del
  `companion object` con KDoc, sin configuración por entorno. Su afinado con datos
  reales es **deuda aceptada** que no bloquea la 1.0.0.

## Alternativas consideradas

- **Persistir el destacado** (columna `destacado`/`score` + migración + segunda
  pasada en el job/backfill). Descartada: más cableado, una pasada extra de I/O y
  **deuda de consistencia** (un valor persistido quedaría obsoleto al afinar las
  reglas hasta reejecutar ingesta/backfill). Coherente con «no anticipar lo
  diferido» (`CONSTRAINTS.md` §Persistencia).
- **Puntuar con IA/LLM o embeddings.** Descartada: coste por publicación, no
  determinismo, difícil de testear/auditar y riesgo de sesgo percibido.
- **Señales editoriales o personalizadas por usuario.** Descartadas por el riesgo
  de sesgo y por el principio de «sin perfiles ni analítica».
- **Tabla de pesos como configuración externa (BD/entorno).** Descartada para la
  1.0.0: constantes en código, versionadas y testeables; si crece, se migrará.

## Consecuencias

- **Habilita** el bloque de «Destacados del día» del feed y de la UI (FT00026,
  FT00032+) sin coste de IA y con comportamiento reproducible y auditable.
- **Cuesta** asumir que umbral, pesos y lista de organismos son una **semilla
  heurística** afinable con datos reales (deuda documentada) y que el recálculo se
  hace por petición (trivial hoy; un cacheo o persistencia sería una decisión
  posterior, fuera de alcance).
- **Documentación/código**: paquete `relevance/` en `ARCHITECTURE.md`, regla MUST
  en `CONSTRAINTS.md` y nota en `docs/desarrollo-local.md`. Sin cambios en
  `:shared`, migraciones, `Application.kt` ni CI.
- **Sin dependencia de red/BD**: el ranking se verifica solo con tests unitarios
  en el gate; no se añade ninguna prueba opt-in.
