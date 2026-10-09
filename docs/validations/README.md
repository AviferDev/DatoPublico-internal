# Validaciones de feature

Un fichero opcional por feature: `docs/validations/<feature-id>.md`.

- Los produce el rol `validator` o el orquestador tras un veredicto `accept`,
  `revise` o `block`.
- Registran: veredicto, checks reejecutados y su resultado, hallazgos por
  severidad, *repair brief* si aplica y evaluación de documentación/harness.
- Si el validador solo reporta en el chat, el orquestador pide confirmación antes
  de persistir el registro, salvo que el usuario lo haya pedido.

La aceptación final se persiste en `feature_list.json` (estado `accepted` +
evidencia) y, cuando aporta, en un fichero de esta carpeta.
