# Feature Implementation Spec: Clasificación por categoría y extracción de plazos

## Source Feature

- `id`: categorizacion-publicaciones
- `ft_id`: FT00012 (ver `docs/feature-ids.md`)
- `parts`: none (atómica; ~14 ficheros, por debajo del límite de 30)
- `area`: ingesta-boe
- `depends_on`: publicacion-persistencia (FT00008, `accepted`)
- `status`: accepted (implementada, autoverificada y validada de forma independiente; rama `feat/ft00012-categorizacion-publicaciones`)
- `source`: `feature_list.json`

## Goal

Añadir en `:backend` la **clasificación curada** de cada publicación del BOE en una
de las **11 categorías** (`CategoriaDto`) a partir de la **sección** y el **epígrafe**
del BOE (que se conservan como metadato en `Publicacion.epigrafe`), cubriendo las
**ocho secciones** (I, II.A, II.B, III, IV, V.A, V.B y V.C); y la **extracción acotada
de plazos** de convocatorias (empleo público y becas/subvenciones) hacia
`Publicacion.plazo` (`PlazoDto`), quedando **vacío** cuando la fuente no lo indica de
forma fiable. Es la base de `docs/roadmap.md` 0.2-T08.

La lógica es **pura y determinista** (sin red, DB, IA ni aleatoriedad), testeable en
el gate, y se **cablea en el parseo existente**: `PublicacionParser` rellena
`categoria` y `plazo` al construir la `Publicacion`. El job diario (FT00009) y el
backfill (FT00011) reutilizan el parser, así que la clasificación entra en el
pipeline sin tocar `Application.kt` ni el arranque; la persistencia (FT00008) ya
guarda y devuelve ambos campos.

## Non-Goals

- **Embeddings, chunking, pgvector y RAG** → FT00014–FT00018.
- **Destacados / ranking** → FT00013. Aquí solo se etiqueta y se extrae plazo.
- **Endpoints HTTP / API / UI** → FT00026+ y FT00032+.
- **Migraciones Flyway nuevas**: el esquema (columnas `categoria`, `plazo_*`
  nullable) es de FT00008; aquí **no** se toca SQL.
- **Clasificación con IA/LLM** o embeddings: la categoría es una regla curada
  determinista (contrato verificable), no una inferencia generativa.
- **Alertas, calendario de plazos o notificaciones** → 1.x (los plazos solo se exponen).
- **Deduplicación III ↔ V.B** y `topic` finos: fuera del alcance.
- **Reclasificar** publicaciones ya persistidas con valores previos distintos:
  el *upsert* ya sobrescribe; no se añade lógica de reconciliación.

## Job Story

Cuando implemento la ingesta del BOE,
quiero etiquetar cada publicación en una de las 11 categorías curadas y exponer el
plazo de las convocatorias,
para que el feed y los filtros hablen por **familia de contenido**, no por sección.

## Users And Permissions

- Desarrollador / job de ingesta (interno): invoca el clasificador desde el parser
  de `:backend`. Sin cuentas ni autenticación; la lógica es **pura** (sin red/BD).

## Acceptance Scenarios

### Scenario 1: muestra real de las ocho secciones → categoría correcta

Given los ocho fixtures reales que ya ejercita `BoePublicacionParserTest` (uno por
sección) y su `EntradaSumario` del sumario real,
When el parser produce cada `Publicacion`,
Then `categoria` no es nula y es la esperada:

| Identificador | Sección | Epígrafe/título | `CategoriaDto` esperada |
| --- | --- | --- | --- |
| `BOE-A-2026-20979` | I | epígrafe «Subvenciones» | `BECAS_SUBVENCIONES_Y_AYUDAS` |
| `BOE-A-2024-87` | II.A | epígrafe «Destinos» | `NOMBRAMIENTOS_Y_CESES` |
| `BOE-A-2024-93` | II.B | epígrafe «Personal laboral» | `OPOSICIONES_Y_EMPLEO_PUBLICO` |
| `BOE-A-2024-117` | III | epígrafe «Ayudas» | `BECAS_SUBVENCIONES_Y_AYUDAS` |
| `BOE-B-2024-1` | IV | sin epígrafe; título «ALMERIA» | `OTRAS_DISPOSICIONES_Y_ANUNCIOS` |
| `BOE-B-2024-25` | V.A | sin epígrafe; «formalización de contratos» | `INFORMACION_PUBLICA_Y_CONCESIONES` |
| `BOE-B-2024-76` | V.B | sin epígrafe; «Información Pública» | `INFORMACION_PUBLICA_Y_CONCESIONES` |
| `BOE-B-2024-92` | V.C | sin epígrafe; título «COMUNIDAD DE REGANTES…» | `OTRAS_DISPOSICIONES_Y_ANUNCIOS` |

Y en todos los casos `Publicacion.epigrafe` **se conserva** tal cual viene del sumario.

### Scenario 2: convocatoria con plazo en la fuente → plazo expuesto

Given la convocatoria real `BOE-A-2024-93` (II.B; texto con «La documentación se
deberá presentar en el plazo de **quince días hábiles** a contar desde el día
siguiente al de la publicación…») y `BOE-A-2024-117` (III; «El plazo de presentación
de solicitudes será de **quince (15) días hábiles** contados a partir del día
siguiente al de la publicación…»), ambas con fecha de publicación `2024-01-02`,
When el parser produce cada `Publicacion`,
Then `plazo` es un `PlazoDto` con `fechaLimite = "2024-01-23"` (quince días hábiles
desde el día siguiente a la publicación, fin de semana sin contar) y
`descripcion` con la frase/expresión que lo justifica.

### Scenario 3: sin plazo fiable → campo vacío (sin falsos positivos)

Given publicaciones reales que **no** son convocatorias con plazo de solicitud:
`BOE-A-2026-20979` (I; solo «plazo de ejecución» / «entrada en vigor»),
`BOE-A-2024-87` (II.A; «plazo de dos meses» para recurso) y `BOE-B-2024-76` (V.B;
«información pública… contados en la forma dispuesta en el artículo 17»),
When el parser produce cada `Publicacion`,
Then `plazo` es `null` (no se inventa ni se confunde con plazos de ejecución,
resolución, recurso o información pública).

### Scenario 4: casos ambiguos (sin epígrafe o con varios) → categoría representativa

Given una `EntradaSumario` **sin epígrafe** (`epigrafe = null`) o con un epígrafe que
no casa ninguna regla,
When se clasifica,
Then se asigna la **categoría por defecto de la sección** (la más representativa) y
`epigrafe` se conserva sin cambios; con varios epígrafes/reglas aplicables, gana la
primera regla del orden documentado (determinista).

### Scenario 5: determinismo y pureza (gate)

Given la misma entrada (sección, epígrafe, título, texto, fecha),
When se clasifica y se extrae plazo cualquier número de veces,
Then el resultado es idéntico, sin red, sin BD, sin reloj del sistema y sin estado
compartido; `./gradlew :backend:test` lo cubre sin servicios externos.

### Scenario 6: sin romper contratos ni arranque

Given el repositorio tras el cambio,
When se ejecuta el gate y el arranque,
Then `:shared` (contrato `CategoriaDto`/`PlazoDto`/`PublicacionDto`), `Application.kt`,
las migraciones Flyway, la raíz del build y la CI quedan intactos; el servidor sigue
arrancando sin BD y `/health` responde.

## Repository Research

### Files Inspected

- **Harness:** `feature_list.json` (FT00012; FT00008 `accepted`), `PROGRESS.md`,
  `docs/feature-ids.md`, `docs/roadmap.md` §0.2.0 (`0.2-T08`), `CONTEXT.md`
  (§Categoría, §Sección/Epígrafe), `docs/domain-model.md` (Categoría, Plazo, edge
  cases), `docs/build-brief.md` (MVP y plazos), `docs/risks-and-open-questions.md`
  (mapeo imperfecto; modelado de plazos), `DESIGN.md` (11 categorías, plazo
  resaltado), `ARCHITECTURE.md`, `CONSTRAINTS.md`, `docs/adr/0002` y
  `docs/specs/boe-parser-publicacion.md`.
- **Producto (`..`):** `shared/.../model/{CategoriaDto,SeccionBoeDto,PlazoDto,PublicacionDto}.kt`;
  `backend/.../ingesta/publicacion/{Publicacion,DocumentoBoe,BoeXmlParser,
  BoePublicacionParser,PublicacionParser}.kt`; `persistence/PublicationRepository.kt`
  (columnas `categoria`/`plazo_*` + *upsert*); `ingesta/job/IngestionJob.kt` y
  `Application.kt` (wiring del parser); fixtures `boe/sumario-*.json` y `boe/texto-*.xml`;
  tests `BoePublicacionParserTest`/`PublicacionParserTest`.

### Existing Patterns To Follow

- **Dominio puro** sin Ktor/JDBC; clases de lógica con `class`/métodos puros
  (precedente `PublicacionParser`, `MissedIngestionDetector`).
- **Wiring aditivo por constructor con defaults** (precedente `BoePublicacionHttpParser`
  recibe `PublicacionParser = PublicacionParser()`): permite cablear sin tocar
  `Application.kt`.
- **`Publicacion`** ya tiene `categoria: CategoriaDto? = null` y `plazo: PlazoDto? = null`
  (FT00007); reutilizar enums `CategoriaDto`/`SeccionBoeDto` y `PlazoDto` de `:shared`.
- **Tests** `kotlin.test` en espejo del paquete; fixtures reales por sección en
  `src/test/resources/boe/`; gate sin red/BD; sin identificadores en castellano
  (KDoc/comentarios en castellano).
- MUST de estilo: `return` único, sin `else if`, ≤40 líneas/función, KDoc, reutilizar.

### Current Gaps

- No existe `ingesta/categorizacion/`; hoy `categoria` y `plazo` quedan siempre
  `null` (FT00007 los difiere).
- No hay ninguna tabla de reglas sección/epígrafe → categoría ni extractor de plazos.
- `PublicacionParserTest` y `BoePublicacionParserTest` **afirman hoy `categoria == null`**;
  se actualizarán al nuevo contrato (cambio esperado, ver *Risks*).

## Technical Approach

1. **Paquete nuevo** `backend/src/main/kotlin/.../ingesta/categorizacion/`.
2. **`PublicationClassifier.kt`** (puro): `fun classify(section: SeccionBoeDto,
   heading: String?, title: String): CategoriaDto`. Normaliza `heading`/`title`
   (minúsculas, sin acentos, espacios colapsados) y aplica por **orden** una tabla de
   reglas de palabra clave; **primero el epígrafe y luego el título**; si ninguno
   casa, la **categoría por defecto de la sección**. Devuelve **siempre** una
   categoría (nunca nula). Semilla de reglas (el implementador puede afinarla con los
   fixtures, sin romper los escenarios):
   - **Por epígrafe/título** (orden, primer acierto): `convenio`/`acuerdo
     internacional` → CONVENIOS_Y_ACUERDOS; `beca`/`subvencion`/`ayuda` →
     BECAS_SUBVENCIONES_Y_AYUDAS; `premio` → PREMIOS; `plan de estudios` →
     EDUCACION_Y_PLANES_DE_ESTUDIO; `medio ambiente`/`ambiental` → MEDIO_AMBIENTE;
     `recurso` → RECURSOS_Y_RESOLUCIONES; `informacion publica`/`concesion` →
     INFORMACION_PUBLICA_Y_CONCESIONES; `nombramiento`/`cese`/`designacion`/
     `destino`/`integracion`/`situacion` → NOMBRAMIENTOS_Y_CESES; `oposicion`/
     `proceso selectivo`/`seleccion`/`concurso`/`proveer`/`plaza`/`personal`/
     `cuerpo` → OPOSICIONES_Y_EMPLEO_PUBLICO.
   - **Por defecto de sección**: I → NORMAS_Y_LEGISLACION; II.A →
     NOMBRAMIENTOS_Y_CESES; II.B → OPOSICIONES_Y_EMPLEO_PUBLICO; III/IV/V.B/V.C →
     OTRAS_DISPOSICIONES_Y_ANUNCIOS; V.A → INFORMACION_PUBLICA_Y_CONCESIONES.
   - Implementación sin `else if` (p. ej. `firstOrNull` sobre una lista de reglas y
     `?:`), `return` único.
3. **`DeadlineExtractor.kt`** (puro): `fun extract(text: String?, publishedDate:
   String): PlazoDto?`. Extracción **acotada** (heurística, no IA) que reconoce:
   - **Días relativos**: `plazo de <N> días [hábiles|naturales]` con la coletilla
     `a contar|contados|a partir … desde/… el día siguiente al de la publicación`,
     donde `<N>` es dígito o palabra castellana (mapa 1–30). Cómputo: `naturales` →
     `publishedDate + N`; `hábiles` → **N-ésimo día laborable estrictamente posterior**
     a `publishedDate` (se saltan sábados/domingos; **no** se modelan festivos).
   - **Fecha explícita**: `hasta el <d> de <mes> de <aaaa>`, `hasta el <dd/mm/aaaa>`
     o `hasta el <dd-mm-aaaa>` cuando el contexto habla de solicitud/presentación.
   - **Puerta de contexto (anti-falsos-positivos)**: solo se extrae si el fragmento
     habla de «presentación de solicitudes» / «presentar … solicitud/documentación»;
     se **descarta** si casa «plazo de ejecución», «de resolución», «para resolver»,
     «recurso», «subsanación», «alegaciones» o «informe».
   - Devuelve `PlazoDto(fechaLimite = ISO, descripcion = frase coincidente acotada)`
     o `null` (límite de fiabilidad documentado; sin inventar fechas).
   - Usa `java.time.LocalDate` (solo `:backend`, JVM); entrada/salida de fechas como
     `String` ISO para alinear con el resto del código.
4. **Cableado en el parseo**: `PublicacionParser` gana dos colaboradores con default
   (`classifier: PublicationClassifier = PublicationClassifier()`,
   `deadlineExtractor: DeadlineExtractor = DeadlineExtractor()`) y rellena
   `categoria = classifier.classify(seccion, epigrafe, titulo)` y
   `plazo = deadlineExtractor.extract(documento?.texto, fechaPublicacion)`.
   `BoePublicacionHttpParser` no cambia de firma y `Application.kt` queda intacto.
5. **Sin cambios** en `:shared`, `libs.versions.toml`, `backend/build.gradle.kts`,
   migraciones, raíz del build, `settings.gradle.kts` ni CI.

**Riesgos clave:** (a) el mapeo epígrafe→categoría es heurístico (epígrafes
ausentes/solapados) — reglas ordenadas + defaults por sección + fixtures reales;
(b) los plazos son texto libre y abundan los falsos positivos («plazo de ejecución»,
recursos) — patrones acotados + puerta de contexto + fixtures negativos;
(c) `hábiles` sin calendario de festivos — documentado; (d) cambiar el resultado del
parser afecta a tests de FT00007 — cambio esperado y acotado; (e) fecha de
referencia del plazo = fecha de publicación de la entrada (los extractos V.B pueden
publicarse en otra fecha) — límite documentado.

## Expected File Changes

Rutas en el repo de producto (`..`):

- `backend/src/main/kotlin/…/backend/ingesta/categorizacion/PublicationClassifier.kt` — create.
- `backend/src/main/kotlin/…/backend/ingesta/categorizacion/DeadlineExtractor.kt` — create.
- `backend/src/main/kotlin/…/backend/ingesta/publicacion/PublicacionParser.kt` — modify;
  colaboradores con default + relleno de `categoria`/`plazo` (KDoc actualizado).
- `backend/src/test/kotlin/…/backend/ingesta/categorizacion/PublicationClassifierTest.kt` — create (gate, sin red).
- `backend/src/test/kotlin/…/backend/ingesta/categorizacion/DeadlineExtractorTest.kt` — create (gate, sin red).
- `backend/src/test/kotlin/…/backend/ingesta/publicacion/PublicacionParserTest.kt` — modify
  (categoría por sección/regla, plazo con y sin patrón).
- `backend/src/test/kotlin/…/backend/ingesta/publicacion/BoePublicacionParserTest.kt` — modify
  (sustituir `assertNull(categoria)` por la categoría esperada por fixture; añadir plazo).
- `docs/desarrollo-local.md` — modify (producto); clasificación y plazos, límites.

Harness: `ARCHITECTURE.md`, `CONSTRAINTS.md`, `docs/adr/0007-…` + índice,
`PROGRESS.md`, `feature_list.json` (ver *Durable Documentation Impact*).

**Sin cambios** en `Application.kt`, `:shared`, `:composeApp`, `libs.versions.toml`,
`backend/build.gradle.kts`, migraciones, raíz del build, `settings.gradle.kts` ni CI.

## Visual Design Impact

- UI involved: no. Sin pantallas ni tokens. `DESIGN.md` ya describe el consumo de
  `categoria` y `plazo` en el feed/detalle (FT00032+); esta feature solo produce los
  valores. Los textos de las 11 categorías se localizan en la UI, fuera de alcance.

## Durable Documentation Impact

- `ARCHITECTURE.md` (harness): update — `ingesta/categorizacion/` (clasificador
  curado determinista + extractor de plazos acotado, puros), cableados en
  `PublicacionParser`; `categoria`/`plazo` de `publicacion` dejan de ser `null` en la
  ingesta; sin IA ni red.
- `CONSTRAINTS.md`: update — MUST durables: (1) la categoría es una regla **curada
  determinista** a partir de sección/epígrafe (sin IA/LLM), siempre devuelve **una**
  `CategoriaDto` y **conserva** el epígrafe; (2) la extracción de plazos es
  **heurística y acotada** y devuelve **vacío** (`null`) si no es fiable: nunca se
  inventa una fecha.
- **ADR `docs/adr/0007-…`** (recomendado): registrar la decisión durable
  «clasificación curada determinista sección/epígrafe → 11 categorías + extracción de
  plazos acotada (sin IA)». El planner **no** lo crea; lo escribe el implementador/
  orquestador e inscribe el índice en `docs/adr/README.md`.
- `AGENTS.md` (harness): not needed — no cambia flujo, arranque ni reglas de repo.
- Otros: `docs/desarrollo-local.md` (producto) — update; `README.md`/`ROADMAP.md` — not needed.

## Implementation Plan

1. Crear `PublicationClassifier` (normalización + reglas ordenadas + defaults por
   sección) y `DeadlineExtractor` (patrones acotados + puerta de contexto + cómputo
   con `java.time`), ambos puros y con KDoc.
2. Cablear ambos en `PublicacionParser` (parámetros con default) y actualizar KDoc.
3. Ajustar los tests de gate (clasificador, extractor y parser unitario/integración
   con los ocho fixtures reales) hasta cumplir los escenarios 1–3; verificar el gate
   sin red ni BD.
4. Actualizar `ARCHITECTURE.md`, `CONSTRAINTS.md`, ADR 0007 + índice,
   `docs/desarrollo-local.md`, `PROGRESS.md` y `feature_list.json`; commit/push/PR/CI
   los gestiona el orquestador.

## Implementation Tasks

- [ ] `PublicationClassifier` (reglas ordenadas epígrafe→título + default por sección).
- [ ] `DeadlineExtractor` (días naturales/hábiles + fecha explícita + puerta de contexto).
- [ ] `PublicacionParser` recibe colaboradores con default y rellena `categoria`/`plazo`.
- [ ] `PublicationClassifierTest` (ocho secciones + ambiguos sin epígrafe + determinismo).
- [ ] `DeadlineExtractorTest` (positivos II.B/III y negativos I/II.A/V.B).
- [ ] `PublicacionParserTest` actualizado (categoría por regla; plazo con y sin patrón).
- [ ] `BoePublicacionParserTest` actualizado (categoría esperada por fixture + plazo real).
- [ ] `ARCHITECTURE.md`, `CONSTRAINTS.md`, ADR 0007 + índice, `docs/desarrollo-local.md`,
      `PROGRESS.md`, `feature_list.json`.

## Verification Plan

Desde la raíz del producto (`..`, JDK 21 vía JBR/`JAVA_HOME`):

- **Gate de unidad (sin red ni BD):** `./gradlew :backend:test --rerun-tasks` →
  BUILD SUCCESSFUL con `PublicationClassifierTest`, `DeadlineExtractorTest`,
  `PublicacionParserTest` y `BoePublicacionParserTest` en verde; escenario 1
  (ocho secciones), 2 (plazo II.B e III) y 3 (negativos) verificados.
- **Gate estándar:** `./gradlew build --no-daemon -PskipClient`, `./gradlew test`,
  `./gradlew detekt` (Detekt + `:cpdCheck`) y `.harness/init.sh` → exit 0.
- **Arranque sin BD:** `./gradlew :backend:run` (o `:backend:test` de `HealthTest`)
  → `/health` 200; `Application.kt`/Flyway/`:shared`/CI intactos.
- **E2E:** no aplica — sin flujo de usuario, endpoint ni cambio de API; la
  clasificación se comprueba de punta a punta con los fixtures reales en el gate.
- `init.sh` (harness): **no** se modifica.
- Pruebas reales de red (`BOE_LIVE_TEST`) no son necesarias aquí: los fixtures ya
  están capturados y versionados.

## Evidence To Capture

- Salida de `./gradlew :backend:test` con los cuatro tests y el recuento (0 fallos).
- Resultado de clasificación de los ocho fixtures reales (identificador → categoría)
  y del plazo de `BOE-A-2024-93`/`BOE-A-2024-117` (`2024-01-23`) con los negativos
  (`null`).
- Gate sin red/BD (`build -PskipClient`, `test`, `detekt`, `init.sh`) en verde.
- Ficheros del commit `FT00012`, PR y run de CI; entradas en `PROGRESS.md` y
  `feature_list.json` (`evidence`).

## Validator Checklist

- [ ] Alcance acotado: solo `ingesta/categorizacion/` + cableado en
      `PublicacionParser` + tests + docs; sin embeddings/chunking (FT00014+), sin
      destacados (FT00013), sin endpoints/UI, sin migraciones, sin wiring en
      `Application.kt` ni cambios en `:shared`/CI.
- [ ] Escenarios 1–6 pasan; muestra real de las **ocho** secciones clasificada como
      la tabla; ambiguos con categoría representativa y epígrafe conservado.
- [ ] Plazos: II.B/III exponen `2024-01-23`; I/II.A/V.B quedan `null` (sin confundir
      ejecución/recurso/información pública); sin plazo fiable → `null` (no se inventa).
- [ ] Clasificador y extractor **puros y deterministas**: sin red, BD, IA ni reloj;
      la categoría es una regla curada (nunca IA); siempre devuelve una `CategoriaDto`.
- [ ] `return` único, sin `else if`, funciones ≤40 líneas y KDoc en todo lo nuevo;
      identificadores en inglés, KDoc/comentarios en castellano.
- [ ] `PublicacionDto`/`CategoriaDto`/`PlazoDto` y el JSON de wire **no** cambian;
      `@SerialName` explícito no se ve afectado (no se crean DTOs).
- [ ] Gate `build`/`test`/`detekt`/`init.sh` verde **sin red ni BD**;
      `ARCHITECTURE.md`, `CONSTRAINTS.md`, ADR 0007, `docs/desarrollo-local.md`,
      `PROGRESS.md` y `feature_list.json` actualizados.
- [ ] No unrelated product behavior or extra feature work was added.

## Risks / Open Questions

- **Mapeo imperfecto sección/epígrafe → categoría.** Los epígrafes del BOE son
  irregulares y a veces faltan (IV, V.A, V.B, V.C). Mitigación: reglas ordenadas +
  default por sección + fixtures reales; el orden de reglas es el contrato
  determinista. Confirmed: la asunción de `risks-and-open-questions.md` («clasificar
  de forma fiable a partir de sección/epígrafe») se cumple **con tolerancia**; el
  detalle fino (p. ej. «Programas de termalismo social» → OTRAS) es deuda aceptada.
- **Falsos positivos de plazo.** Texto libre con plazos de ejecución/resolución/
  recurso/subsanación; mitigado con puerta de contexto y fixtures negativos. Los
  patrones no cubiertos (fechas en tablas/PDF, «un mes», «entrada en vigor»,
  festivos) se documentan como deuda.
- **Festivos no modelados.** «Días hábiles» cuenta solo sábados/domingos; el
  resultado puede desviarse si el plazo cruza festivos. Documentado; no bloquea.
- **Fecha de referencia del plazo.** Se usa la `fechaPublicacion` de la entrada del
  sumario; los extractos de V.B pueden remitir a la fecha del extracto. Límite
  aceptado por ahora.
- **Cambio de comportamiento del parser.** FT00007 dejaba `categoria = null`; aquí
  pasa a estar rellena. Es el objetivo de FT00012; se actualizan los tests de
  FT00007 afectados (esperado, no es regresión de contrato).
- **División.** ~14 ficheros: por debajo de 30 → **atómica**; no se recomienda
  partir en `FT00012-PTn`.
