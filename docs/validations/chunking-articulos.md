# Validación — `chunking-articulos` (FT00014)

- Veredicto: **`accept`**
- Fecha: 2026-10-10
- Rol: `validator` (independiente, solo lectura; no implementa ni corrige)
- Spec: `.harness/docs/specs/chunking-articulos.md`
- Rama: `feat/ft00014-chunking-articulos` (commit `d586536 chore(FT00014): claim`;
  cambios de la feature **sin commitear** en el árbol de trabajo)
- Estado en `feature_list.json`: `not_started` (sin `evidence`) — ver *Harness*.

> Historial: primera validación (2026-10-10) → **`revise`** por un hallazgo Medium
> (identificadores en castellano en `ArticleChunkerTest.kt`) y un Low (KDoc
> desactualizado en `FragmentRepository.kt`). Reparación del implementer
> verificada de forma independiente en esta revalidación → **`accept`**.

## Checks reejecutados (JAVA_HOME = JBR 21, desde `..`)

| Comando | Resultado |
| --- | --- |
| `./gradlew :backend:test --rerun-tasks` | BUILD SUCCESSFUL; **154** tests, 0 fallos. `ArticleChunkerTest` **9/0/0**. |
| `./gradlew detekt --rerun-tasks` | BUILD SUCCESSFUL (Detekt ×3 + `:cpdCheck`, 4 tareas ejecutadas, sin hallazgos). |
| `env -u JAVA_HOME .harness/init.sh` | **exit 0** («Gate OK»). |

## Reparación verificada

1. **Identificadores en inglés (Medium resuelto).** `ArticleChunkerTest.kt`
   renombrado sin cambio de comportamiento: `publicationFromFixture`,
   `publication`, `resource` (+ `path`), parámetros `section`/`text`, variable
   `publication`. Grep de identificadores de nuevo código: **0** en castellano;
   solo quedan en castellano el KDoc/comentarios, los nombres heredados de
   propiedades de `Publicacion` (`titulo`/`seccion`/`epigrafe`/`texto`, deuda
   FT00047) y literales de datos (`"Artículo 1. Norma extensa."`, `"palabra$index"`,
   `"Publicación $id"`). El código de producción ya estaba íntegramente en inglés.
2. **KDoc corregido (Low resuelto).** Cabecera de `FragmentRepository.kt` ahora:
   «El modelo de dominio y el chunking por artículo ya existen (FT00014); aquí solo
   se guardan y se leen por publicación.»

## Escenarios del spec

1–7 cubiertos por `ArticleChunkerTest` sobre **fixtures reales**, sin red ni BD
(9 tests): 20 encabezados con su referencia + bloque introductorio, cobertura
exacta por líneas (V.B), cobertura por palabras de párrafo partido (I), sección
sin artículos (V.B, `reference = "Sección V_B"`), artículo largo partido con la
misma referencia y ≤512 tokens, `order` contiguo `0..n-1` + determinismo, texto
nulo/vacío/en blanco → lista vacía, y mapeo a `FragmentEntity` con `id = null`.

### Verificación independiente de fixtures

Recuento y clases de encabezados por fixture (script propio sobre los XML):

- `texto-I-2026-20979`: **20** encabezados `Artículo`/`Disposición`, todos
  `class="articulo"` (17 artículos + 3 disposiciones finales); `texto-III-2024-117`:
  **15**; resto de secciones: **0** (variante por sección).
- **0 falsos positivos**: ninguna línea de cuerpo (p. ej. `class="parrafo"`) empieza
  por «Artículo»/«Disposición» en ninguna de las 8 secciones → la heurística
  anclada a inicio de línea es correcta con datos reales.
- `texto-VB-2024-76`: **701** líneas (≈700 párrafos del spec). Líneas > presupuesto
  (`>1536` car.): 1 en I (1625) y 1 en III (2309) → se parten por palabras
  (escenario 4). Sin solapamiento estructural.

## Hallazgos

Ninguno pendiente. El hallazgo Medium (identificadores en castellano) y el Low
(KDoc) han quedado **resueltos y verificados**. Deuda Low opcional, no bloqueante:

- `ArticleChunker` no valida `maxTokens`/`charsPerToken` inyectados (un `0`
  provocaría división por cero / `chunked(0)`); defaults seguros y FT00015 inyecta
  el contador real → `require(...)` opcional.
- El test duplica `MAX_TOKENS`/`HEADER_REGEX` (private en el chunker); aceptable
  como oráculo.

## Seguridad

Sin hallazgos. Sin red ni BD en el código nuevo ni en los tests (solo strings y
`BoeXmlParser` sobre fixtures locales; sin `java.sql`/`HttpClient` en `rag/`).
Sin secretos ni credenciales; sin entrada de usuario no confiable (texto ya
normalizado por el parser XML endurecido de FT00007). `Regex` lineales y anclados
(`^(Artículo|Disposición)\b`, `\s+`) → sin ReDoS. Chunker puro y determinista, sin
reloj ni estado compartido.

## Alcance, arquitectura y estilo

- Alcance acotado verificado por `git status`: solo `rag/Fragment.kt`,
  `rag/chunking/ArticleChunker.kt`, la extensión `Fragment.toEntity()` en
  `persistence/FragmentRepository.kt`, el test espejo y `docs/desarrollo-local.md`.
  **Intactos**: `Application.kt`, `:shared`, `:composeApp`, raíz del build,
  `settings.gradle.kts`, `libs.versions.toml`, migraciones Flyway (`V1`/`V2`, sin
  `embedding`/HNSW) y CI. Sin wiring (grep: `ArticleChunker`/`rag` solo se
  referencian dentro de `rag/` y en el import correcto de `persistence/`).
- Dirección de dependencia correcta (`persistence` → `rag.Fragment`). Modelo de
  dominio `Fragment` sin sufijo. Sin embeddings/ONNX (FT00015), sin pgvector/HNSW
  (FT00016), sin recuperación (FT00017), sin IA ni endpoints.
- Estilo MUST: `return` único por función, sin `else if`, funciones ≪40 líneas,
  KDoc en castellano e identificadores en inglés en producción **y test**. Detekt
  (ReturnCount max 1) verde.

## Documentación y harness

- `ARCHITECTURE.md` (§`:backend` → `rag/`), `CONSTRAINTS.md`
  (§«RAG / fragmentación»), ADR `docs/adr/0009-chunking-determinista-articulo-seccion.md`
  + índice en `docs/adr/README.md`, skill `rag-datapublico/SKILL.md` (§1 «Estado
  actual del producto (FT00014)») y `docs/desarrollo-local.md` actualizados y
  coherentes con la implementación.
- **Pendiente del orquestador (no afecta al juicio de código)**: `feature_list.json`
  FT00014 sigue `not_started` con `evidence` vacío, `docs/feature-ids.md` igual y
  `PROGRESS.md` sin entrada de sesión para FT00014. Al aceptar, el orquestador debe
  persistir estado `accepted` + evidencia.
- `init.sh` sin cambios; `feature_list.json` parsea como JSON válido (46 features).

## Seguimiento

Ninguno bloqueante. La aceptación final la persiste el orquestador en
`feature_list.json` (estado `accepted` + evidencia). Deuda Low opcional arriba.
