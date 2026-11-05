# Política de seguridad del equipo

## Reglas obligatorias
1. **Nunca** subir secretos: `.env`, llaves privadas, contraseñas, tokens. (GitHub Push Protection y Gitleaks lo vigilan.)
2. **Solo datos de prueba.** Prohibido usar tarjetas, cuentas o datos personales reales.
3. **Nunca** guardar CVV. El número de tarjeta (PAN) solo se almacena cifrado (AES-256-GCM); fuera de la Wallet circula el *token*.
4. **No registrar** (logs, consola, bitácora) contraseñas, PAN, tokens ni llaves.
5. Contraseñas con **Argon2id**; nada de MD5/SHA simple para contraseñas.
6. Toda consulta SQL va parametrizada (usar SQLAlchemy). Toda entrada se valida con Pydantic.
7. Cambios en `backend/shared/` y `mobile/lib/core/` requieren revisión del arquitecto de seguridad.
8. Dependencias nuevas: revisar que estén mantenidas y sin vulnerabilidades conocidas.

## Reportar un problema
Abre un Issue con la etiqueta `security` (repositorio privado) o avisa directamente al arquitecto de seguridad. Si un secreto se subió por error, **rótalo de inmediato** (cambiar el valor), no basta con borrar el commit.
