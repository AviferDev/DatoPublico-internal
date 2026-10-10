# Validación — `embeddings-locales-onnx` (FT00015)

- Veredicto: **`accept`**
- Fecha: 2026-10-10
- Rol: `validator` (independiente, solo lectura; no implementa ni corrige)
- Spec: `.harness/docs/specs/embeddings-locales-onnx.md`
- Rama: `feat/ft00015-embeddings-locales-onnx` (commit `121bfe7 chore(FT00015):
  claim`; cambios de la feature **sin commitear** en el árbol de trabajo)
- Estado en `feature_list.json`: `accepted` (persistido por el orquestador el
  2026-10-10).

## Checks reejecutados (JAVA_HOME = JBR 21, desde `..`)

| Comando | Resultado |
| --- | --- |
| `./gradlew :backend:test --rerun-tasks` | BUILD SUCCESSFUL; `:backend` **173** tests, 0 fallos/errores (36 clases XML). Nuevos: `VectorMathTest` 6, `E5EmbeddingProviderTest` 7, `EmbeddingConfigTest` 5, `E5EmbeddingLiveTest` 1 (omitido sin env). |
| `./gradlew build --no-daemon -PskipClient` | BUILD SUCCESSFUL (23 tareas). |
| `./gradlew test` | BUILD SUCCESSFUL (3 módulos). |
| `./gradlew detekt --rerun-tasks` (+`:cpdCheck`) | BUILD SUCCESSFUL (4 tareas, sin hallazgos). |
| `env -u JAVA_HOME .harness/init.sh` | **exit 0** («Gate OK»). |
| `EMBEDDING_LIVE_TEST=1 … '*E5EmbeddingLiveTest'` | BUILD SUCCESSFUL (modelo real); evidencia reproducida. |

## Evidencia del modelo real (opt-in, fuera del gate)

- Modelo: `backend/models/multilingual-e5-small/` (espejo `Xenova/multilingual-e5-small`,
  **gitignored**; `git check-ignore` OK, `git ls-files` vacío).
  `model.onnx` 118.308.185 B, sha256 `f80102d3…f98c193`;
  `tokenizer.json` 17.082.730 B, sha256 `0b44a9d7…ebdf4c39`.
- Salida reproducida de forma independiente: `dims=384`, `norm=1.0`,
  `cos(rel,par)=0.9693954`, `cos(rel,unrel)=0.849925`, `cos(par,unrel)=0.8374902`,
  `countTokens(passage)=24`. Cumple los dos criterios de `verification`
  (384 dims y `cos(relacionados) > cos(no_relacionados)` con textos del dominio BOE).

## Escenarios del spec

1–7 cubiertos: contrato de 384 dims y rechazo de dims ≠384, orden de similitud
coseno, prefijos `query: `/`passage: ` (capturados en el tokenizador), vectores
normalizados (norma ≈1, guarda `EPS`), fail-fast con `EmbeddingException`,
`close()` idempotente y `countTokens` del *seam*. El gate verifica la aritmética y
los contratos con **dobles deterministas**; la semántica del E5 real se verifica
en el test **opt-in**.

## Offline y seguridad

- El gate no hace red ni BD; sin `EMBEDDING_LIVE_TEST` el test imprime «omitido» y
  no construye el proveedor ni abre sockets. El modelo/tokenizador no se commitean.
- Sin secretos ni credenciales en el diff (solo URLs públicas de Hugging Face);
  sin datos personales, entrada de usuario, SQL ni endpoints; DJL/ONNX cargan de
  fichero local. Único punto (Low): integridad de la descarga (hash no verificado
  en el script).

## Alcance, arquitectura y estilo

- Diff de producto: **17 ficheros** = 4 modificados (`.gitignore`,
  `backend/build.gradle.kts`, `gradle/libs.versions.toml`, `docs/desarrollo-local.md`)
  + 13 nuevos (8 `main` en `rag/embeddings/`, 4 tests, 1 script).
- **Sin** columna vectorial/HNSW ni migración (FT00016), **sin** recuperación
  (FT00017), **sin** resúmenes/IA, **sin** endpoints y **sin** wiring: `grep` no
  encuentra referencias a embeddings fuera de `rag/embeddings/` ni en
  `Application.kt`; `ArticleChunker`/`Fragment`/`persistence/`/`:shared`/
  `:composeApp`/CI/`init.sh` intactos.
- Estilo MUST: `return` único (Detekt `ReturnCount max=1` verde), sin `else if`,
  funciones ≪40 líneas, KDoc en castellano e identificadores en inglés; sin
  `return@`, `TODO` ni `FIXME`.

## Desviación `token_type_ids`

Correcta y documentada. El export real declara `input_ids`/`attention_mask`/
`token_type_ids`; `OnnxEmbeddingModel` añade el tercero a ceros **solo si el modelo
lo declara**, lee `last_hidden_state` y hace *mean pooling* con máscara. La
inferencia real pasa y produce cosenos coherentes → no oculta ningún fallo.
Registrada en el spec («Nota de implementación»), `feature_list.json` y ADR 0010.

## Hallazgos (todos Low, no bloquean)

1. **`countTokens` trunca a 512 (prescrito por el spec).** `E5Tokenizer` usa
   `optMaxLength(512)`/`optTruncation(true)`, así que no puede distinguir un texto
   de 512 de uno de 600 tokens. Recomendación para FT00016: contar sin truncar o
   validar el presupuesto por otra vía.
2. **Script de descarga sin verificación de integridad.** Usa `…/resolve/main` (ref
   mutable) y no comprueba sha256. Fijar revisión + hash (script dev-only, fuera
   del gate/CI).
3. **Fuga menor de recurso en `E5EmbeddingProvider.from`.** Si el modelo falla tras
   crear el tokenizador, este no se cierra (`try/finally`).
4. **`close()` idempotente solo a nivel de proveedor.** `OnnxEmbeddingModel`/
   `E5Tokenizer` no guardan estado; el escenario 6 (proveedor) sí se cumple.

## Documentación y harness

Coherente y completa: `ARCHITECTURE.md` (frontera IA + `rag/embeddings/`),
`CONSTRAINTS.md` §«Embeddings locales», **ADR 0010** + índice, skill
`rag-datapublico` §2, `docs/desarrollo-local.md`, `docs/feature-ids.md` (FT00015 →
`accepted`), `docs/risks-and-open-questions.md` y `PROGRESS.md` (Session 047).
`AGENTS.md` no requería cambios.

## Seguimiento

Ninguno bloqueante. Deuda Low arriba: llevar el hallazgo #1 a FT00016 y, si
procede, #2–#4 a la deuda del backlog. La aceptación final queda persistida por el
orquestador en `feature_list.json` (estado `accepted` + evidencia).
