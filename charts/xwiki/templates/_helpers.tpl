{{/* vim: set filetype=mustache: */}}
{{/*
Expand the name of the chart.
*/}}
{{- define "xwiki.name" -}}
{{- include "common.names.name" . }}
{{- end -}}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
*/}}
{{- define "xwiki.fullname" -}}
{{- include "common.names.fullname" . }}
{{- end }}

{{- define "solr.fullname" -}}
{{- printf "%s-solr" (include "common.names.fullname" .) }}
{{- end }}

{{/*
Solr Common labels
*/}}
{{- define "solr.labels" -}}
run: solr
{{- end }}

{{/*
Selector labels
*/}}
{{- define "solr.selectorLabels" -}}
run: solr
{{- end }}

{{/*
Common labels
*/}}
{{- define "xwiki.labels" -}}
{{- include "common.labels.standard" . }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "xwiki.selectorLabels" -}}
{{- include "common.labels.matchLabels" . }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "xwiki.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "xwiki.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Create the name of init scripts configmap 
*/}}
{{- define "xwiki.initScripts" -}}
{{- printf "%s-init-scripts" (include "xwiki.fullname" .) }}
{{- end }}

{{/*
Istio cert name to be used
*/}}
{{- define "xwiki.istio.credentialName" -}}
{{- $secretName := .Values.istio.tls.secretName }}
{{- if $secretName }}
{{- printf "%s" (tpl $secretName $) -}}
{{- else }}
    {{- printf "%s-istio-cert" (include "xwiki.fullname" .) -}}
{{- end }}
{{- end }}

{{/*
Istio gateway name to be used
*/}}
{{- define "xwiki.istio.gatewayName" -}}
{{- $gatewayName := .Values.istio.externalGatewayName }}
{{- if $gatewayName }}
{{- printf "%s" (tpl $gatewayName $) -}}}
{{- else }}
{{- printf "%s-gateway" (include "xwiki.fullname" .) }}
{{- end }}
{{- end }}

{{/*
Define which image to use
*/}}
{{- define "xwiki.imageName" -}}
{{- if .Values.image.tag }}
{{- printf "%s:%s" .Values.image.name .Values.image.tag -}}
{{- else if .Values.mysql.enabled }}
{{- printf "%s:lts-mysql-tomcat" .Values.image.name -}}
{{- else if .Values.postgresql.enabled }}
{{- printf "%s:lts-postgres-tomcat" .Values.image.name -}}
{{- else }}
{{- .Values.image.name -}}
{{- end }}
{{- end }}


{{/*
Database env vars
*/}}
{{- define "xwiki.database.env" }}
- name: DB_PASSWORD
  valueFrom:
    secretKeyRef:
    {{- if and .Values.externalDB.customKeyRef .Values.externalDB.customKeyRef.enabled }}
      name: {{ .Values.externalDB.customKeyRef.name | quote }}
      key:  {{ .Values.externalDB.customKeyRef.key  | quote }}
    {{- else if .Values.mysql.enabled }}
      name: "{{ .Release.Name }}-mysql"
      key: mysql-password
    {{- else if .Values.postgresql.enabled }}
      name: "{{ .Release.Name }}-postgresql"
      key: password
    {{- else }}
      name: {{ .Release.Name | quote }}
      key: DB_PASSWORD
    {{- end }}
- name: DB_HOST
  valueFrom:
    configMapKeyRef:
      name: {{ include "xwiki.fullname" . }}
      key: DB_HOST
- name: DB_USER
  valueFrom:
    configMapKeyRef:
      name: {{ include "xwiki.fullname" . }}
      key: DB_USER
- name: DB_DATABASE
  valueFrom:
    configMapKeyRef:
      name: {{ include "xwiki.fullname" . }}
      key: DB_DATABASE
{{- end }}

{{/*
Image for the database init container
*/}}
{{- define "xwiki.initContainer.database.image" -}}
  {{- if .Values.initContainers.database.image }}
{{ .Values.initContainers.database.image }}
  {{- else if .Values.mysql.enabled }}
{{ printf "%s:%s" .Values.mysql.image.repository .Values.mysql.image.tag }}
  {{- else if .Values.postgresql.enabled }}
{{ printf "%s:%s" .Values.postgresql.image.repository .Values.postgresql.image.tag }}
  {{- else if .Values.mariadb.enabled }}
{{ printf "%s:%s" .Values.mariadb.image.repository .Values.mariadb.image.tag }}
  {{- end }}
{{- end }}

{{/*
Command for the database init container
*/}}
{{- define "xwiki.initContainer.database.command" -}}
  {{- if .Values.initContainers.database.command }}
{{ .Values.initContainers.database.command }}
  {{- else if or .Values.mysql.enabled .Values.mariadb.enabled (eq .Values.externalDB.type "mysql") (eq .Values.externalDB.type "mariadb") }}
mysqladmin ping -h $DB_HOST -u $DB_USER -p$DB_PASSWORD
  {{- else if or .Values.postgresql.enabled (eq .Values.externalDB.type "postgresql") }}
PGPASSWORD=$DB_PASSWORD pg_isready -h $DB_HOST -U $DB_USER -d $DB_DATABASE
  {{- end }}
{{- end }}

{{/*
Init Containers
*/}}
{{- define "xwiki.initContainers" -}}
  {{- if and .Values.volumePermissions.enabled .Values.persistence.enabled }}
- name: xwiki-data-permissions
  image: {{ include "xwiki.imageName" . }}
  imagePullPolicy: {{ .Values.image.pullPolicy }}
  command:
    - /bin/sh
    - -ec
    - chown -R "{{ .Values.containerSecurityContext.runAsUser }}:{{ .Values.securityContext.fsGroup }}" /usr/local/xwiki/data
  securityContext: {{- omit .Values.volumePermissions.containerSecurityContext "enabled" | toYaml | nindent 12 }}
  volumeMounts:
    - name: xwiki-data
      mountPath: /usr/local/xwiki/data
  {{- end }}
  {{- if .Values.initContainers.database.enabled }}
- name: wait-for-db
  {{- if .Values.initContainers.database.containerSecurityContext.enabled }}
  securityContext:
    {{- omit .Values.initContainers.database.containerSecurityContext "enabled" | toYaml | nindent 6 }}
  {{- end }}
  env:
    {{- include "xwiki.database.env" . | nindent 4 }}
    - name: CHECK_DB
      value: {{ include "xwiki.initContainer.database.command" . | trim | quote }}
  image: {{ include "xwiki.initContainer.database.image" . | trim | quote }}
  command:
    - /bin/sh
    - -ec
  args:
    - |
      for i in $(seq 1 30); do
        if eval $CHECK_DB; then
          echo "Database is ready!"
          exit 0
        fi
        echo "Waiting for database..."
        sleep 1
      done
      echo "Database is not ready!"
      exit 1
  {{- end }}
  {{- if .Values.initContainers.solr.enabled }}
- name: wait-for-solr
  image: "alpine/curl:8.9.0"
  command:
    - /bin/sh
    - -ec
    - |
      for i in $(seq 1 30); do
        if curl --silent --connect-timeout "15000" $SOLR_BASEURL/admin/info/system | grep '\"status\":0'
          echo "Solr is ready!"
          exit 0
        fi
        echo "Waiting for Solr..."
        sleep 1
      done
      echo "Solr is not ready!"
      exit 1
  {{- if .Values.initContainers.solr.containerSecurityContext.enabled }}
  securityContext:
    {{- omit .Values.initContainers.solr.containerSecurityContext "enabled" | toYaml | nindent 6 }}
  {{- end }}
  env:
    - name: SOLR_BASEURL
      valueFrom:
        configMapKeyRef:
          name: {{ include "xwiki.fullname" . }}
          key: SOLR_BASEURL
  {{- end }}
{{- end }}
