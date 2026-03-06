# Estrategia de Ecosistema Docker para Static Testing

## 1. Contexto y Objetivos
El objetivo es profesionalizar el flujo de trabajo del proyecto `static_testing` (ModestInventary) mediante un entorno Dockerizado. Dado el contexto educativo, el sistema debe ser agnóstico al framework de pruebas (soportando tanto `unittest` como `pytest`) y garantizar la integridad de los reportes mediante firmas GPG.

## 2. Arquitectura Docker "Dual Core"
Para permitir la rotación entre frameworks sin duplicar mantenimiento, se utilizará una estrategia **Multi-stage Build**:

*   **Imagen Base:** Python 3.x, dependencias comunes (`pylint`, `mypy`, `radon`, `bandit`, `hadolint`, `gnupg`, `git`).
*   **Capa A (Unittest):** Hereda de Base + `coverage.py`. Entrypoint configurado para `unittest`.
*   **Capa B (Pytest):** Hereda de Base + `pytest`, `pytest-cov`. Entrypoint configurado para `pytest`.

**Selección Dinámica:**
El archivo `docker-compose.yml` utilizará una variable de entorno `${TEST_FRAMEWORK}` (definida en un `.env` local) para determinar qué etapa construir y ejecutar.

## 3. Gestión de Identidad y Seguridad (GPG)
Se definen dos contextos de ejecución con estrategias de gestión de claves distintas:

### Contexto A: Desarrollador (Local)
*   **Persistencia:** Las claves GPG residen en el host dentro de `.docker/gnupg/` y se montan en el contenedor (`/home/devuser/.gnupg`).
*   **Inicialización (`init_dev.sh`):**
    1.  Detecta si existen claves en `.docker/gnupg`.
    2.  Si existen: Solicita al usuario el `KEY_ID` para firmar.
    3.  Si no existen: Genera un par de claves interactivamente y guarda el ID.
    4.  Configura permisos y genera el archivo `.env` con `UID`/`GID` del host.
*   **Firma:** Requiere passphrase (interactiva) al momento de hacer commit con el tag `[set]`.

### Contexto B: Runner (CI/Staging)
*   **Identidad:** Cada runner tiene una identidad única ligada a la máquina física.
*   **Inyección de Claves:**
    1.  La clave privada (sin passphrase) se codifica en Base64.
    2.  Se almacena en el archivo `.env` del propio runner (no en el repo).
    3.  Docker recibe la clave vía variable de entorno `GPG_IMPORT_DATA` e importa la identidad al arrancar.
*   **Prioridad:** Se utiliza un modelo de "Pool de Disponibilidad" (Best Effort) confiando en la asignación de GitHub Actions.

## 4. Manejo de Volúmenes y Permisos
*   **Problema:** Archivos generados por Docker (root) en volúmenes montados son ineditables por el host.
*   **Solución:**
    *   `Dockerfile` acepta argumentos `ARG UID` y `ARG GID`.
    *   Crea un usuario `devuser` con esos IDs específicos durante el build.
    *   El script de inicialización captura el ID del usuario actual del host y lo pasa al `.env`.

## 5. Flujo de Trabajo Automatizado
1.  **Pre-commit (Local):** Hook `commit-msg`, ejecuta pylint y mypy con cada commit. Si detecta la etiqueta `[set]`. Levanta Docker, ejecuta linters/tests y firma los reportes independientemente del resultado.
2.  **CI Pipeline (GitHub):** Al hacer merge/PR, el runner local ejecuta validaciones, pruebas de integración y firma los artefactos usando su identidad inyectada.

---

## Prompt de Seguimiento (Continuidad)

*Copia y pega el siguiente bloque en un nuevo chat para retomar el desarrollo exactamente donde se quedó, con todo el contexto técnico necesario.*

```text
ACTÚA COMO: Ingeniero DevOps y Experto en Python/Docker.

CONTEXTO DEL PROYECTO:
Estamos implementando un entorno de desarrollo Dockerizado para "ModestInventary".
El objetivo es crear los archivos de configuración para una arquitectura ya definida y validada.

ESTRATEGIA TÉCNICA DEFINIDA (NO CAMBIAR):
1. DOCKERFILE (Multi-stage):
   - Base: Instala gnupg, git, hadolint, pylint, mypy, radon, bandit.
   - Stage 'unittest': Agrega coverage.
   - Stage 'pytest': Agrega pytest, pytest-cov.
   - Usuario: Debe crear un usuario no-root ('devuser') usando ARG UID y ARG GID pasados desde el build.

2. DOCKER COMPOSE:
   - Servicio 'app': Monta el código actual (.:/app).
   - Volumen GPG: Monta ./.docker/gnupg:/home/devuser/.gnupg (para persistencia de claves dev).
   - Variables: Lee TEST_FRAMEWORK, UID, GID desde un archivo .env.

3. GESTIÓN GPG (Dual Strategy):
   - DEV: Script 'scripts/init_dev.sh' debe detectar si .docker/gnupg ya tiene claves. Si sí, pide ID. Si no, genera interactivamente. Guarda UID/GID en .env.
   - RUNNER: Script 'scripts/init_runner.sh' genera clave sin password y exporta la privada en Base64 para ser usada en el .env del runner de GitHub.
   - INYECCIÓN: El contenedor debe aceptar una variable de entorno opcional GPG_IMPORT_DATA (base64) para importar claves al vuelo (caso Runner).

4. HOOKS:
   - 'hooks/commit-msg': Detecta string "[set]", levanta docker-compose, corre linters+tests, y si pasa, firma reportes pidiendo passphrase al usuario.

TAREA ACTUAL:
Genera el código para los siguientes archivos basándote estrictamente en la estrategia anterior:
1. `Dockerfile`
2. `docker-compose.yml`
3. `scripts/init_dev.sh` (Bash, robusto, detección de claves existentes).
4. `scripts/init_runner.sh` (Bash, exportación base64).

NOTA: Asegura que el Dockerfile maneje correctamente la creación del usuario dinámico para evitar problemas de permisos en los volúmenes montados.
```