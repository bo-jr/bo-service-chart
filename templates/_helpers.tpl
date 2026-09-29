{{/*
Labels on every object and pod. `app` is the stable identity (and the only
selector key); `version` is APP_VERSION, so Kiali, kubectl and Prometheus all
name the same thing when two versions run side by side.
*/}}
{{- define "service.labels" -}}
app: {{ .Values.name }}
version: {{ .Values.version }}
app.kubernetes.io/name: {{ .Values.name }}
app.kubernetes.io/version: {{ .Values.version }}
app.kubernetes.io/part-of: gitops-lab
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
{{- end }}

{{/*
A service pins this chart by exact version in its chart-values.yaml. Rendering
those values with any other chart version is refused rather than silently
producing manifests nobody reviewed.
*/}}
{{- define "service.pinGuard" -}}
{{- if ne (toString .Values.chartVersion) .Chart.Version -}}
{{- fail (printf "chart-values.yaml pins chartVersion %q but this is chart %s; re-pin deliberately" (toString .Values.chartVersion) .Chart.Version) -}}
{{- end -}}
{{- end }}
