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

## How to use Specific Version of LiteLLM

By default, this project uses the latest version of LiteLLM. There may be reasons you want to run a specific version of LiteLLM. This project deploys LiteLLM using its Python package, and you can update the version referenced to target a specific version of LiteLLM if necessary.

To do so, you can edit the [`/src/litellm/requirements.txt`](/src/litellm/requirements.txt) file. This file is the Python `pip` requirements file that specifies the PIP packages and their versions to use. The `litellm[proxy]` package is the package that is LiteLLM. You can find the available release versions on the [`litellm` PIP package page.](https://pypi.org/project/litellm/)

Here's an example of the `requirements.txt` file reference of `litellm` package specifying the v1.65.1 release:

```text
litellm[proxy]==1.65.1
```

By default, this project does not specify a version; which tells PIP to pull down the latest release. I hope this helps if you find yourself needing to run a specific version of LiteLLM.

## Author

This `azd` template was written by [Chris Pietschmann](https://pietschsoft.com), founder of [Build5Nines](https://build5nines.com), Microsoft MVP, HashiCorp Ambassador, and Microsoft Certified Trainer (MCT).
