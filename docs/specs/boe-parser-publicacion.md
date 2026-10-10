# Feature Implementation Spec: Parser de publicaciones del BOE (metadatos y texto)

## Source Feature

- `id`: boe-parser-publicacion
- `ft_id`: FT00007
- `parts`: none (atómica — 1 modelo + 1 parser + 1 cliente de texto + tests)
- `area`: ingesta-boe
- `depends_on`: boe-sumario-cliente (FT00006, `accepted` y fusionada — PR #6)
- `status`: accepted
- `source`: `feature_list.json`
- Rama de producto ya reclamada: `feat/ft00007-boe-parser-publicacion`.

> **Nota del implementador (2026-10-10).** `categoria` se deja `null` (FT00012),
> como decidió la planificación. `Publicacion` proyecta del XML solo `rango`
> (según *Technical Approach* §2); el resto de metadatos enriquecidos
> (`departamento`, `fechaDisposicion`, `numeroOficial`, `origenLegislativo`) se
> conservan en `DocumentoBoe.metadatos` para FT00008. El XML se selecciona como
> nodo **hijo directo** de `<documento>` (no `getElementsByTagName`, que elegiría
> un `<texto>` anidado en `<analisis>`).

## Nota de alcance: categoría (deferida a FT00012)

La `user_visible_behavior` de la feature menciona «…sección, epígrafe, **categoría**,
texto y URL oficial». Sin embargo, `docs/roadmap.md` asigna la clasificación curada
a **0.2-T08 = FT00012** (`categorizacion-publicaciones`), y el grafo de
dependencias la sitúa **después** de este parser (FT00012 → `publicacion-persistencia`
→ `boe-parser-publicacion`). Decisión de planificación:

- El parser **extrae** los campos crudos de los que depende la clasificación
  (`seccion` y `epigrafe`) y deja `categoria` **sin asignar** (`null`).
- La asignación de `CategoriaDto` (enum curado de 11) es **no-objetivo** de esta
  feature y se implementa en FT00012.
- Discrepancia registrada como riesgo/duda abierta para que el orquestador la
  confirme antes de implementar (ver *Risks / Open Questions*).

## Goal

Añadir en `:backend` un **parser de publicaciones** que, a partir de una
`EntradaSumario` (FT00006), descargue el **texto oficial** de la publicación desde
el endpoint XML del BOE (`https://www.boe.es/diario_boe/xml.php?id=<identificador>`,
ya expuesto en `EntradaSumario.urlXml`) y produzca un modelo interno `Publicacion`
con identificador, título, fecha, organismo, sección, epígrafe, **texto completo**,
URL oficial y metadatos enriquecidos del XML (rango, departamento, fecha de
disposición, número oficial). Es la base de `docs/roadmap.md` 0.2-T02: la
persistencia (FT00008) y el job diario (FT00009) consumirán este parser.

El parser **no** clasifica (FT00012), **no** fragmenta (FT00014), **no** persiste
(FT00008) y **no** se cablea en el arranque del servidor: es una librería de
`:backend` con sus tests.

## Non-Goals

- **Categorización curada** (`CategoriaDto`) y **extracción de plazos** → FT00012.
  El parser deja `categoria = null`.
- **Persistencia** (tablas, repositorios, Flyway) → FT00008; ninguna BD aquí.
- **Job programado**, reintentos, backoff, segunda pasada, backfill → FT00009/FT00011.
- **Chunking / fragmentación** y embeddings → FT00014+.
- **Fallback HTML (`txt.php`) o PDF**: la vía de texto es el **XML estructurado**;
  se documenta como fuera de alcance (todos los `item` de los fixtures reales
  exponen `url_xml`). No se parsea HTML en esta feature.
- **Enriquecimiento por `url_pdf`/imágenes**: una publicación sin texto XML
  disponible se acepta con `texto = null`.
- **Wiring en el arranque**: `Application.kt` no crea ni invoca el parser.
- **Endpoint HTTP** que exponga publicaciones → FT00026+.

## Job Story

Cuando implemento la ingesta del BOE,
quiero convertir cada entrada del sumario en una publicación con su texto oficial
completo y metadatos fiables,
para persistirlas, clasificarlas y resumirlas sin volver a interpretar la fuente
en cada feature.

## Users And Permissions

- Desarrollador / job de ingesta (interno): invoca el parser desde código de
  `:backend`. Sin cuentas, sin datos personales, sin autenticación (fuentes
  públicas de solo lectura; sin clave).

## Acceptance Scenarios

### Scenario 1: fixture real de cada sección → campos obligatorios

Given un fixture real del texto XML (`xml.php`) de una publicación de **cada** una
de las ocho secciones (I, II.A, II.B, III, IV, V.A, V.B, V.C) y su `EntradaSumario`
del sumario real,
When el parser lo procesa,
Then la `Publicacion` resultante tiene identificador, título, fecha ISO-8601,
sección, organismo/epígrafe (cuando la fuente los ofrece), **texto no vacío** y
**URL oficial**, sin descartar ninguna sección.

### Scenario 2: publicación extensa

Given una publicación extensa (Sección I, p. ej. `BOE-A-2026-20979`; XML real de
~58 KB con decenas de párrafos y tablas),
When el parser la procesa,
Then el texto completo se conserva (no truncado), con separación por párrafos, y
los metadatos se extraen correctamente.

### Scenario 3: publicación sin texto completo disponible

Given una publicación cuyo XML no tiene `<texto>` (o trae `<texto/>` vacío), o
cuyo `xml.php` responde `404`,
When el parser la procesa,
Then produce una `Publicacion` **válida** con todos los metadatos y la URL oficial,
y `texto = null` (sin excepción y sin inventar texto).

### Scenario 4: variantes por sección

Given entradas de Secciones IV/V.C (llegan bajo `departamento.texto.item`, sin
`control` y sin `epigrafe`) y entradas tipo «B» de V.A/V.B (sin `control`), frente a
entradas tipo «A» de I/II.A/II.B/III (con `control`),
When el parser las procesa,
Then todas producen el mismo modelo `Publicacion` (mismos campos obligatorios),
tratando `organismo`, `epigrafe`, `control` y `rango` como opcionales.

### Scenario 5: error al descargar el texto

Given un error de red o una respuesta HTTP distinta de `200`/`404` al pedir el
texto XML,
When el cliente de texto procesa la respuesta,
Then lanza `BoeTextoException` tipada con mensaje claro (identificador y
estado/causa), sin devolver datos parciales silenciosos. `404` se traduce a
`null` («sin texto disponible»).

### Scenario 6: petición correcta al endpoint XML

Given una `EntradaSumario` con `urlXml`,
When el cliente descarga el texto,
Then hace `GET <urlXml>` (URL absoluta del BOE) con cabecera `Accept:
application/xml`, y decodifica el cuerpo como UTF-8.

### Scenario 7: entrada sin `urlXml`

Given una `EntradaSumario` con `urlXml = null`,
When el parser la procesa,
Then **no** hace ninguna petición y produce la `Publicacion` con `texto = null`.

### Scenario 8: llamada real (opt-in, manual)

Given conectividad y `BOE_LIVE_TEST=1`,
When se ejecuta el test opt-in contra una publicación real del BOE,
Then descarga el XML real y produce una `Publicacion` con texto no vacío.
**Fuera del gate y de la CI** (ver *Verification Plan*).

## Repository Research

### Files Inspected

- `.harness/feature_list.json` (FT00007 y dependencia FT00012),
  `PROGRESS.md`, `docs/feature-ids.md`, `docs/roadmap.md` §0.2.0 (`0.2-T02`),
  `docs/domain-model.md` (Publicación, edge cases «sin texto» y «extensa»),
  `docs/technical-discovery.md` (corpus y BOE), `docs/risks-and-open-questions.md`,
  `ARCHITECTURE.md`, `CONSTRAINTS.md`, `docs/desarrollo-local.md` y skill
  `rag-datapublico` (normalización de texto, chunking por sección).
- Producto `..`: `ingesta/sumario/{BoeSumarioClient, BoeSumarioHttpClient,
  SumarioWireDto, SingleOrArraySerializer, EntradaSumario}.kt` (FT00006);
  `Application.kt` (sin wiring de ingesta); `backend/build.gradle.kts` (cliente
  Ktor CIO + `ktor-client-mock` ya presentes); `shared/.../PublicacionDto.kt`,
  `SeccionBoeDto.kt`, `CategoriaDto.kt`; `SumarioParsingTest.kt`; fixtures
  `backend/src/test/resources/boe/sumario-{20261009,20240102}.json`.
- Fuente real (comprobada con `curl`): `xml.php?id=…` devuelve
  `<documento><metadatos>…</metadatos><texto>…</texto></documento>`;
  los párrafos son `<p class="parrafo|parrafo_2|anexo_num…">`, con `<em>`,
  `<table>`/`<tr>`/`<td>` y espacios duros (`\u00a0`). Ejemplos verificados:
  `BOE-A-2024-87` (II.A, con tabla), `BOE-B-2024-1` (IV, texto corto),
  `BOE-B-2024-92` (V.C), `BOE-A-2026-20979` (I, extensa, ~58 KB).

### Existing Patterns To Follow

- Feature-first en `:backend`; paquete propio en `ingesta/…`; dominio puro sin
  Ktor/HTTP.
- Clientes con `HttpClient` **inyectado**, `expectSuccess = false`, traducción a
  modelos internos y excepción tipada (patrón `BoeSumarioClient`/`BoeSumarioException`).
- Modelo interno sin serialización ni sufijo `Dto` (precedente `EntradaSumario`).
- Tests `kotlin.test` en espejo del paquete; fixtures reales en
  `backend/src/test/resources/boe/`; gate sin red (opt-in por `BOE_LIVE_TEST=1`).
- `@SerialName` explícito solo aplica a tipos `@Serializable`; el XML se parsea con
  DOM/StAX, así que no se crean wire DTOs ni se necesita esa regla.

### Current Gaps

- No existe el paquete `ingesta/publicacion/` ni ningún parser de texto.
- No hay ningún consumidor que combine sumario + texto.
- No hay parser XML ni dependencia de XML (se usará el parser XML del JDK).

## Technical Approach

1. **Paquete nuevo** `backend/src/main/kotlin/.../ingesta/publicacion/`.
2. **Modelo interno** `Publicacion.kt` (data class sin serialización ni `Dto`):
   `id` (identificador), `titulo`, `fechaPublicacion` (ISO-8601 `String`),
   `organismo: String?`, `seccion: SeccionBoeDto`, `epigrafe: String?`,
   `texto: String?`, `urlOficial: String`, `urlXml: String?`, `urlPdf: String?`,
   `rango: String?` (del XML; útil para destacados FT00013),
   `categoria: CategoriaDto? = null` (KDoc: «pendiente de FT00012»).
3. **Modelo del XML** `DocumentoBoe.kt` (sin `Dto`): `texto: String?` +
   `metadatos: MetadatosBoe` (`rango`, `departamento`, `fechaDisposicion`,
   `numeroOficial`, `urlPdf`, `origenLegislativo` — todos opcionales).
4. **Parser XML puro** `BoeXmlParser.kt`: `parse(xml: String): DocumentoBoe` con el
   **parser XML del JDK** (DOM o StAX), **seguro**: `FEATURE_SECURE_PROCESSING`,
   DTD y entidades externas **deshabilitadas** (`disallow-doctype-decl`,
   `ACCESS_EXTERNAL_DTD`/`SCHEMA` = "") para evitar XXE y *billion laughs*.
   Extrae los nodos de `<metadatos>` y recorre `<texto>` concatenando el texto de
   los bloques (`p`, `li`, `tr`/`td`) con saltos de párrafo y normalizando
   `\u00a0`→espacio y espacios repetidos. `<texto>` ausente/vacío → `texto = null`.
   XML malformado → `BoeTextoException` (misma tipada que el cliente).
5. **Cliente de texto** `BoeTextoClient.kt` (interfaz
   `suspend fun obtenerDocumento(urlXml: String): DocumentoBoe?`) +
   `BoeTextoException`; `BoeTextoHttpClient.kt` (impl con `HttpClient` inyectado,
   `GET urlXml` con `Accept: application/xml`, `404` → `null`, cuerpo como texto
   UTF-8 → `BoeXmlParser`; otro estado/red/cuerpo ilegible → `BoeTextoException`).
   Factory `boeTextoHttpClient()` (CIO, `expectSuccess = false`). Sin default de
   base URL: `urlXml` es absoluto.
6. **Parser de publicación puro** `PublicacionParser.kt`:
   `fun parsear(entrada: EntradaSumario, documento: DocumentoBoe?): Publicacion`
   (mapea campos del sumario + texto/metadatos del XML; tolerante a `documento = null`;
   `organismo`/`epigrafe`/`control`/`rango` opcionales; `categoria = null`).
7. **Orquestador** `BoePublicacionParser.kt` (interfaz + impl):
   `suspend fun parsear(entrada: EntradaSumario): Publicacion` — descarga el texto
   (si `urlXml != null`) y delega en `PublicacionParser`. Punto de entrada para
   FT00008/FT00009.
8. **Sin wiring**: `Application.kt`, Flyway, `:shared`, `:composeApp` y CI intactos.

**Riesgos clave:** (a) XXE al parsear XML remoto — mitigado con *secure
processing*; (b) variabilidad estructural por sección (IV/V.C sin `control`/
`epigrafe`, XML cortos o con tablas) — modelo nullable + tests por sección;
(c) publicaciones sin `<texto>` (imagen/PDF) — `texto = null` sin romper;
(d) publicaciones muy extensas — DOM en memoria (~decenas–cientos de KB, aceptable
en el N100; vigilar una ley enorme); (e) `categoria` mencionada en la feature pero
de FT00012 — ver *Nota de alcance*.

## Expected File Changes

Rutas en el repo de producto (`..`):

- `backend/src/main/kotlin/es/aviferdev/datopublico/backend/ingesta/publicacion/Publicacion.kt` — create.
- `…/ingesta/publicacion/DocumentoBoe.kt` — create.
- `…/ingesta/publicacion/BoeXmlParser.kt` — create.
- `…/ingesta/publicacion/BoeTextoClient.kt` — create (interfaz + `BoeTextoException`).
- `…/ingesta/publicacion/BoeTextoHttpClient.kt` — create (+ factory).
- `…/ingesta/publicacion/PublicacionParser.kt` — create.
- `…/ingesta/publicacion/BoePublicacionParser.kt` — create (interfaz + impl).
- `backend/src/test/kotlin/…/ingesta/publicacion/{BoeXmlParserTest,PublicacionParserTest,BoeTextoClientTest,BoePublicacionParserTest,BoePublicacionLiveTest}.kt` — create.
- `backend/src/test/resources/boe/texto-{I-2026-20979,IIA-2024-87,IIB-2024-93,III-2024-117,IV-2024-1,VA-2024-25,VB-2024-76,VC-2024-92}.xml` — create (fixtures reales, uno por sección).
- `backend/src/test/resources/boe/texto-sin-texto.xml` — create (XML mínimo con `<texto>` vacío; sintético, marcado como tal).
- `docs/desarrollo-local.md` — update (ligero): endpoint XML del BOE, captura de fixtures y check opt-in.

**Sin cambios** en `gradle/libs.versions.toml`, `backend/build.gradle.kts`
(se reutilizan Ktor CIO/mock y el parser XML del JDK), `Application.kt`, `:shared`,
`:composeApp`, la raíz del build ni el CI.

## Visual Design Impact

- UI involved: no. Sin pantallas, tokens ni textos de UI.

## Durable Documentation Impact

- `ARCHITECTURE.md` (harness): update — `ingesta/` añade el parser de publicaciones
  y el cliente del texto XML; anotar la frontera **Backend → BOE (texto oficial,
  solo lectura)** y que sigue **sin wiring** en el arranque.
- `CONSTRAINTS.md`: update — MUST durable de seguridad: el XML remoto de la fuente
  se parsea con *secure processing* (sin DTD/entidades externas). Y recordar que la
  descarga de texto es red y por tanto gobernada por la regla de tests opt-in ya
  existente.
- `AGENTS.md`, `init.sh`: not needed — no cambia flujo, arranque ni repo.
- **ADR** `docs/adr/0002-…` (recomendado): registrar la decisión durable «la fuente
  de texto y metadatos del BOE es el **XML estructurado** (`xml.php`), no el HTML
  (`txt.php`) ni el PDF». Condiciona FT00008/FT00014. El planner **no** lo crea;
  lo escribe el implementador/orquestador (ver `docs/adr/README.md`).
- Otros: `docs/desarrollo-local.md` (producto) — update ligero; `README.md`/
  `ROADMAP.md` — not needed.

## Implementation Plan

1. Crear el modelo `Publicacion` y `DocumentoBoe` (sin serialización).
2. Implementar `BoeXmlParser` (JDK, seguro) con extracción de metadatos y texto;
   cubrir `<texto>` ausente/vacío y XML malformado.
3. Implementar `BoeTextoClient`/`BoeTextoHttpClient` + factory y `BoeTextoException`
   (`404` → `null`, error tipado, `Accept: application/xml`).
4. Implementar `PublicacionParser` (puro) y el orquestador `BoePublicacionParser`.
5. Capturar los **8 fixtures XML reales** (uno por sección; la Sección I extensa)
   y el XML mínimo «sin texto»; escribir los tests con `MockEngine` (sin red) y el
   test opt-in `BOE_LIVE_TEST=1` fuera del gate.
6. Verificar `:backend:test` y el gate sin red; actualizar `ARCHITECTURE.md`,
   `CONSTRAINTS.md`, `docs/desarrollo-local.md`, `PROGRESS.md` y
   `feature_list.json`; commit/push/PR/CI los gestiona el orquestador.

## Implementation Tasks

- [ ] `Publicacion` (modelo interno; `categoria = null` documentado).
- [ ] `DocumentoBoe` + `MetadatosBoe`.
- [ ] `BoeXmlParser` seguro (DOM/StAX), texto por párrafos, `\u00a0` normalizado.
- [ ] `BoeTextoClient` + `BoeTextoHttpClient` + factory + `BoeTextoException`.
- [ ] `PublicacionParser` puro (sumario + documento → `Publicacion`).
- [ ] `BoePublicacionParser` (interfaz + impl): orquesta descarga + parseo.
- [ ] 8 fixtures XML reales (uno por sección, I extensa) + fixture «sin texto».
- [ ] Tests `MockEngine`: por sección, extensa, sin texto, sin `urlXml`, `404`,
      error tipado, XML malformado.
- [ ] Test opt-in `BoePublicacionLiveTest` (env-gated) fuera del gate.
- [ ] `ARCHITECTURE.md`, `CONSTRAINTS.md`, `docs/desarrollo-local.md`,
      `PROGRESS.md` y `feature_list.json` actualizados. ADR 0002 (recomendado).

## Verification Plan

Desde la raíz del producto (`..`, JDK 21 vía JBR/`JAVA_HOME`):

- **Fixtures por sección (verificación 1, en el gate):**
  `./gradlew :backend:test --rerun-tasks` → BUILD SUCCESSFUL, XML sin
  failures/errors. Los tests con `MockEngine`/fixtures reales (sin red) comprueban:
  campos obligatorios por sección (I, II.A, II.B, III, IV, V.A, V.B, V.C), la
  publicación extensa (texto largo, párrafos) y la publicación **sin texto**
  (`texto = null`, publicación válida).
- **Llamada real (verificación 2, manual/opt-in, fuera del gate):**
  `BOE_LIVE_TEST=1 ./gradlew :backend:test --tests '*BoePublicacionLiveTest'` →
  descarga el XML real de una publicación conocida y produce texto no vacío; o
  `curl -s 'https://www.boe.es/diario_boe/xml.php?id=BOE-A-2024-87' | head`.
- **Gate estándar sin red ni BD:** `./gradlew build --no-daemon -PskipClient` →
  BUILD SUCCESSFUL; `./gradlew test` → 3 módulos verdes; `./gradlew detekt`
  (Detekt + `:cpdCheck`) sin hallazgos; `.harness/init.sh` → exit 0.
- **E2E:** no aplica — no hay flujo de usuario ni endpoint nuevo; los tests con
  `MockEngine` cubren el parser de punta a punta sin red.
- `init.sh` (harness): **no** se modifica.

## Evidence To Capture

- Salida de `./gradlew :backend:test` con `BoeXmlParserTest`, `PublicacionParserTest`,
  `BoeTextoClientTest`, `BoePublicacionParserTest` y `BoePublicacionLiveTest`
  (opt-in), y recuento de publicaciones por sección sobre los fixtures.
- Salida real de `xml.php` (HTTP 200, `<texto>` no vacío) con el identificador usado,
  y prueba de `<texto>` vacío/`404` → `texto = null`.
- Prueba de la publicación extensa (longitud del texto y nº de párrafos).
- Gate sin red: `./gradlew build`, `./gradlew test`, `./gradlew detekt` e `init.sh`
  (exit 0).
- Ficheros del commit `FT00007`, PR y run de CI; entradas en `PROGRESS.md` y
  `feature_list.json` (`evidence`).

## Validator Checklist

- [ ] Alcance acotado: solo parser de publicaciones + cliente de texto XML + su
      modelo + tests; sin BD, sin endpoint, sin clasificación/categoría (deferida a
      FT00012), sin chunking, sin job y sin wiring en el arranque (`Application.kt`
      intacto).
- [ ] Escenarios 1–8 pasan: fixture real por sección; extensa; sin texto
      disponible; variantes IV/V.C y tipo «B»; error tipado/`404`→`null`; petición
      `GET <urlXml>` con `Accept: application/xml`; sin `urlXml` → sin petición;
      llamada real opt-in.
- [ ] Los 8 fixtures XML son **respuestas reales** del BOE (bytes verificables) y
      la publicación extensa es real; el fixture «sin texto» es sintético y está
      marcado como tal.
- [ ] El XML se parsea con *secure processing* (sin DTD/entidades externas); no hay
      `else if`, hay `return` único por función, funciones ≤40 líneas y KDoc.
- [ ] `categoria` queda `null` y está documentado (no se implementa FT00012).
- [ ] El gate `./gradlew build`/`test`/`detekt`/`init.sh` sigue verde **sin red** ni
      servicios externos; los tests de red son opt-in.
- [ ] `ARCHITECTURE.md`, `CONSTRAINTS.md`, `docs/desarrollo-local.md`,
      `PROGRESS.md` y `feature_list.json` actualizados; ADR 0002 valorado.
- [ ] No unrelated product behavior or extra feature work was added.

## Risks / Open Questions

- **Categoría en la descripción de la feature vs FT00012.** El grafo de
  dependencias (`FT00012 → publicacion-persistencia → boe-parser-publicacion`) sitúa
  la clasificación después de este parser, pero la `user_visible_behavior` lista
  «categoría». Decisión: el parser **no** asigna categoría (`null`). *Confirmar con
  el orquestador*; si se quiere una categoría provisional aquí, es un cambio de
  alcance que debe validarse antes de implementar.
- **Estructura irregular por sección** (II.A/II.B/III/IV/V.A/V.B/V.C): campos
  ausentes y XML cortos; el modelo nullable + fixtures por sección lo cubren, pero
  puede aparecer una variante nueva (vigilada por el job, FT00009).
- **Publicaciones sin texto XML** (imagen/PDF): `texto = null`. Hoy no se ha
  confirmado un caso real vacío en los fixtures; el test usa un XML mínimo
  sintético. Si en producción abundan, valorar fallback a `txt.php`/OCR (fuera de
  alcance, 1.x).
- **XXE / XML malicioso**: mitigado con *secure processing*; es un MUST de seguridad.
- **Volumen y memoria (N100)**: ~200–400 XML/día; DOM por documento es aceptable,
  pero una ley muy extensa (MB) puede pesar; si ocurre, migrar a StAX/streaming.
- **Truststore JVM**: el test opt-in en JVM puede requerir la raíz **FNMT-RCM**
  (limitación ya documentada en FT00006/`docs/desarrollo-local.md`); `curl` usa el
  llavero del sistema. No afecta al gate.
