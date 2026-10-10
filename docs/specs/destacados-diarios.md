# Feature Implementation Spec: Destacados del día por ranking objetivo

## Source Feature

- `id`: destacados-diarios
- `ft_id`: FT00013 (ver `docs/feature-ids.md`)
- `parts`: none (atómica; ~4–6 ficheros de producto, muy por debajo del límite de 30)
- `area`: relevancia
- `depends_on`: categorizacion-publicaciones (FT00012, `accepted`)
- `status`: accepted (implementada, autoverificada y validada de forma independiente; rama `feat/ft00013-destacados-diarios`)
- `source`: `feature_list.json`

## Decisión de planificación (persistir vs calcular)

**Decisión: calcular *on-the-fly* (sin persistir).** No hay migración Flyway ni
columna nueva ni cambio de repositorio.

Justificación:

1. **El destacado es relativo al conjunto del día, no una propiedad por
   publicación.** El ranking marca un **subconjunto** de las publicaciones de una
   fecha comparándolas entre sí (orden por puntuación, umbral, tope). Persistir
   exigiría, tras los *upserts* del día, una **segunda pasada** que releyera el día
   completo y volviera a escribir cada fila: cableado extra en el job diario
   (FT00009), el backfill (FT00011) y `Application.kt`, y una migración `V3`.
2. **Las señales ya están persistidas.** La puntuación usa `titulo`, `organismo`,
   `rango`, `seccion`, `categoria` y `plazo`, todos guardados por FT00008/FT00012.
   La función es **pura y determinista**, así que recalcular produce exactamente el
   mismo resultado: no hay pérdida de consistencia.
3. **Coste despreciable y N100-friendly.** `PublicationRepository.listByDate(date)`
   ya devuelve el día; puntuar unos cientos de elementos en memoria es trivial. No
   se añade I/O por petición ni se toca el esquema.
4. **Sin deuda de consistencia.** Si mañana se afinan las reglas, recalcular
   refleja el cambio al instante; un valor persistido quedaría obsoleto hasta
   re-ejecutar ingesta/backfill o migrar datos.
5. **Coherente con el precedente FT00012 y con «no anticipar lo diferido»**
   (`CONSTRAINTS.md` §Persistencia): la feature queda **dentro del gate** (pura, sin
   red ni BD), sin tocar `Application.kt`, `:shared`, migraciones ni CI.

**Integración futura (documentada, no implementada aquí):** el feed (FT00026)
llamará `PublicationRepository.listByDate(fecha)` y pasará la lista al ranker
`HighlightRanker.rank(...)`; si el perfilado lo exigiera, un cacheo o una
persistencia de destacados sería una decisión posterior (fuera de alcance).

## Goal

Añadir en `:backend` un **ranking de relevancia automático, objetivo,
determinista y explicable** que, dada la lista de publicaciones de un día, marque
un **subconjunto** como **destacadas** por señales objetivas —**rango normativo**,
**sección normativa**, **categoría temática** (empleo público, becas/subvenciones,
premios), **plazo de solicitud abierto** y **organismo emisor relevante**— y exponga
**por qué** cada una es destacada (`HighlightReason`). Es la base de
`docs/roadmap.md` 0.4-T08.

La lógica es **pura** (sin red, BD, IA, reloj ni aleatoriedad), vive en un paquete
de dominio `relevance/` y se verifica **solo en el gate** con tests unitarios. No se
cablea en el arranque; la consumirá el feed (FT00026).

## Non-Goals

- **Persistir** el destacado (columna/migración `V3`/repositorio): descartado, ver
  *Decisión de planificación*.
- **Endpoints HTTP / API** (`api-feed-diario`, FT00026) y **UI** (FT00032+): no se
  exponen ni se serializan destacados.
- **Cambios en `:shared`**: no se añade ningún `Dto` ni campo a `PublicacionDto`
  (el DTO de wire de destacados/reasons llega con FT00026).
- **Embeddings, chunking, pgvector, RAG** (FT00014–FT00018) y **clasificación**
  (ya hecha en FT00012): el ranking **reutiliza** la `categoria` ya calculada.
- **IA/LLM, señales subjetivas o editoriales**, personalización por usuario o
  analítica: prohibido por el riesgo de sesgo (`risks-and-open-questions.md`).
- **Cambiar el job diario / backfill / `Application.kt`** para recalcular o
  persistir destacados.
- **Alertas, watchlist o notificaciones** de convocatorias: 1.x.
- **Tuning fino de pesos** con datos reales de producción: se documenta como deuda;
  aquí se fija una semilla determinista verificable.

## Job Story

Cuando consulto el feed del día,
quiero que las publicaciones más relevantes aparezcan destacadas con una
explicación breve y objetiva de por qué lo son,
para orientarme rápido sin depender de un criterio editorial opaco.

## Users And Permissions

- Desarrollador / consumidor interno (feed FT00026): invoca `HighlightRanker` sobre
  una `List<Publicacion>` ya recuperada. Sin cuentas, sin autenticación, sin datos
  personales. La función es pura y no accede a red ni BD.

## Acceptance Scenarios

### Scenario 1: día mixto → subconjunto destacado ordenado y explicado

Given una lista de publicaciones del mismo día con señales distintas (una `Ley`
orgánica de la Sección I, un `Real Decreto`, una convocatoria de empleo público con
plazo, un `Orden` y varios anuncios V.C sin señales),
When `HighlightRanker.rank(publications)` puntúa y selecciona,
Then devuelve solo las que alcanzan el umbral, **ordenadas por puntuación
descendente** y, a igual puntuación, por `id` ascendente (estable), y **cada
destacado** expone su `score` y una lista **no vacía** de `HighlightReason`.

### Scenario 2: prioridad del rango normativo

Given dos publicaciones de la Sección I con el resto de señales iguales, una con
`rango = "Ley Orgánica"` y otra con `rango = "Orden"`,
When se puntúan,
Then la de `Ley Orgánica` obtiene **mayor** `score` (y `HighlightReason.NORMATIVE_RANK`)
y precede a la de `Orden` en el resultado.

### Scenario 3: convocatoria accionable vs anuncio trivial

Given una convocatoria de la Sección II.B (categoría `OPOSICIONES_Y_EMPLEO_PUBLICO`,
`plazo != null`) y un anuncio de la Sección V.C sin rango, sin plazo y categoría
`OTRAS_DISPOSICIONES_Y_ANUNCIOS`,
When se puntúan,
Then la convocatoria es **destacada** (con `THEMATIC_KEYWORD` y `OPEN_DEADLINE`) y el
anuncio **no** aparece en el resultado.

### Scenario 4: organismo emisor relevante

Given dos publicaciones con idénticas señales de rango/sección/categoría/plazo pero
distinto `organismo`, una de ellas en la **lista curada de emisores de referencia**
del BOE (p. ej. `Jefatura del Estado`, `Presidencia del Gobierno`, `Cortes
Generales`) y otra de un organismo cualquiera,
When se puntúan,
Then la primera obtiene `HighlightReason.RELEVANT_BODY` y **mayor o igual** `score`;
la señal de organismo es **modesta** y **nunca** por sí sola decide un destacado.

### Scenario 5: día sin señales → sin destacados

Given una lista vacía o formada solo por publicaciones por debajo del umbral,
When se rankea,
Then el resultado es la lista vacía (el feed mostrará el bloque de destacados
vacío; no se fuerza un mínimo artificial).

### Scenario 6: determinismo y pureza (gate)

Given la misma lista de publicaciones,
When se rankea cualquier número de veces, en cualquier orden de entrada,
Then el resultado es **idéntico** (mismo orden y mismas razones), sin red, sin BD,
sin reloj, sin estado compartido ni aleatoriedad; el orden de entrada no altera la
salida. `./gradlew :backend:test` lo cubre sin servicios externos.

### Scenario 7: sin romper contratos ni arranque

Given el repositorio tras el cambio,
When se ejecuta el gate y el arranque,
Then `:shared`, `Application.kt`, las migraciones Flyway, `PublicationRepository`,
la raíz del build y la CI quedan **intactos**; el servidor sigue arrancando sin BD y
`/health` responde.

## Repository Research

### Files Inspected

- **Harness:** `feature_list.json` (FT00013; FT00012 `accepted`), `PROGRESS.md`,
  `docs/feature-ids.md`, `docs/roadmap.md` §0.4.0 (`0.4-T08`), `CONTEXT.md`
  (§Destacados), `docs/domain-model.md` (Destacado), `docs/build-brief.md`,
  `docs/technical-discovery.md` (pruebas del ranking), `DESIGN.md` (destacados,
  «explicar por qué»), `docs/risks-and-open-questions.md` (sesgo editorial),
  `ARCHITECTURE.md`, `CONSTRAINTS.md`, `docs/adr/0007`, y
  `docs/specs/categorizacion-publicaciones.md` / `publicacion-persistencia.md`.
- **Producto (`..`):**
  `backend/.../ingesta/publicacion/Publicacion.kt` (campos `rango`, `organismo`,
  `seccion`, `categoria`, `plazo`, `titulo`), `.../ingesta/categorizacion/PublicationClassifier.kt`
  (patrón de normalización y reglas puras), `.../persistence/PublicationRepository.kt`
  (`listByDate` + `PublicationEntity`), `.../Application.kt` (composition root),
  `shared/.../model/{CategoriaDto,SeccionBoeDto,PlazoDto,PublicacionDto}.kt`,
  migraciones `V1`/`V2`.

### Existing Patterns To Follow

- **Dominio puro sin Ktor/JDBC** (precedentes `PublicationClassifier`,
  `DeadlineExtractor`, `MissedIngestionDetector`): clases con métodos puros y
  constantes documentadas.
- **Reutilizar la `categoria` de FT00012** como señal temática en lugar de volver a
  normalizar texto (evita duplicar la tabla de reglas).
- **Reutilizar `PublicationRepository.listByDate`** como fuente de la lista del día;
  no se modifica el repositorio.
- **Tests `kotlin.test`** en espejo del paquete, sin red ni BD; sin identificadores
  en castellano (KDoc/comentarios en castellano).
- MUST de estilo: `return` único, sin `else if`, ≤40 líneas/función, KDoc.

### Current Gaps

- No existe ningún paquete `relevance/` ni puntuación de relevancia.
- No hay consumidor todavía: el feed (FT00026) y la UI (FT00032+) son posteriores.
- `PublicationDto` (contrato de `:shared`) no tiene campos de destacado ni razones;
  su wire se difiere a FT00026.

## Technical Approach

1. **Paquete nuevo de dominio** `backend/src/main/kotlin/.../backend/relevance/`
   (identificadores en inglés; KDoc en castellano).
2. **`Highlight.kt`** — modelos internos (ni serializables ni `Dto`):
   - `enum class HighlightReason` con motivos objetivos: `NORMATIVE_SECTION`,
     `NORMATIVE_RANK`, `THEMATIC_KEYWORD`, `OPEN_DEADLINE`, `RELEVANT_BODY`. Cada
     valor con KDoc que explique la señal (los textos de UI se localizan en FT00032+).
   - `data class Highlight(val publication: Publicacion, val score: Int, val reasons:
     List<HighlightReason>)`.
3. **`HighlightRanker.kt`** (puro): `fun rank(publications: List<Publicacion>):
   List<Highlight>`. Para cada publicación calcula una puntuación aditiva por
   señales y acumula las razones que dispara; luego filtra por umbral, ordena por
   `score` desc y `id` asc, y aplica un tope. Sin reloj ni aleatoriedad.
   Semilla determinista de señales (el implementador puede afinar los pesos con
   fixtures reales **sin romper los escenarios ni el orden**):
   - **`NORMATIVE_SECTION`** — `seccion == I` → **+2** (Sección I = normas).
   - **`NORMATIVE_RANK`** — por `rango` normalizado: `Ley Orgánica`/`Ley`/
     `Real Decreto-ley`/`Real Decreto Legislativo` → **+4**; `Real Decreto` → **+3**;
     `Orden`/`Orden Ministerial`/`Instrucción` → **+2**; `Resolución`/`Acuerdo`/
     `Circular` → **+1**; desconocido/`null` → **0**.
   - **`THEMATIC_KEYWORD`** — `categoria ∈ {OPOSICIONES_Y_EMPLEO_PUBLICO,
     BECAS_SUBVENCIONES_Y_AYUDAS, PREMIOS}` → **+2** (familia temática de interés
     ciudadano; reutiliza la categoría curada).
   - **`OPEN_DEADLINE`** — `plazo != null` → **+2** (convocatoria accionable).
   - **`RELEVANT_BODY`** — `organismo` en una **lista curada y documentada** de
     emisores de referencia del BOE (p. ej. `Jefatura del Estado`, `Presidencia del
     Gobierno`, `Cortes Generales`, `Consejo de Ministros`, `Ministerio de la
     Presidencia…`) → **+1** (peso **modesto**, jamás decisivo por sí solo; mitiga el
     riesgo de sesgo).
   - **Selección:** es destacada si `score >= MIN_SCORE` (semilla **4**), ordenada
     por `score` desc / `id` asc, con tope `MAX_HIGHLIGHTS` (semilla **12**).
     Constantes en el `companion object` con KDoc; **sin** configuración por entorno.
   - **Determinismo:** comparación de `rango`/`organismo` con la **misma
     normalización** (minúsculas, sin acentos, espacios colapsados) que usa
     `PublicationClassifier`; si se prefiere reutilizarla literalmente, extraer un
     normalizador interno compartido es una refactorización **opcional y acotada**
     (si no, duplicar la pequeña función con KDoc). La salida **no** depende del
     orden de entrada.
   - Cumplir estilo: `return` único, sin `else if` (usar `when`/`firstOrNull`/`fold`),
     funciones ≤40 líneas (extraer `scoreOf`, `reasonsOf`, `rankOf` si hace falta).
4. **Sin wiring**: no se toca `Application.kt`, el job, el backfill, `:shared`,
   migraciones, repositorios, build ni CI. La integración la hará FT00026
   (`listByDate` → `rank`).

**Riesgos clave:** (a) **sesgo percibido** — mitigado con señales objetivas
documentadas, pesos modestos (organismo +1), explicación visible y sin IA;
(b) **umbral/pesos arbitrarios** — se fijan como semilla determinista y se
documentan como deuda afinable con datos reales; (c) **`rango`/`organismo` nulos o
irregulares** entre secciones — el ranking los tolera (0 puntos) y no depende de
ellos; (d) **día sin destacados** — aceptado (Scenario 5), el feed muestra el bloque
vacío.

## Expected File Changes

Rutas en el repo de producto (`..`):

- `backend/src/main/kotlin/…/backend/relevance/Highlight.kt` — create;
  `Highlight` + `HighlightReason`.
- `backend/src/main/kotlin/…/backend/relevance/HighlightRanker.kt` — create; ranker
  puro + constantes de señales/umbral/tope.
- `backend/src/test/kotlin/…/backend/relevance/HighlightRankerTest.kt` — create;
  tests del gate (escenarios 1–6), sin red ni BD.
- `docs/desarrollo-local.md` — modify (producto); señales, umbral, «por qué es
  destacada» y ruta de integración futura con el feed.

Harness: `ARCHITECTURE.md`, `CONSTRAINTS.md`, `docs/adr/0008-…` + índice,
`PROGRESS.md`, `feature_list.json` (ver *Durable Documentation Impact*).

**Sin cambios** en `Application.kt`, `:shared`, `:composeApp`, `persistence/`,
migraciones, `libs.versions.toml`, `backend/build.gradle.kts`, raíz del build,
`settings.gradle.kts` ni CI.

## Visual Design Impact

- UI involved: no. Sin pantallas ni tokens. `DESIGN.md` ya describe el consumo
  («bloque de Destacados del día», «explicar de forma breve por qué una publicación
  es destacada»); esta feature solo produce el modelo y las razones. La presentación
  y los textos de las razones se localizan en la UI (FT00032+), fuera de alcance.

## Durable Documentation Impact

- `ARCHITECTURE.md` (harness): update — nuevo paquete de dominio `relevance/` (ranker
  puro y explicable por señales objetivas, sin IA/red/BD); el feed (FT00026) lo
  consumirá sobre `listByDate`.
- `CONSTRAINTS.md`: update — MUST durable: el ranking de destacados es **automático,
  objetivo, determinista y explicable** (señales objetivas documentadas, sin IA ni
  señales editoriales/subjetivas), es **puro** (sin red/BD/reloj) y **expone el
  motivo**; se **calcula *on-the-fly*** (no se persiste) en la 1.0.0.
- **ADR `docs/adr/0008-…`** (recomendado): registrar la decisión durable «destacados
  calculados *on-the-fly* por un ranker puro y explicable, sin persistencia ni IA».
  El planner **no** lo crea; lo escribe el implementador/orquestador e inscribe el
  índice en `docs/adr/README.md`.
- `AGENTS.md` (harness): not needed — no cambia flujo, arranque ni reglas de repo.
- Otros: `docs/desarrollo-local.md` (producto) — update; `README.md`/`ROADMAP.md` —
  not needed.

## Implementation Plan

1. Crear `Highlight`/`HighlightReason` (modelos internos con KDoc).
2. Crear `HighlightRanker` (señales + puntuación + razones + umbral/orden/tope),
   puro y con `return` único / sin `else if` / funciones ≤40 líneas.
3. Escribir `HighlightRankerTest` (escenarios 1–6, incluido el determinismo frente al
   orden de entrada y el caso de día vacío) hasta verde en el gate sin red ni BD.
4. Actualizar `ARCHITECTURE.md`, `CONSTRAINTS.md`, ADR 0008 + índice,
   `docs/desarrollo-local.md`, `PROGRESS.md` y `feature_list.json`; commit/push/PR/CI
   los gestiona el orquestador.

## Implementation Tasks

- [ ] `Highlight.kt` (`Highlight` + `HighlightReason` con KDoc).
- [ ] `HighlightRanker.kt` (señales objetivas, puntuación, razones, umbral, orden, tope).
- [ ] Normalización de `rango`/`organismo` determinista (reutilizar o extraer acotado).
- [ ] `HighlightRankerTest` (día mixto; rango; convocatoria vs anuncio; organismo;
      día vacío; determinismo/orden de entrada).
- [ ] `ARCHITECTURE.md`, `CONSTRAINTS.md`, ADR 0008 + índice, `docs/desarrollo-local.md`,
      `PROGRESS.md`, `feature_list.json`.

## Verification Plan

Desde la raíz del producto (`..`, JDK 21 vía JBR/`JAVA_HOME`):

- **Gate de unidad (sin red ni BD):** `./gradlew :backend:test --rerun-tasks` →
  BUILD SUCCESSFUL con `HighlightRankerTest` en verde; escenarios 1–6 verificados.
- **Gate estándar:** `./gradlew build --no-daemon -PskipClient`, `./gradlew test`,
  `./gradlew detekt` (Detekt + `:cpdCheck`) y `.harness/init.sh` → exit 0.
- **Arranque sin BD:** `./gradlew :backend:run` (o `HealthTest`) → `/health` 200;
  `Application.kt`/Flyway/`:shared`/CI intactos.
- **E2E:** no aplica — sin flujo de usuario, endpoint ni cambio de API; el ranking se
  comprueba de punta a punta con `HighlightRankerTest` en el gate.
- `init.sh` (harness): **no** se modifica.
- Pruebas reales de red/BD (`BOE_LIVE_TEST`/`DB_LIVE_TEST`) **no** son necesarias:
  el ranker es puro y sus entradas ya están cubiertas por fixtures de otras features.

## Evidence To Capture

- Salida de `./gradlew :backend:test` con `HighlightRankerTest` y el recuento
  (0 fallos).
- Ejemplos reales de ranking: identificador → `score` + `reasons` (p. ej. `Ley
  Orgánica` > `Orden`; convocatoria II.B destacada y anuncio V.C fuera), y el caso de
  día vacío → lista vacía.
- Gate sin red/BD (`build -PskipClient`, `test`, `detekt`, `init.sh`) en verde.
- Ficheros del commit `FT00013`, PR y run de CI; entradas en `PROGRESS.md` y
  `feature_list.json` (`evidence`).

## Validator Checklist

- [ ] Alcance acotado: solo `relevance/` + tests + docs; **sin** persistencia/
      migración/repositorio, sin endpoints/UI, sin `:shared`, sin `Application.kt`,
      sin embeddings/chunking (FT00014+), sin tocar el job/backfill ni la CI.
- [ ] Escenarios 1–7 pasan; el subconjunto es **reproducible y explicable** (cada
      destacado con `score` y razones no vacías).
- [ ] El ranking prioriza **rango normativo superior** y señales temáticas/plazo/
      organismo; el organismo es modesto y no decide por sí solo; a igual score,
      orden por `id` (estable).
- [ ] **Puro y determinista**: sin red, BD, IA, reloj ni estado; la salida no depende
      del orden de entrada; día vacío → lista vacía.
- [ ] `return` único, sin `else if`, funciones ≤40 líneas y KDoc en todo lo nuevo;
      identificadores en inglés, KDoc/comentarios en castellano.
- [ ] `:shared`/`PublicacionDto`/JSON de wire **no** cambian; no se crean tipos
      `@Serializable` (no aplica `@SerialName`).
- [ ] Gate `build`/`test`/`detekt`/`init.sh` verde **sin red ni BD**;
      `ARCHITECTURE.md`, `CONSTRAINTS.md`, ADR 0008, `docs/desarrollo-local.md`,
      `PROGRESS.md` y `feature_list.json` actualizados.
- [ ] No unrelated product behavior or extra feature work was added.

## Risks / Open Questions

- **Sesgo percibido.** Señales objetivas documentadas + pesos modestos + explicación
  visible + sin IA mitigan el riesgo (`risks-and-open-questions.md`). Deuda aceptada:
  la lista curada de organismos y los pesos son una semilla afinable.
- **Umbral/pesos arbitrarios.** Se fijan como constantes deterministas y documentadas;
  su afinado con datos reales queda como deuda (no bloquea la 1.0.0).
- **`rango`/`organismo` irregulares entre secciones.** El ranking los tolera (0 puntos)
  y no depende de ellos; no se inventan valores.
- **Recálculo por petición.** Coste trivial hoy; si el feed lo exigiera, un cacheo o
  una persistencia sería una decisión posterior (fuera de alcance).
- **División.** ~4–6 ficheros: muy por debajo de 30 → **atómica**; no se recomienda
  partir en `FT00013-PTn`.
