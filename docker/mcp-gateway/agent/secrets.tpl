{{- with getSecretByName "PROJECT_ID_PLACEHOLDER" "prod" "/" "HONCHO_API_KEY" }}
honcho.api_key={{ .Value }}
{{- end }}
{{- with getSecretByName "PROJECT_ID_PLACEHOLDER" "prod" "/" "AI_MEMORY_AUTH_TOKEN" }}
ai-memory.token={{ .Value }}
{{- end }}
