{{- with getSecretByName "PROJECT_ID_PLACEHOLDER" "prod" "/" "HONCHO_API_KEY" }}
honcho.api_key={{ .Value }}
{{- end }}
