# Validación — `dist-web` (FT00039)

## FT00039-PT1 — Build Web (Wasm) de producción + SEO del shell

- **Rama**: `feat/ft00039-pt1-web-prod-build` (PR #46) · fusionada en `main` como
  `017af0c` (5 ficheros).
- **Spec**: `docs/specs/dist-web.md` (solo el alcance de PT1).
- **Validador**: `feature-validator` (independiente del implementador).
- **Fecha**: 2026-10-18.

### Veredicto

**`accept`** (PT1). PT2 («enlaces compartibles») queda fuera de esta validación.

| Ronda | Veredicto | Motivo |
| --- | --- | --- |
| 1 | **`accept`** | Mecanismo de URL por build verificado extremo a extremo; SEO del shell correcto; solo hallazgos Low y uno de *bookkeeping* del harness. |

### Checks reejecutados

| Check | Resultado |
| --- | --- |
| `./init.sh --with-client` | **Gate OK (exit 0)**; `./gradlew build` BUILD SUCCESSFUL (212 tareas); detekt + `:cpdCheck` OK (`wasmJsBrowserTest` SKIPPED por diseño, preexistente) |
| `:composeApp:wasmJsBrowserDistribution -PapiBaseUrl="https://api.example.test///"` (tras borrar `build/generated/apiConfig`) | BUILD SUCCESSFUL (1m40s); constante generada = `internal const val API_BASE_URL: String = "https://api.example.test"` → el enlace `srcDir(TaskProvider)` funciona y **recorta barras finales** |
| Reejecución idéntica | `generateApiBaseUrlConfig` y `wasmJsBrowserDistribution` → `UP-TO-DATE` |
| URL inyectada en el wasm | presente `https://api.example.test` ×1 (UTF-16LE); `http://localhost:8080` ×0 |
| Sin la propiedad | constante y wasm = `http://localhost:8080` (dev intacto) |
| `-PapiBaseUrl=""` y `-PapiBaseUrl="   "` | exit 1, `FAILURE … «La propiedad 'apiBaseUrl' está vacía…»` (fail-fast también con espacios) |
| Servido estático (`python3 -m http.server` sobre `productionExecutable/`) | `/` **200 `text/html`** (con metadatos), `/composeApp.js` **200 `text/javascript`**, `/*.wasm` **200 `application/wasm`**, `/favicon.svg` **200 `image/svg+xml`**; `/norma/<id>` → 404 en servidor pelado (**esperado**: el *fallback* SPA es FT00052-PT2) |
| SEO del `index.html` distribuido | `lang="es"`, `title`, `description`, `robots=index,follow`, `canonical`, `theme-color`, `link icon`, `og:type/site_name/locale/title/description/url/image`; sin secretos |
| Evidencia registrada vs realidad | PR #46 `MERGED` (`mergeCommit=017af0c…`, 5 ficheros); CI run `38792955614` job «Build and test» `success` (`headSha=f284178`) |
| Android/iOS/JVM | Intactos (el diff son 5 ficheros; `git diff 017af0c..HEAD` sobre las rutas de PT1 = vacío) |

**No verificable en este entorno**: el arranque real en navegador (no hay
Chrome/Chromium y `wasmJsBrowserTest` está deshabilitado en el gate). La limitación
está documentada en el spec (§Verification Plan C/D), `feature_list.json` y
`PROGRESS.md` (Session 086): **aceptable**, con verificación manual pendiente del
dueño.

### Hallazgos

#### M1 — Estado del harness incoherente (Medium; no es defecto de la implementación)

La parte figuraba `accepted` en `feature_list.json` **sin validación registrada** y
con las fuentes en contradicción: su propia evidencia decía «pendiente de validación
independiente» y `docs/feature-ids.md` decía `passing`. El cambio lo introdujo el
commit `1be16da` (bookkeeping de FT00047), que pasó `passing → accepted` a 9
entradas de golpe, entre ellas `FT00039-PT1` y `FT00053`. **Resuelto en este
cierre**: validación registrada (este fichero), evidencia corregida y
`docs/feature-ids.md` alineado.

#### L1 — El literal Kotlin no escapa `"`, `\` ni `$` (Low)

`-PapiBaseUrl='https://x.test/a"b'` genera `… = "https://x.test/a"b"` y la
compilación Wasm falla con errores confusos. Es entrada del operador en *build
time* (no hay superficie de atacante en runtime; `const val` impide plantillas
evaluables). **Recomendado** (no bloquea): escapar el valor o validarlo con una
regex de URL y fallar con mensaje claro.

#### L2 — `og:image` apunta a un fichero inexistente (Low)

`index.html` → `https://datopublico.example/og-image.png`, que no existe en el
artefacto. Amparado por el MUST (dominio *placeholder* hasta FT00052-PT2), pero
conviene que PT2 publique `og-image.png` o retire la etiqueta.

#### L3 — Deriva de tokens de diseño (Low, atribuible a FT00053)

`theme-color` y `favicon.svg` usan `#1A4D8F` (el `primary` del §Colors de
`DESIGN.md`), mientras la paleta M3 posterior de FT00053 fija `primary: #00366F`.
No es defecto de PT1 (se fusionó antes). A reconciliar en FT00052-PT2, que cierra
los metadatos definitivos.

#### L4 — Limpieza de árbol (Low)

`docs/pantallas-frontend.md` queda sin seguimiento en el repo de producto (ajeno a
PT1). Versionar o borrar antes del cierre de sesión.

### Notas informativas

- El artefacto incluye `composeApp.js.map` (1,4 MB) y `composeApp.js.LICENSE.txt`;
  si FT00052-PT2 hace `rsync` del directorio completo, publicará los *source maps*
  (impacto bajo: el proyecto es de código abierto).
- El hash de wasm citado en la evidencia (`dcf15720…`) ya no corresponde al
  artefacto actual (regenerado por features posteriores): esperable, no invalida nada.
- `docs/release.md` no se toca (correcto según spec); no hay capturas en
  `docs/pr/ft00039-dist-web/` porque PT1 no cambia píxeles.

### Seguridad

Sin hallazgos bloqueantes. No hay secretos (solo el *placeholder*
`datopublico.example`, idéntico al de `deploy/.env.production.example`); sin
autenticación/roles; la única entrada es la propiedad Gradle del operador en build
time (L1 es robustez, no RCE); sin datos personales en metadatos ni artefacto; sin
dependencias ni llamadas salientes nuevas. La URL de API queda compilada dentro del
wasm público, que es el comportamiento buscado (CONSTRAINTS exige que **no** se
hardcodee una URL de producción en el código).

### Estado

- **FT00039-PT1 → `accepted`** (persistido en `feature_list.json` y
  `docs/feature-ids.md`).
- `dist-web` sigue **`in_progress`**: **PT2** (puente de URL Web / History API para
  enlaces compartibles + ADR) pendiente.
- Sin ADR en PT1 (el spec reserva el ADR para PT2); la decisión durable queda en
  `ARCHITECTURE.md` (§Despliegue → «Web (Wasm): build y servido») y `CONSTRAINTS.md`.
