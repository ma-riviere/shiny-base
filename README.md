# Shiny Base

A modular Shiny application template with Auth0 authentication, database integration, and usage analytics.

## Quick Start

```bash
# Install dependencies
renv::restore()

# Configure environment (see .Renviron.example)
cp .Renviron.example .Renviron

# Run the app
shiny::runApp()
```

## Setup Requirements

### Auth0 Configuration

1. **Create Auth0 Application**
   - Go to Auth0 Dashboard → Applications → Create Application
   - Choose "Regular Web Application"
   - Note the Domain, Client ID, and Client Secret

2. **Configure `_auth0.yml`**
```yaml
name: shiny-base
remote_url: !expr Sys.getenv("APP_URL")
auth0_config:
    api_url: !expr paste0("https://", Sys.getenv("AUTH0_USER"), ".eu.auth0.com")
    audience: !expr paste0('https://', Sys.getenv("AUTH0_USER"), '.eu.auth0.com/api/v2/')
    scope: openid profile email
    credentials:
        key: !expr Sys.getenv("AUTH0_CLIENT_ID")
        secret: !expr Sys.getenv("AUTH0_CLIENT_SECRET")
```

3. **Enable RBAC (Role-Based Access Control)**
   
   Auth0 does not include roles in tokens by default. Create an Auth0 Action:
   
   - Go to Auth0 Dashboard → Actions → Triggers
   - Click on "post-login" under "Sign Up & Login"
   - Click "+" to add a new action and create it with this code:
   
   ```javascript
   exports.onExecutePostLogin = async (event, api) => {
     const namespace = 'https://shiny-base.ma-riviere.com/';
     if (event.authorization) {
       api.idToken.setCustomClaim(`${namespace}roles`, event.authorization.roles);
     }
   };
   ```
   
   - Deploy the Action and add it to the Login flow
   
   > **Important**: The namespace must match `auth0_roles_claim` in `global.R`. If you change the namespace in Auth0, update the option accordingly.

4. **Assign Roles to Users**
   - Go to Auth0 Dashboard → User Management → Roles
   - Create an "admin" role
   - Assign the role to users who should have admin access

### Environment Variables

Create a `.Renviron` file in the project root:

```bash
cp .Renviron.example .Renviron
```
