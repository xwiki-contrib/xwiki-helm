{{/*
Entrypoint shell snippet that patches the image server.xml via sed.
The original file is copied to a writable data directory, updated, then copied back.
*/}}
{{- define "xwiki.customTomcatServer.entrypoint" -}}
    if [ -d "/usr/local/tomcat" ]; then
      SERVER_XML_DEST="$AS_PATH/conf/server.xml"
      SERVER_XML_WORK="/usr/local/xwiki/data/server.xml.new"

      function tomcat_server_xml_replace_or_add() {
        local attribute="$1"
        local new_value="$2"

        if sed -n "/protocol=\"HTTP\/1.1\"/,/^[[:space:]]*\/>/p" "$SERVER_XML_WORK" | grep -q "${attribute}="; then
          sed -i "/protocol=\"HTTP\/1.1\"/,/^[[:space:]]*\/>/ s|${attribute}=\"[^\"]*\"|${attribute}=\"${new_value}\"|" "$SERVER_XML_WORK"
        else
          sed -i "/protocol=\"HTTP\/1.1\"/,/^[[:space:]]*\/>/{
            /^[[:space:]]*\/>/i\\
               ${attribute}=\"${new_value}\"
          }" "$SERVER_XML_WORK"
        fi
      }

      cp "$SERVER_XML_DEST" "$SERVER_XML_WORK"

      sed -i 's|<Connector port="[0-9]*" protocol="HTTP/1.1"|<Connector port="{{ .Values.service.internalPort }}" protocol="HTTP/1.1"|' "$SERVER_XML_WORK"
      sed -i '/protocol="HTTP\/1.1"/,/^[[:space:]]*\/>/ s/port="[0-9]*"/port="{{ .Values.service.internalPort }}"/' "$SERVER_XML_WORK"
{{- range $attribute, $value := .Values.customTomcatServer.connector }}
      tomcat_server_xml_replace_or_add "{{ $attribute }}" "{{ $value }}"
{{- end }}
{{- range $className, $attrs := .Values.customTomcatServer.valvesEngine }}
{{ include "xwiki.customTomcatServer.valve" (dict "sectionStart" "<Engine name=\\\"Catalina\\\"" "sectionEnd" "<\\/Engine>" "className" $className "attrs" $attrs) }}
{{- end }}
{{- range $className, $attrs := .Values.customTomcatServer.valvesHost }}
{{ include "xwiki.customTomcatServer.valve" (dict "sectionStart" "<Host name=\\\"localhost\\\"" "sectionEnd" "<\\/Host>" "className" $className "attrs" $attrs) }}
{{- end }}

      cp "$SERVER_XML_WORK" "$SERVER_XML_DEST"
      rm -f "$SERVER_XML_WORK"
    fi
{{- end -}}

{{/*
Render the sed commands that add (or replace, if already present) a single Valve
element inside a given server.xml section.

Expects a dict with:
  sectionStart : regex matching the opening tag of the section (e.g. <Engine name="Catalina")
  sectionEnd   : regex matching the closing tag of the section (e.g. <\/Engine>)
  className    : the Valve className
  attrs        : map of Valve attribute name to value

First any existing Valve with the same className inside the section is removed
(handles single and multi-line valves), then the new Valve is inserted just
before the section closing tag. This makes the operation idempotent.
*/}}
{{- define "xwiki.customTomcatServer.valve" -}}
{{- $sectionStart := .sectionStart }}
{{- $sectionEnd := .sectionEnd }}
{{- $className := .className }}
{{- $attrs := .attrs }}
      sed -i "/{{ $sectionStart }}/,/{{ $sectionEnd }}/{
        /<Valve className=\"{{ $className }}\"/{
          :a
          /\/>/!{N;ba}
          d
        }
      }" "$SERVER_XML_WORK"
      sed -i "/{{ $sectionStart }}/,/{{ $sectionEnd }}/{
        /{{ $sectionEnd }}/i\\
      <Valve className=\"{{ $className }}\"\\
{{- range $k, $v := $attrs }}
          {{ $k }}=\"{{ $v }}\"\\
{{- end }}
          />
      }" "$SERVER_XML_WORK"
{{- end -}}
