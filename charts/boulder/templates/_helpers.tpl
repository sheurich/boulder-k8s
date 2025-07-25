{{/*
Expand the name of the chart.
*/}}
{{- define "boulder.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "boulder.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "boulder.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "boulder.labels" -}}
helm.sh/chart: {{ include "boulder.chart" . }}
{{ include "boulder.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "boulder.selectorLabels" -}}
app.kubernetes.io/name: {{ include "boulder.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "boulder.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "boulder.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Boulder network configuration
*/}}
{{- define "boulder.bouldernet.cidr" -}}
{{- .Values.networkPolicies.bouldernet.cidr | default "10.77.77.0/24" }}
{{- end }}

{{- define "boulder.publicnet.cidr" -}}
{{- .Values.networkPolicies.publicnet.cidr | default "64.112.117.0/25" }}
{{- end }}

{{- define "boulder.publicnet2.cidr" -}}
{{- .Values.networkPolicies.publicnet2.cidr | default "64.112.117.128/25" }}
{{- end }}