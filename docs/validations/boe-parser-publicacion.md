# Validación — `boe-parser-publicacion` (FT00007)

- Veredicto: **`accept`**
- Fecha: 2026-10-10
- Rol: `validator` (independiente, solo lectura; no implementa ni corrige)
- Spec: `.harness/docs/specs/boe-parser-publicacion.md`
- Rama: `feat/ft00007-boe-parser-publicacion` (commit `chore(FT00007): claim`;
  cambios de la feature **sin commitear** en el árbol de trabajo)
- Estado en `feature_list.json`: `passing` (listo para validación)

## Checks reejecutados (JAVA_HOME = JBR 21, desde `..`)

| Comando | Resultado |
| --- | --- |
| `./gradlew :backend:test --rerun-tasks` | BUILD SUCCESSFUL; **43** tests, 0 fallos. 23 nuevos en `ingesta/publicacion`: `BoeXmlParserTest` 8, `PublicacionParserTest` 4, `BoeTextoClientTest` 6, `BoePublicacionParserTest` 4, `BoePublicacionLiveTest` 1 (opt-in, no-op). |
| `./gradlew build --no-daemon -PskipClient` | BUILD SUCCESSFUL (23 tareas). |
| `./gradlew test` (con Android SDK) | BUILD SUCCESSFUL; `:shared:jvmTest` + `:backend:test` + `:composeApp:jvmTest`. |
| `./gradlew detekt -PskipClient --rerun-tasks` | BUILD SUCCESSFUL; Detekt + `:cpdCheck` sin hallazgos (analiza el código nuevo). |
| `env -u JAVA_HOME .harness/init.sh` | **exit 0** («Gate OK»). |
| `BOE_LIVE_TEST=1 … --tests '*BoePublicacionLiveTest'` | FALLA con `SunCertPathBuilderException` (truststore del JBR sin la raíz FNMT-RCM) — limitación de entorno ya documentada, no defecto de la implementación. |

### Fixtures reales (byte a byte)

Los 8 fixtures XML se re-descargaron con `curl` (HTTP 200) y son **byte-idénticos**
(`shasum -a 256`) a los versionados:

`BOE-A-2026-20979` (I, 58678 B), `BOE-A-2024-87` (II.A, 6427), `BOE-A-2024-93`
(II.B, 24937), `BOE-A-2024-117` (III, 41192), `BOE-B-2024-1` (IV, 1116),
`BOE-B-2024-25` (V.A, 11776), `BOE-B-2024-76` (V.B, 55105), `BOE-B-2024-92`
(V.C, 2955). `texto-sin-texto.xml` es **sintético** y está marcado con un
comentario XML explícito; `<texto/>` vacío.

## Escenarios del spec

1–7 cubiertos por tests con `MockEngine`/fixtures reales (sin red). 8 (opt-in)
env-gated por `BOE_LIVE_TEST`; el flujo real queda probado por los fixtures
byte-idénticos + el gate. Detalle: campos por sección y 8 secciones
(`BoePublicacionParserTest`), extensa >40 000 car./>140 párrafos (153 `<p>` en el
fixture I), sin texto y sin nodo `<texto>`, variantes IV/V.C y tipo B, `404`→`null`,
error tipado (500, red, cuerpo ilegible), `GET <urlXml>` con `Accept:
application/xml`, sin `urlXml` → 0 peticiones.

## Hallazgos

Sin hallazgos Critical/High/Medium.

- **Low (deuda)**: `boeTextoHttpClient()` no fija `HttpTimeout` explícito (misma
  deuda que FT00006, apuntada a FT00009). Sin impacto en el gate (no se cablea).
- **Low (nota)**: `BoeTextoHttpClient.parse` re-envuelve un `BoeTextoException`
  del parser en otro `BoeTextoException` («Respuesta ilegible…»); el mensaje de
  la causa conserva el detalle. No afecta al contrato.
- **Low (nota)**: la implementación del orquestador se llama
  `BoePublicacionHttpParser` (patrón `BoeSumarioHttpClient`); coherente con el
  fichero `BoePublicacionParser.kt` (interfaz + impl) del spec.

## Seguridad

- XML remoto parseado con *secure processing*: `FEATURE_SECURE_PROCESSING`,
  `disallow-doctype-decl`, `ACCESS_EXTERNAL_DTD`/`ACCESS_EXTERNAL_SCHEMA` vacíos y
  `isExpandEntityReferences = false`. Test explícito que rechaza un XXE
  (`<!ENTITY xxe SYSTEM "file:///etc/passwd">`) → `BoeTextoException`.
- Sin secretos ni credenciales en el diff; fixtures y URLs son contenido público
  del BOE. Sin autenticación (fuente pública de solo lectura).
- Sin red en el gate: los tests doblan la red con `MockEngine` (todas las
  peticiones resueltas por el motor falso); el único test real es opt-in.

## Alcance y arquitectura

- Solo paquete `ingesta/publicacion/` + tests espejo + fixtures +
  `docs/desarrollo-local.md`. `Application.kt`, Flyway/BD, `:shared`,
  `:composeApp`, raíz del build, `libs.versions.toml` y CI **intactos**.
- Modelos internos sin sufijo `Dto` (precedente `EntradaSumario`); dominio puro
  sin Ktor (`BoeXmlParser`/`PublicacionParser`); cliente con `HttpClient`
  inyectado y excepción tipada (patrón FT00006). Sin wiring.
- `categoria = null` documentado (diferida a FT00012).
- Estilo MUST: sin `else if`, sin `return@…`, `return` único por función
  (Detekt `ReturnCount max: 1`), funciones ≪40 líneas, KDoc en todo lo nuevo. No
  hay tipos `@Serializable` nuevos (no aplica `@SerialName`).

## Documentación y harness

- `ARCHITECTURE.md` (paquete `ingesta/publicacion/`, frontera Backend→BOE XML),
  `CONSTRAINTS.md` (§«Fuentes externas (ingesta)»: MUST de parseo seguro + red
  opt-in), `docs/desarrollo-local.md` (endpoint, captura de fixtures, opt-in),
  `PROGRESS.md` (Session 035) y `feature_list.json` (FT00007, 7 evidencias).
- ADR `docs/adr/0002-fuente-texto-boe-xml.md` creado, coherente con la
  implementación e indexado en `docs/adr/README.md`.
- `docs/feature-ids.md`: FT00007 `passing`. `init.sh` sin cambios.
- `feature_list.json` parsea como JSON válido (46 features).

## Seguimiento

Ninguno bloqueante. La aceptación final la persiste el orquestador en
`feature_list.json` (estado `accepted` + evidencia). Deuda Low a arrastrar:
`HttpTimeout` del cliente de texto (FT00009).
