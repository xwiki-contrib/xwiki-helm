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
Define which image to use on XWiki
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
Define which image to use on Solr
*/}}
{{- define "solr.imageName" -}}
{{- $separator := ":" -}}
{{- $selector := .Values.solr.image.tag | toString -}}
{{- if .Values.solr.image.digest }}
    {{- $separator = "@" -}}
    {{- $selector = .Values.solr.image.digest | toString -}}
{{- end -}}
{{- if .Values.solr.image.registry }}
    {{- printf "%s/%s%s%s" .Values.solr.image.registry .Values.solr.image.repository $separator $selector -}}
{{- else -}}
    {{- printf "%s%s%s"  .Values.solr.image.repository $separator $selector -}}
{{- end -}}
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
Application server base path (tomcat or jetty).
*/}}
{{- define "xwiki.asPath" -}}
{{- if eq .Values.initContainers.supportReadonly.as "jetty" -}}
/var/lib/jetty
{{- else -}}
/usr/local/tomcat
{{- end -}}
{{- end -}}

{{/*
WEB-INF base path used for writable config volume mounts.
*/}}
{{- define "xwiki.webInfBasePath" -}}
{{- printf "%s/webapps/%s/WEB-INF" (include "xwiki.asPath" .) .Values.initContainers.supportReadonly.contextPath -}}
{{- end -}}

{{/*
Volume mounts for writable WEB-INF config files copied by the supportReadonly init container.
*/}}
{{- define "xwiki.webInfConfigVolumeMounts" -}}
{{- if .Values.initContainers.supportReadonly.enabled }}
{{- $base := include "xwiki.webInfBasePath" . }}
- name: webinf-configs
  mountPath: {{ $base }}/xwiki.cfg
  subPath: xwiki.cfg
- name: webinf-configs
  mountPath: {{ $base }}/xwiki.properties
  subPath: xwiki.properties
- name: webinf-configs
  mountPath: {{ $base }}/hibernate.cfg.xml
  subPath: hibernate.cfg.xml
- name: webinf-configs
  mountPath: {{ $base }}/web.xml
  subPath: web.xml
- name: webinf-configs
  mountPath: {{ $base }}/classes/logback.xml
  subPath: classes/logback.xml
- name: webinf-configs
  mountPath: {{ $base }}/observation/remote/jgroups
  subPath: observation/remote/jgroups
{{- end }}
{{- end -}}

{{/*
Volume mounts used by the main XWiki container. Reused by extra init
containers so they see the same data/config/entrypoint volumes (including
any user-defined extraVolumeMounts).
*/}}
{{- define "xwiki.volumeMounts" -}}
- name: xwiki-data
  mountPath: /usr/local/xwiki/data
- name: configmaps
  mountPath: /configmaps
{{- if and .Values.propertiesSecret.name .Values.propertiesSecret.key }}
- name: secretproperties
  mountPath: /secretproperties
  readOnly: true
{{- end }}
- name: entrypoint
  mountPath: /entrypoint
  readOnly: true
{{ include "xwiki.webInfConfigVolumeMounts" . }}
{{- with .Values.extraVolumeMounts }}
{{ toYaml . }}
{{- end }}
{{- end -}}

{{/*
Log markers for init container execution start/end.
Use at the beginning of init container shell scripts.
*/}}
{{- define "xwiki.initContainer.execLog" -}}
echo "Starting init container: {{ . }}"
trap 'echo "Finished init container: {{ . }}"' EXIT
{{- end -}}

{{/*
Init Containers for secrets
*/}}
{{- define "xwiki.initContainersSecrets" -}}
{{- $fullName := include "xwiki.fullname" . -}}
- name: xwiki-secrets
  image: {{ include "xwiki.imageName" . }}
  imagePullPolicy: {{ .Values.image.pullPolicy }}
  command: ["/bin/sh", "-c"]
  args:
    - |
        {{ include "xwiki.initContainer.execLog" "xwiki-secrets" | nindent 8 }}
        cp /secrets/entrypoint /entrypoint/start.sh
        chmod 0550 /entrypoint/start.sh
      {{- range $key, $value := .Values.javaOptsSecrets }}
      {{- $keySanitised := regexReplaceAll "\\W+" $key "_" }}
        sed --in-place "s/{{ $keySanitised | upper }}/${ {{- $keySanitised | upper -}} }/g" /entrypoint/start.sh
      {{- end }}
      {{- range $_, $values := .Values.customConfigsSecrets }}
      {{- range $key, $_ := $values }}
      {{- $keySanitised := regexReplaceAll "\\W+" $key "_" }}
        sed --in-place "s/{{ $keySanitised | upper }}/${ {{- $keySanitised | upper -}} }/g" /entrypoint/start.sh
      {{- end }}
      {{- end }}
  securityContext: {{- omit .Values.volumePermissions.containerSecurityContext "enabled" | toYaml | nindent 4 }}
  resources:
    {{- toYaml .Values.resources | nindent 4 }}
  env:
  {{- range $key, $value := .Values.javaOptsSecrets }}
    {{- $keySanitised := regexReplaceAll "\\W+" $key "_" }}
    - name: {{ $keySanitised | upper }}
      valueFrom:
        secretKeyRef:
          {{- if hasKey $value "secret" }}
          {{- if and $value.secret.name $value.secret.key }}
          name: {{ $value.secret.name | default $fullName | quote }}
          key: {{ $value.secret.key | default $keySanitised | quote }}
          {{- else }}
          name: {{ $fullName | quote }}
          key: {{ $keySanitised | quote }}
          {{- end }}
          {{- else }}
          name: {{ $fullName | quote }}
          key: {{ $keySanitised | quote }}
          {{- end }}
  {{- end }}
  {{- range $_, $values := .Values.customConfigsSecrets }}
    {{- range $key, $value := $values }}
      {{- $keySanitised := regexReplaceAll "\\W+" $key "_" }}
    - name: {{ $keySanitised | upper }}
      valueFrom:
        secretKeyRef:
          {{- if hasKey $value "secret" }}
          {{- if and $value.secret.name $value.secret.key }}
          name: {{ $value.secret.name | default $fullName | quote }}
          key: {{ $value.secret.key | default $keySanitised | quote }}
          {{- else }}
          name: {{ $fullName | quote }}
          key: {{ $keySanitised | quote }}
          {{- end }}
          {{- else }}
          name: {{ $fullName | quote }}
          key: {{ $keySanitised | quote }}
          {{- end }}
    {{- end }}
  {{- end }}
  volumeMounts:
    - name: secrets
      mountPath: /secrets
    - name: entrypoint
      mountPath: /entrypoint
{{- end }}

{{/*
Init container that seeds writable WEB-INF config files from the image layer.
*/}}
{{- define "xwiki.initSupportReadonly" -}}
{{- if .Values.initContainers.supportReadonly.enabled }}
- name: xwiki-webinf-configs
  image: {{ include "xwiki.imageName" . }}
  imagePullPolicy: {{ .Values.image.pullPolicy }}
  command: ["/bin/bash", "-ec"]
  args:
    - |
      {{ include "xwiki.initContainer.execLog" "xwiki-webinf-configs" | nindent 6 }}
      WEBINF="{{ include "xwiki.asPath" . | quote }}/webapps/{{ .Values.initContainers.supportReadonly.contextPath }}/WEB-INF"
      DEST="/webinf-configs"

      mkdir -p "${DEST}/classes" "${DEST}/observation/remote/jgroups"

      cp "${WEBINF}/xwiki.cfg"          "${DEST}/xwiki.cfg"
      cp "${WEBINF}/xwiki.properties"   "${DEST}/xwiki.properties"
      cp "${WEBINF}/hibernate.cfg.xml"  "${DEST}/hibernate.cfg.xml"
      cp "${WEBINF}/web.xml"            "${DEST}/web.xml"

      if [ -f "${WEBINF}/classes/logback.xml" ]; then
        cp "${WEBINF}/classes/logback.xml" "${DEST}/classes/logback.xml"
      fi

      if [ -d "${WEBINF}/observation/remote/jgroups" ]; then
        cp -a "${WEBINF}/observation/remote/jgroups/." "${DEST}/observation/remote/jgroups/"
      fi
      echo "Listing all loaded configs from WEB-INF directory"
      ls ${DEST}/*
  {{- if .Values.initContainers.supportReadonly.containerSecurityContext.enabled }}
  securityContext:
    {{- omit .Values.initContainers.supportReadonly.containerSecurityContext "enabled" | toYaml | nindent 4 }}
  {{- else if .Values.volumePermissions.containerSecurityContext.enabled }}
  securityContext: {{- omit .Values.volumePermissions.containerSecurityContext "enabled" | toYaml | nindent 4 }}
  {{- end }}
  {{- if .Values.initContainers.supportReadonly.resources }}
  resources:
    {{- toYaml .Values.initContainers.supportReadonly.resources | nindent 4 }}
  {{- else }}
  resources:
    {{- toYaml .Values.resources | nindent 4 }}
  {{- end }}
  volumeMounts:
    - name: webinf-configs
      mountPath: /webinf-configs
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
  args:
    - |
      {{ include "xwiki.initContainer.execLog" "xwiki-data-permissions" | nindent 6 }}
      chown -R "{{ .Values.containerSecurityContext.runAsUser }}:{{ .Values.securityContext.fsGroup }}" /usr/local/xwiki/data
  securityContext: {{- omit .Values.volumePermissions.containerSecurityContext "enabled" | toYaml | nindent 4 }}
  resources:
    {{- toYaml .Values.resources | nindent 4 }}
  volumeMounts:
    - name: xwiki-data
      mountPath: /usr/local/xwiki/data
  {{- end }}
  {{- if .Values.initContainers.database.enabled }}
- name: wait-for-db
  {{- if .Values.initContainers.database.containerSecurityContext.enabled }}
  securityContext:
    {{- omit .Values.initContainers.database.containerSecurityContext "enabled" | toYaml | nindent 4 }}
  {{- end }}
  resources:
    {{- toYaml .Values.resources | nindent 4 }}
  env:
    {{- include "xwiki.database.env" . | nindent 4 }}
    - name: CHECK_DB
      value: {{ include "xwiki.initContainer.database.command" . | trim | quote }}
    - name: DB_CHECK_RETRIES
      value: {{ .Values.initContainers.database.retries | default 30 | quote }}
    - name: DB_CHECK_INTERVAL
      value: {{ .Values.initContainers.database.retryInterval | default 1 | quote }}
    - name: DB_CHECK_TIMEOUT
      value: {{ .Values.initContainers.database.timeout | default 5 | quote }}
  image: {{ include "xwiki.initContainer.database.image" . | trim | quote }}
  command:
    - /bin/sh
    - -c
  args:
    - |
      echo "Starting init container: wait-for-db"
      for i in $(seq 1 "${DB_CHECK_RETRIES:-30}"); do
        if timeout "${DB_CHECK_TIMEOUT:-5}" sh -c "$CHECK_DB"; then
          echo "Database is ready!"
          echo "Finished init container: wait-for-db"
          exit 0
        fi
        echo "Waiting for database... (attempt $i)"
        sleep "${DB_CHECK_INTERVAL:-1}"
      done
      echo "Database is not ready!"
      echo "Finished init container: wait-for-db"
      exit 1
  {{- end }}
  {{- if .Values.initContainers.solr.enabled }}
- name: wait-for-solr
  {{- if .Values.initContainers.solr.image }}
  image: {{ .Values.initContainers.solr.image }}
  {{- else }}
  image: {{ (include "xwiki.imageName" .) }}
  {{- end }}
  command:
    - /bin/sh
    - -c
    - |
      echo "Starting init container: wait-for-solr"
      for i in $(seq 1 30); do
        if curl --silent --connect-timeout "15000" "$SOLR_BASEURL/admin/info/system" | grep '"status":0'; then
          echo "Solr is ready!"
          echo "Finished init container: wait-for-solr"
          exit 0
        fi
        echo "Waiting for Solr..."
        sleep 1
      done
      echo "Solr is not ready!"
      echo "Finished init container: wait-for-solr"
      exit 1
  {{- if .Values.initContainers.solr.containerSecurityContext.enabled }}
  securityContext:
    {{- omit .Values.initContainers.solr.containerSecurityContext "enabled" | toYaml | nindent 4 }}
  {{- end }}
  {{- if .Values.initContainers.solr.resources }}
  resources:
    {{- toYaml .Values.initContainers.solr.resources | nindent 4 }}
  {{- else }}
  resources:
    {{- toYaml .Values.resources | nindent 4 }}
  {{- end }}
  env:
    - name: SOLR_BASEURL
      valueFrom:
        configMapKeyRef:
          name: {{ include "xwiki.fullname" . }}
          key: SOLR_BASEURL
  {{- end }}
{{- end }}

{{/*
Extra user-defined init containers.
*/}}
{{- define "xwiki.extraInitContainers" -}}
{{- range $name, $spec := .Values.extraInitContainers }}
{{- if $spec.enabled }}
- name: {{ $name }}
  image: {{ $spec.image | default (include "xwiki.imageName" $) | quote }}
  imagePullPolicy: {{ $spec.imagePullPolicy | default $.Values.image.pullPolicy }}
  {{- if $spec.securityContext }}
  securityContext:
    {{- toYaml $spec.securityContext | nindent 4 }}
  {{- else if $.Values.securityContext.enabled }}
      securityContext: {{- omit $.Values.securityContext "enabled" | toYaml | nindent 4 }}
  {{- end }}
  {{- if $spec.script }}
  command:
    - /bin/sh
    - -ec
  args:
    - |
      {{ include "xwiki.initContainer.execLog" $name | nindent 6 }}
      {{- $spec.script | nindent 6 }}
  {{- else }}
  {{- with $spec.command }}
  command:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  {{- with $spec.args }}
  args:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  {{- end }}
  {{- if or $spec.env $spec.includeDatabaseEnv }}
  env:
    {{- if $spec.includeDatabaseEnv }}
    {{- include "xwiki.database.env" $ | nindent 4 }}
    {{- end }}
    {{- with $spec.env }}
    {{- toYaml . | nindent 4 }}
    {{- end }}
  {{- end }}
  {{- with $spec.envFrom }}
  envFrom:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  {{- if $spec.resources }}
  resources:
    {{- toYaml $spec.resources | nindent 4 }}
  {{- else }}
  resources:
    {{- toYaml $.Values.resources | nindent 4 }}
  {{- end }}
  volumeMounts:
    {{- if $spec.volumeMounts }}
    {{- toYaml $spec.volumeMounts | nindent 4 }}
    {{- else }}
    {{- include "xwiki.volumeMounts" $ | nindent 4 }}
    {{- end }}
{{- end }}
{{- end }}
{{- end -}}