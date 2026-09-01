{{/*
Helpers reutilizables. Nada de esto se renderiza como manifiesto:
se invoca con  {{ include "mini-app.xxx" . }}  desde los otros templates.
*/}}

{{/* Nombre corto del chart (override posible con nameOverride). */}}
{{- define "mini-app.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Nombre completo de los recursos.
- Si el release ya contiene el nombre del chart (ej. release "mini-app"), se usa
  solo el release name -> recursos "mini-app".
- Si no, se antepone el release -> recursos "<release>-mini-app".
- 63 chars es el límite de nombres en Kubernetes.
*/}}
{{- define "mini-app.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $name := default .Chart.Name .Values.nameOverride -}}
{{- if contains $name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/* Nombre del StatefulSet/Service de Redis: "<fullname>-redis". */}}
{{- define "mini-app.redis.fullname" -}}
{{- printf "%s-redis" (include "mini-app.fullname" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/* Labels comunes a todos los recursos (convención app.kubernetes.io/*). */}}
{{- define "mini-app.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{ include "mini-app.selectorLabels" . }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{/* Subconjunto estable de labels usado en selectors (no debe cambiar nunca). */}}
{{- define "mini-app.selectorLabels" -}}
app.kubernetes.io/name: {{ include "mini-app.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{/* Nombre del Secret que guarda la password de Redis. */}}
{{- define "mini-app.redis.secretName" -}}
{{- printf "%s-redis" (include "mini-app.fullname" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}
