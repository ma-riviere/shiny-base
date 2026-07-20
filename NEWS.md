# NEWS

## 2026-07-20

- Error emails now go through the Resend HTTPS API (shinyutils 0.3.0) instead of Brevo SMTP; blastula stays as the HTML formatter. Config: `EMAIL_TO`, `EMAIL_FROM` (any address on the Resend-verified ma-riviere.com domain), `RESEND_API_KEY`, `SEND_ERROR_EMAILS`. The `SMTP_*` variables are gone.
