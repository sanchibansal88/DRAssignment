{{- define "frontend-api.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $name := default .Chart.Name .Values.nameOverride -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{- define "frontend-api.labels" -}}
helm.sh/chart: {{ include "frontend-api.chart" . }}
app.kubernetes.io/name: {{ include "frontend-api.fullname" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{- define "frontend-api.selectorLabels" -}}
app.kubernetes.io/name: {{ include "frontend-api.fullname" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "frontend-api.chart" -}}
{{ printf "%s-%s" .Chart.Name .Chart.Version }}
{{- end -}}
