{{/* Nombre base del chart */}}
{{- define "notes.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/* Nombre completo del release */}}
{{- define "notes.fullname" -}}
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

{{/* Etiquetas comunes a todos los recursos */}}
{{- define "notes.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" }}
app.kubernetes.io/name: {{ include "notes.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: notes
{{- with .Values.commonLabels }}
{{ toYaml . }}
{{- end }}
{{- end -}}

{{/* Etiquetas de seleccion para un componente: include "notes.selectorLabels" (dict "root" . "component" "backend") */}}
{{- define "notes.selectorLabels" -}}
app.kubernetes.io/name: {{ include "notes.name" .root }}
app.kubernetes.io/instance: {{ .root.Release.Name }}
app.kubernetes.io/component: {{ .component }}
{{- end -}}

{{/* Nombre de un componente: <fullname>-<componente> */}}
{{- define "notes.componentName" -}}
{{- printf "%s-%s" (include "notes.fullname" .root) .component | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/* Referencia completa de imagen: [registry/]repository:tag */}}
{{- define "notes.image" -}}
{{- $tag := .image.tag | default .root.Chart.AppVersion -}}
{{- if .root.Values.image.registry -}}
{{- printf "%s/%s:%s" .root.Values.image.registry .image.repository $tag -}}
{{- else -}}
{{- printf "%s:%s" .image.repository $tag -}}
{{- end -}}
{{- end -}}

{{/* Tag de imagen resuelto (para la variable APP_VERSION) */}}
{{- define "notes.imageTag" -}}
{{- .image.tag | default .root.Chart.AppVersion -}}
{{- end -}}
