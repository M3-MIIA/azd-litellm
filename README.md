# azd-litellm ![Awesome Badge](https://awesome.re/badge-flat2.svg)

An `azd` template to deploy [LiteLLM](https://www.litellm.ai/) running in Azure Container Apps using an Azure PostgreSQL database.

To use this template, follow these steps using the [Azure Developer CLI](https://learn.microsoft.com/azure/developer/azure-developer-cli/overview):

1. Log in to Azure Developer CLI. This is only required once per-install.

    ```bash
    azd auth login
    ```

2. Initialize this template using `azd init`:

    ```bash
    azd init --template build5nines/azd-litellm
    ```

3. Configure your existing PostgreSQL database connection. Set the following environment variables with your database credentials:

    ```bash
    azd env set DATABASE_HOST "your-postgres-host.example.com"
    azd env set DATABASE_PORT "5432"
    azd env set DATABASE_NAME "litellmdb"
    azd env set DATABASE_USER "your-database-user"
    azd env set DATABASE_PASSWORD "your-secure-password"
    ```

    **Important notes:**
    - Replace the values above with your actual PostgreSQL connection details
    - This template uses an **existing PostgreSQL database** - it will not create a new database server
    - Make sure your PostgreSQL server allows connections from Azure services
    - LiteLLM will automatically initialize the required tables on first run
    - The database port defaults to `5432` if not specified

4. Use `azd up` to provision your Azure infrastructure and deploy the web application to Azure.

    ```bash
    azd up
    ```

5. `azd up` will prompt you to enter these additional secret and password parameters used to configure LiteLLM:

    - `litellm_master_key`: The LiteLLM Master Key. This is the LiteLLM proxy admin key.
    - `litellm_salt_key`: The LiteLLM Salt Key. This cannot be changed once set, and is used to encrypt model keys in the database.

    Be sure to save these secrets and passwords to keep them safe.

6. Once the template has finished provisioning all resources, and Azure Container Apps has completed deploying the LiteLLM container _(this can take a minute or so after `azd up` completes to finish)_, you can access both the Swagger UI and Admin UI for LiteLLM.

    This can be done by navigating to the `litellm` service **Endpoint** returned from the `azd` deployment step using your web browser. _You can also find this endpoint by navigating to the **Container App** within the **Azure Portal** then locating the **Application Url**._

    ![Screenshot of terminal with azd up completed](/assets/screenshot-azd-up-completed.png)

    Navigating to the Endpoint URL will access Swagger UI:

    ![Screenshot of LiteLLM Swagger UI](/assets/screenshot-litellm-swagger-ui.png)

    Navigating to `/ui` on the Endpoint URL will access the LiteLLM Admin UI where Models and other things can be configured:

    ![Screenshot of LiteLLM Admin UI](/assets/screenshot-litellm-admin-ui.png)

## Architecture Diagram

![Diagram of Azure Resources provisioned with this template](assets/architecture.png)

In addition to deploying Azure Resources to host LiteLLM, this template includes a `DOCKERFILE` that builds a LiteLLM docker container that builds the LiteLLM proxy server with Admin UI using Python from the `litellm` pip package.

## Azure Resources

These are the Azure resources that are deployed with this template:

- **Container Apps Environment** - The environment for hosting the Container App
- **Container App** - The hosting for the [LiteLLM](https://www.litellm.ai) Docker Container
- **Log Analytics** and **Application Insights** - Logging for the Container Apps Environment
- **Container Registry** - Used to deploy the custom Docker container for LiteLLM

**Note:** This template is configured to use an **existing PostgreSQL database** that you provide. It does not provision a new PostgreSQL server in Azure.

## Custom LiteLLM Branch

**Note:** This template has been modified to use a custom LiteLLM branch instead of the official PyPI package.

The Docker build process clones and installs LiteLLM from:
- **Repository:** https://github.com/AriOliv/litellm
- **Branch:** `premium-side`

The DOCKERFILE uses a multi-stage build approach:
1. **Builder stage:** Clones the custom branch from GitHub
2. **Runtime stage:** Installs LiteLLM from the cloned source

### Updating the Custom Branch

When the `premium-side` branch is updated with new changes, you'll need to rebuild and redeploy:

```bash
azd deploy litellm
```

This will:
- Clone the latest code from the `premium-side` branch
- Build a new container image
- Deploy to Azure Container Apps

### Switching Back to Official PyPI Version

To revert to the official LiteLLM package:

1. Edit `/src/litellm/DOCKERFILE` to remove the builder stage
2. Add `litellm[proxy]` back to `/src/litellm/requirements.txt`
3. Redeploy with `azd deploy litellm`

### Using a Different Branch or Repository

To use a different branch or fork, edit line 8 of `/src/litellm/DOCKERFILE`:

```dockerfile
RUN git clone --branch YOUR_BRANCH --depth 1 https://github.com/YOUR_USERNAME/litellm.git
```

## Author

This `azd` template was written by [Chris Pietschmann](https://pietschsoft.com), founder of [Build5Nines](https://build5nines.com), Microsoft MVP, HashiCorp Ambassador, and Microsoft Certified Trainer (MCT).
