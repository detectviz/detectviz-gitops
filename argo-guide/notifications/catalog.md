# 觸發器與範本目錄
## 入門指南
* 從目錄安裝觸發器與範本
  ```bash
  kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/notifications_catalog/install.yaml
  ```
## 觸發器
|          名稱          |                          說明                          |                      範本                       |
|------------------------|---------------------------------------------------------------|-----------------------------------------------------|
| on-created             | 應用程式已建立。                                       | [app-created](#app-created)                         |
| on-deleted             | 應用程式已刪除。                                       | [app-deleted](#app-deleted)                         |
| on-deployed            | 應用程式已同步且狀況良好。每個提交觸發一次。 | [app-deployed](#app-deployed)                       |
| on-health-degraded     | 應用程式已降級                                      | [app-health-degraded](#app-health-degraded)         |
| on-sync-failed         | 應用程式同步失敗                                | [app-sync-failed](#app-sync-failed)                 |
| on-sync-running        | 應用程式正在同步中                                   | [app-sync-running](#app-sync-running)               |
| on-sync-status-unknown | 應用程式狀態為「未知」                               | [app-sync-status-unknown](#app-sync-status-unknown) |
| on-sync-succeeded      | 應用程式同步成功                             | [app-sync-succeeded](#app-sync-succeeded)           |

## 範本
### app-created
**定義**:
```yaml
email:
  subject: 應用程式 {{.app.metadata.name}} 已建立。
message: 應用程式 {{.app.metadata.name}} 已建立。
teams:
  title: 應用程式 {{.app.metadata.name}} 已建立。

```
### app-deleted
**定義**:
```yaml
email:
  subject: 應用程式 {{.app.metadata.name}} 已刪除。
message: 應用程式 {{.app.metadata.name}} 已刪除。
teams:
  title: 應用程式 {{.app.metadata.name}} 已刪除。

```
### app-deployed
**定義**:
```yaml
email:
  subject: 應用程式 {{.app.metadata.name}} 的新版本已啟動並執行。
message: |
  {{if eq .serviceType "slack"}}:white_check_mark:{{end}} 應用程式 {{.app.metadata.name}} 現在正在執行新版本的部署資訊清單。
slack:
  attachments: |
    [{
      "title": "{{ .app.metadata.name}}",
      "title_link":"{{.context.argocdUrl}}/applications/{{.app.metadata.name}}",
      "color": "#18be52",
      "fields": [
      {
        "title": "同步狀態",
        "value": "{{.app.status.sync.status}}",
        "short": true
      },
      {
        "title": {{- if .app.spec.source }} "儲存庫" {{- else if .app.spec.sources }} "儲存庫" {{- end }},
        "value": {{- if .app.spec.source }} ":arrow_heading_up: {{ .app.spec.source.repoURL }}" {{- else if .app.spec.sources }} "{{- range $index, $source := .app.spec.sources }}{{ if $index }}\n{{ end }}:arrow_heading_up: {{ $source.repoURL }}{{- end }}" {{- end }},
        "short": true
      },
      {
        "title": "修訂版本",
        "value": "{{.app.status.sync.revision}}",
        "short": true
      }
      {{range $index, $c := .app.status.conditions}}
      ,
      {
        "title": "{{$c.type}}",
        "value": "{{$c.message}}",
        "short": true
      }
      {{end}}
      ]
    }]
  deliveryPolicy: Post
  groupingKey: ""
  notifyBroadcast: false
teams:
  facts: |
    [{
      "name": "同步狀態",
      "value": "{{.app.status.sync.status}}"
    },
    {
      "name": {{- if .app.spec.source }} "儲存庫" {{- else if .app.spec.sources }} "儲存庫" {{- end }},
      "value": {{- if .app.spec.source }} "⬆️ {{ .app.spec.source.repoURL }}" {{- else if .app.spec.sources }} "{{- range $index, $source := .app.spec.sources }}{{ if $index }}\n{{ end }}⬆️ {{ $source.repoURL }}{{- end }}" {{- end }}
    },
    {
      "name": "修訂版本",
      "value": "{{.app.status.sync.revision}}"
    }
    {{range $index, $c := .app.status.conditions}}
      ,
      {
        "name": "{{$c.type}}",
        "value": "{{$c.message}}"
      }
    {{end}}
    ]
  potentialAction: |
    [{
      "@type":"OpenUri",
      "name":"操作應用程式",
      "targets":[{
        "os":"default",
        "uri":"{{.context.argocdUrl}}/applications/{{.app.metadata.name}}"
      }]
    },
    {
      "@type":"OpenUri",
      "name":"開啟儲存庫",
      "targets":[{
        "os":"default",
        "uri":{{- if .app.spec.source }} "⬆️ {{ .app.spec.source.repoURL }}" {{- else if .app.spec.sources }} "{{- range $index, $source := .app.spec.sources }}{{ if $index }}\n{{ end }}⬆️ {{ $source.repoURL }}{{- end }}" {{- end }}
      }]
    }]
  themeColor: '#000080'
  title: 應用程式 {{.app.metadata.name}} 的新版本已啟動並執行。

```
### app-health-degraded
**定義**:
```yaml
email:
  subject: 應用程式 {{.app.metadata.name}} 已降級。
message: |
  {{if eq .serviceType "slack"}}:exclamation:{{end}} 應用程式 {{.app.metadata.name}} 已降級。
  應用程式詳細資訊：{{.context.argocdUrl}}/applications/{{.app.metadata.name}}。
slack:
  attachments: |
    [{
      "title": "{{ .app.metadata.name}}",
      "title_link":"{{.context.argocdUrl}}/applications/{{.app.metadata.name}}",
      "color": "#f4c030",
      "fields": [
      {
        "title": "健康狀態",
        "value": "{{.app.status.health.status}}",
        "short": true
      },
      {
        "title": {{- if .app.spec.source }} "儲存庫" {{- else if .app.spec.sources }} "儲存庫" {{- end }},
        "value": {{- if .app.spec.source }} ":arrow_heading_up: {{ .app.spec.source.repoURL }}" {{- else if .app.spec.sources }} "{{- range $index, $source := .app.spec.sources }}{{ if $index }}\n{{ end }}:arrow_heading_up: {{ $source.repoURL }}{{- end }}" {{- end }},
        "short": true
      }
      {{range $index, $c := .app.status.conditions}}
      ,
      {
        "title": "{{$c.type}}",
        "value": "{{$c.message}}",
        "short": true
      }
      {{end}}
      ]
    }]
  deliveryPolicy: Post
  groupingKey: ""
  notifyBroadcast: false
teams:
  facts: |
    [{
      "name": "健康狀態",
      "value": "{{.app.status.health.status}}"
    },
    {
      "name": {{- if .app.spec.source }} "儲存庫" {{- else if .app.spec.sources }} "儲存庫" {{- end }},
      "value": {{- if .app.spec.source }} "⬆️ {{ .app.spec.source.repoURL }}" {{- else if .app.spec.sources }} "{{- range $index, $source := .app.spec.sources }}{{ if $index }}\n{{ end }}⬆️ {{ $source.repoURL }}{{- end }}" {{- end }}
    }
    {{range $index, $c := .app.status.conditions}}
      ,
      {
        "name": "{{$c.type}}",
        "value": "{{$c.message}}"
      }
    {{end}}
    ]
  potentialAction: |
    [{
      "@type":"OpenUri",
      "name":"開啟應用程式",
      "targets":[{
        "os":"default",
        "uri":"{{.context.argocdUrl}}/applications/{{.app.metadata.name}}"
      }]
    },
    {
      "@type":"OpenUri",
      "name":"開啟儲存庫",
      "targets":[{
        "os":"default",
        "uri":{{- if .app.spec.source }} "⬆️ {{ .app.spec.source.repoURL }}" {{- else if .app.spec.sources }} "{{- range $index, $source := .app.spec.sources }}{{ if $index }}\n{{ end }}⬆️ {{ $source.repoURL }}{{- end }}" {{- end }}
      }]
    }]
  themeColor: '#FF0000'
  title: 應用程式 {{.app.metadata.name}} 已降級。

```
### app-sync-failed
**定義**:
```yaml
email:
  subject: 同步應用程式 {{.app.metadata.name}} 失敗。
message: |
  {{if eq .serviceType "slack"}}:exclamation:{{end}}  應用程式 {{.app.metadata.name}} 的同步操作於 {{.app.status.operationState.finishedAt}} 失敗，錯誤如下：{{.app.status.operationState.message}}
  同步操作詳細資訊可在以下網址取得：{{.context.argocdUrl}}/applications/{{.app.metadata.name}}?operation=true 。
slack:
  attachments: |
    [{
      "title": "{{ .app.metadata.name}}",
      "title_link":"{{.context.argocdUrl}}/applications/{{.app.metadata.name}}",
      "color": "#E96D76",
      "fields": [
      {
        "title": "同步狀態",
        "value": "{{.app.status.sync.status}}",
        "short": true
      },
      {
        "title": {{- if .app.spec.source }} "儲存庫" {{- else if .app.spec.sources }} "儲存庫" {{- end }},
        "value": {{- if .app.spec.source }} ":arrow_heading_up: {{ .app.spec.source.repoURL }}" {{- else if .app.spec.sources }} "{{- range $index, $source := .app.spec.sources }}{{ if $index }}\n{{ end }}:arrow_heading_up: {{ $source.repoURL }}{{- end }}" {{- end }},
        "short": true
      }
      {{range $index, $c := .app.status.conditions}}
      ,
      {
        "title": "{{$c.type}}",
        "value": "{{$c.message}}",
        "short": true
      }
      {{end}}
      ]
    }]
  deliveryPolicy: Post
  groupingKey: ""
  notifyBroadcast: false
teams:
  facts: |
    [{
      "name": "同步狀態",
      "value": "{{.app.status.sync.status}}"
    },
    {
      "name": "失敗時間",
      "value": "{{.app.status.operationState.finishedAt}}"
    },
    {
      "name": {{- if .app.spec.source }} "儲存庫" {{- else if .app.spec.sources }} "儲存庫" {{- end }},
      "value": {{- if .app.spec.source }} "⬆️ {{ .app.spec.source.repoURL }}" {{- else if .app.spec.sources }} "{{- range $index, $source := .app.spec.sources }}{{ if $index }}\n{{ end }}⬆️ {{ $source.repoURL }}{{- end }}" {{- end }}
    }
    {{range $index, $c := .app.status.conditions}}
      ,
      {
        "name": "{{$c.type}}",
        "value": "{{$c.message}}"
      }
    {{end}}
    ]
  potentialAction: |
    [{
      "@type":"OpenUri",
      "name":"開啟操作",
      "targets":[{
        "os":"default",
        "uri":"{{.context.argocdUrl}}/applications/{{.app.metadata.name}}?operation=true"
      }]
    },
    {
      "@type":"OpenUri",
      "name":"開啟儲存庫",
      "targets":[{
        "os":"default",
        "uri":{{- if .app.spec.source }} "⬆️ {{ .app.spec.source.repoURL }}" {{- else if .app.spec.sources }} "{{- range $index, $source := .app.spec.sources }}{{ if $index }}\n{{ end }}{{ $source.repoURL }}⬆️ {{- end }}" {{- end }}
      }]
    }]
  themeColor: '#FF0000'
  title: 同步應用程式 {{.app.metadata.name}} 失敗。

```
### app-sync-running
**定義**:
```yaml
email:
  subject: 開始同步應用程式 {{.app.metadata.name}}。
message: |
  應用程式 {{.app.metadata.name}} 的同步操作已於 {{.app.status.operationState.startedAt}} 開始。
  同步操作詳細資訊可在以下網址取得：{{.context.argocdUrl}}/applications/{{.app.metadata.name}}?operation=true 。
slack:
  attachments: |
    [{
      "title": "{{ .app.metadata.name}}",
      "title_link":"{{.context.argocdUrl}}/applications/{{.app.metadata.name}}",
      "color": "#0DADEA",
      "fields": [
      {
        "title": "同步狀態",
        "value": "{{.app.status.sync.status}}",
        "short": true
      },
      {
        "title": {{- if .app.spec.source }} "儲存庫" {{- else if .app.spec.sources }} "儲存庫" {{- end }},
        "value": {{- if .app.spec.source }} ":arrow_heading_up: {{ .app.spec.source.repoURL }}" {{- else if .app.spec.sources }} "{{- range $index, $source := .app.spec.sources }}{{ if $index }}\n{{ end }}:arrow_heading_up: {{ $source.repoURL }}{{- end }}" {{- end }},
        "short": true
      }
      {{range $index, $c := .app.status.conditions}}
      ,
      {
        "title": "{{$c.type}}",
        "value": "{{$c.message}}",
        "short": true
      }
      {{end}}
      ]
    }]
  deliveryPolicy: Post
  groupingKey: ""
  notifyBroadcast: false
teams:
  facts: |
    [{
      "name": "同步狀態",
      "value": "{{.app.status.sync.status}}"
    },
    {
      "name": "開始時間",
      "value": "{{.app.status.operationState.startedAt}}"
    },
    {
      "name": {{- if .app.spec.source }} "儲存庫" {{- else if .app.spec.sources }} "儲存庫" {{- end }},
      "value": {{- if .app.spec.source }} "⬆️ {{ .app.spec.source.repoURL }}" {{- else if .app.spec.sources }} "{{- range $index, $source := .app.spec.sources }}{{ if $index }}\n{{ end }}⬆️ {{ $source.repoURL }}{{- end }}" {{- end }}
    }
    {{range $index, $c := .app.status.conditions}}
      ,
      {
        "name": "{{$c.type}}",
        "value": "{{$c.message}}"
      }
    {{end}}
    ]
  potentialAction: |
    [{
      "@type":"OpenUri",
      "name":"開啟操作",
      "targets":[{
        "os":"default",
        "uri":"{{.context.argocdUrl}}/applications/{{.app.metadata.name}}?operation=true"
      }]
    },
    {
      "@type":"OpenUri",
      "name":"開啟儲存庫",
      "targets":[{
        "os":"default",
        "uri":{{- if .app.spec.source }} "⬆️ {{ .app.spec.source.repoURL }}" {{- else if .app.spec.sources }} "{{- range $index, $source := .app.spec.sources }}{{ if $index }}\n{{ end }}⬆️ {{ $source.repoURL }}{{- end }}" {{- end }}
      }]
    }]
  title: 開始同步應用程式 {{.app.metadata.name}}。

```
### app-sync-status-unknown
**定義**:
```yaml
email:
  subject: 應用程式 {{.app.metadata.name}} 的同步狀態為「未知」
message: |
  {{if eq .serviceType "slack"}}:exclamation:{{end}} 應用程式 {{.app.metadata.name}} 的同步狀態為「未知」。
  應用程式詳細資訊：{{.context.argocdUrl}}/applications/{{.app.metadata.name}}。
  {{if ne .serviceType "slack"}}
  {{range $c := .app.status.conditions}}
      * {{$c.message}}
  {{end}}
  {{end}}
slack:
  attachments: |
    [{
      "title": "{{ .app.metadata.name}}",
      "title_link":"{{.context.argocdUrl}}/applications/{{.app.metadata.name}}",
      "color": "#E96D76",
      "fields": [
      {
        "title": "同步狀態",
        "value": "{{.app.status.sync.status}}",
        "short": true
      },
      {
        "title": {{- if .app.spec.source }} "儲存庫" {{- else if .app.spec.sources }} "儲存庫" {{- end }},
        "value": {{- if .app.spec.source }} ":arrow_heading_up: {{ .app.spec.source.repoURL }}" {{- else if .app.spec.sources }} "{{- range $index, $source := .app.spec.sources }}{{ if $index }}\n{{ end }}:arrow_heading_up: {{ $source.repoURL }}{{- end }}" {{- end }},
        "short": true
      }
      {{range $index, $c := .app.status.conditions}}
      ,
      {
        "title": "{{$c.type}}",
        "value": "{{$c.message}}",
        "short": true
      }
      {{end}}
      ]
    }]
  deliveryPolicy: Post
  groupingKey: ""
  notifyBroadcast: false
teams:
  facts: |
    [{
      "name": "同步狀態",
      "value": "{{.app.status.sync.status}}"
    },
    {
      "name": {{- if .app.spec.source }} "儲存庫" {{- else if .app.spec.sources }} "儲存庫" {{- end }},
      "value": {{- if .app.spec.source }} "⬆️ {{ .app.spec.source.repoURL }}" {{- else if .app.spec.sources }} "{{- range $index, $source := .app.spec.sources }}{{ if $index }}\n{{ end }}⬆️ {{ $source.repoURL }}{{- end }}" {{- end }}
    }
    {{range $index, $c := .app.status.conditions}}
      ,
      {
        "name": "{{$c.type}}",
        "value": "{{$c.message}}"
      }
    {{end}}
    ]
  potentialAction: |
    [{
      "@type":"OpenUri",
      "name":"開啟應用程式",
      "targets":[{
        "os":"default",
        "uri":"{{.context.argocdUrl}}/applications/{{.app.metadata.name}}"
      }]
    },
    {
      "@type":"OpenUri",
      "name":"開啟儲存庫",
      "targets":[{
        "os":"default",
        "uri":{{- if .app.spec.source }} "⬆️ {{ .app.spec.source.repoURL }}" {{- else if .app.spec.sources }} "{{- range $index, $source := .app.spec.sources }}{{ if $index }}\n{{ end }}⬆️ {{ $source.repoURL }}{{- end }}" {{- end }}
      }]
    }]
  title: 應用程式 {{.app.metadata.name}} 的同步狀態為「未知」

```
### app-sync-succeeded
**定義**:
```yaml
email:
  subject: 應用程式 {{.app.metadata.name}} 已成功同步。
message: |
  {{if eq .serviceType "slack"}}:white_check_mark:{{end}} 應用程式 {{.app.metadata.name}} 已於 {{.app.status.operationState.finishedAt}} 成功同步。
  同步操作詳細資訊可在以下網址取得：{{.context.argocdUrl}}/applications/{{.app.metadata.name}}?operation=true 。
slack:
  attachments: |
    [{
      "title": "{{ .app.metadata.name}}",
      "title_link":"{{.context.argocdUrl}}/applications/{{.app.metadata.name}}",
      "color": "#18be52",
      "fields": [
      {
        "title": "同步狀態",
        "value": "{{.app.status.sync.status}}",
        "short": true
      },
      {
        "title": {{- if .app.spec.source }} "儲存庫" {{- else if .app.spec.sources }} "儲存庫" {{- end }},
        "value": {{- if .app.spec.source }} ":arrow_heading_up: {{ .app.spec.source.repoURL }}" {{- else if .app.spec.sources }} "{{- range $index, $source := .app.spec.sources }}{{ if $index }}\n{{ end }}:arrow_heading_up: {{ $source.repoURL }}{{- end }}" {{- end }},
        "short": true
      }
      {{range $index, $c := .app.status.conditions}}
      ,
      {
        "title": "{{$c.type}}",
        "value": "{{$c.message}}",
        "short": true
      }
      {{end}}
      ]
    }]
  deliveryPolicy: Post
  groupingKey: ""
  notifyBroadcast: false
teams:
  facts: |
    [{
      "name": "同步狀態",
      "value": "{{.app.status.sync.status}}"
    },
    {
      "name": "同步時間",
      "value": "{{.app.status.operationState.finishedAt}}"
    },
    {
      "name": {{- if .app.spec.source }} "儲存庫" {{- else if .app.spec.sources }} "儲存庫" {{- end }},
      "value": {{- if .app.spec.source }} "⬆️ {{ .app.spec.source.repoURL }}" {{- else if .app.spec.sources }} "{{- range $index, $source := .app.spec.sources }}{{ if $index }}\n{{ end }}⬆️ {{ $source.repoURL }}{{- end }}" {{- end }}
    }
    {{range $index, $c := .app.status.conditions}}
      ,
      {
        "name": "{{$c.type}}",
        "value": "{{$c.message}}"
      }
    {{end}}
    ]
  potentialAction: |
    [{
      "@type":"OpenUri",
      "name":"操作詳細資訊",
      "targets":[{
        "os":"default",
        "uri":"{{.context.argocdUrl}}/applications/{{.app.metadata.name}}?operation=true"
      }]
    },
    {
      "@type":"OpenUri",
      "name":"開啟儲存庫",
      "targets":[{
        "os":"default",
        "uri":{{- if .app.spec.source }} "⬆️ {{ .app.spec.source.repoURL }}" {{- else if .app.spec.sources }} "{{- range $index, $source := .app.spec.sources }}{{ if $index }}\n{{ end }}⬆️ {{ $source.repoURL }}{{- end }}" {{- end }}
      }]
    }]
  themeColor: '#000080'
  title: 應用程式 {{.app.metadata.name}} 已成功同步

```
