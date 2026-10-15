# FT00053 — Alineación visual de las 4 pantallas con el diseño

- **Feature**: `ui-design-refresh`
- **Área**: `cliente-cmp`
- **Depende de**: `ui-feed` (FT00032), `ui-detalle` (FT00033),
  `ui-busqueda-filtros` (FT00036), `ui-chat` (FT00037)
- **Estado**: `passing` (implementada y autoverificada; validación independiente
  pendiente)

## Objetivo

Alinear las **cuatro pantallas existentes** del cliente Compose Multiplatform
(feed, búsqueda, detalle y chat RAG) con los mockups de
`.harness/docs/desing/` (carpetas `datopublico_feed_diario`,
`datopublico_b_squeda_en_el_boe`, `datopublico_detalle_de_publicaci_n` y
`datopublico_preguntar_al_boe_chat_rag`) y con los tokens Material 3 de
`.harness/docs/desing/datopublico/DESIGN.md`.

## Alcance

- **Tokens del tema** (`design/theme/DatoPublicoTheme.kt`): paleta Material 3 del
  mockup (primario `#00366F`, secundario `#006A63`, terciario `#4F3000` con
  contenedores pastel, superficies `#F9F9FF`/`#FFFFFF`, contornos `#737782`), con
  tipografía y formas del diseño. Es el **único** lugar con literales de color.
- **Componentes compartidos** (`design/components/`): `CategoryLabel`,
  `PublicationBadges`, `PublicationCard` (+ enlace a la fuente), `AiNotice`
  (título opcional), `SectionBlock` (barra de acento), `OfficialSourceLink`
  (botón principal) y `OfficialSourceUrl` (URL + copiar).
- **Chasis** (`app/AppChrome.kt`, nuevo): barra superior común (marca +
  «Preguntar al BOE» + buscar), barra superior de atrás en el detalle y barra
  inferior de navegación (Boletín / Búsqueda / RAG Chat).
- **Pantallas**:
  - Feed: tira de estado, bloque de destacados, publicaciones y tarjeta de ayuda
    al chat.
  - Búsqueda: sub-cabecera, panel de filtros (consulta, categorías, fechas,
    acciones), tira de resultados y tarjeta de garantía.
  - Detalle: sub-barra de contenido, tarjeta de cabecera, bloque de plazo,
    bloques del resumen, aviso de IA y fuente oficial (+ URL).
  - Chat: sub-cabecera con «RAG Activo», campo de pregunta (contador + limpiar +
    enviar), burbuja de consulta, tarjeta de respuesta, citas, aviso de IA,
    privacidad y consultas sugeridas.
- **Textos i18n** (`composeResources/values/strings.xml`): todas las cadenas
  nuevas.

## Fuera de alcance (Non-Goals)

- **Backend, dominio y contrato de datos**: intactos. Solo se ha tocado la capa
  UI + textos.
- **Datos que no existen en el dominio**: no se pintan organismo emisor, imagen
  institucional, «quedan N días», cifras clave del chat ni marca/logo, porque no
  están en el modelo del cliente y no se inventan.
- **Acciones sin respaldo**: no se añaden controles muertos (favoritos,
  guardar alerta, compartir, pulgares de feedback, menú «Filtros» del feed,
  avatar de cuenta), por coherencia con «sin cuentas ni datos personales».
- **Fuente Inter**: no se empaqueta la tipografía (se mantiene la del sistema);
  se respetan tamaños, pesos y espaciado del diseño.

## Enfoque

1. **Base compartida** (secuencial): tema, componentes, chasis, navegación y
   `strings.xml`, congelados antes de repartir.
2. **Cuatro pantallas en paralelo**: cada tarea posee en exclusiva los ficheros
   de su feature (`feed/ui`, `search/ui`, `detail/ui`, `chat/ui`), sin tocar la
   base congelada ni otras pantallas.
3. **Verificación central**: compilación del cliente (Wasm), tests y detekt.

## Ficheros

- `composeApp/src/commonMain/kotlin/es/aviferdev/datopublico/design/theme/DatoPublicoTheme.kt`
- `composeApp/src/commonMain/kotlin/es/aviferdev/datopublico/design/components/*.kt`
- `composeApp/src/commonMain/kotlin/es/aviferdev/datopublico/app/AppChrome.kt` (nuevo)
- `composeApp/src/commonMain/kotlin/es/aviferdev/datopublico/app/AppNavHost.kt`
- `composeApp/src/commonMain/kotlin/es/aviferdev/datopublico/feature/{feed,search,detail,chat}/ui/*.kt`
- `composeApp/src/commonMain/composeResources/values/strings.xml`

## Criterios de verificación

- Las 4 pantallas y el chasis compilan para los targets del cliente.
- `:composeApp:jvmTest` y `:composeApp:detekt` (+ `:cpdCheck`) en verde.
- `init.sh --with-client` en verde.
- Capturas antes/después o justificación (ver `docs/pr/`).

## Riesgos

- El entorno de captura es **headless**: no se pudieron tomar capturas (se
  justifica en `docs/pr/feat-ft00053-ui-design-refresh/README.md`).
- El set `material-icons-core` no incluye los iconos extendidos del mockup
  (`newspaper`, `smart_toy`, `tune`…): se aproximan con iconos core.
