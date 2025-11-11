# 網頁式終端機

![Argo CD 終端機](../assets/terminal.png)

自 v2.4 版起，Argo CD 提供一個網頁式終端機，讓您可以像使用 `kubectl exec` 一樣，在執行中的 pod 內取得一個 shell。基本上，這就是從您的瀏覽器進行 SSH，完全支援 ANSI 色彩！然而，基於安全性考量，此功能預設為停用。

這是一項強大的權限。它允許使用者在他們擁有 `exec/create` 權限的應用程式所管理的任何 Pod 上執行任意程式碼。如果 Pod 掛載了 ServiceAccount 權杖（這是 Kubernetes 的預設行為），那麼使用者實際上就擁有與該 ServiceAccount 相同的權限。

## 啟用終端機
<!-- 在編號清單中使用縮排的程式碼區塊，以防止編號中斷。請參閱 #11590 -->

1. 在 `argocd-cm` ConfigMap 中，將 `exec.enabled` 金鑰設定為 `"true"`。這會在 Argo CD 中啟用 exec 功能。

    ```
    apiVersion: v1
    kind: ConfigMap
    metadata:
      name: argocd-cm
      namespace: <namespace>  # 將 <namespace> 替換為您的實際命名空間
    data:
      exec.enabled: "true"
    ```

2. 修補 `argocd-server` Role（如果使用命名空間範圍的 Argo）或 ClusterRole（如果使用叢集範圍的 Argo），以允許 `argocd-server` `exec` 進入 pod。

        - apiGroups:
          - ""
          resources:
          - pods/exec
          verbs:
          - create
   如果您想以命令式的方式執行修補，可以使用以下指令：
        
    - 對於命名空間範圍的 Argo
         ```
         kubectl patch role <argocd-server-role-name> -n argocd --type='json' -p='[{"op": "add", "path": "/rules/-", "value": {"apiGroups": ["*"], "resources": ["pods/exec"], "verbs": ["create"]}}]'
         ```
    - 對於叢集範圍的 Argo
         ```
         kubectl patch clusterrole <argocd-server-clusterrole-name> --type='json' -p='[{"op": "add", "path": "/rules/-", "value": {"apiGroups": ["*"], "resources": ["pods/exec"], "verbs": ["create"]}}]'
         ```

3. 新增 RBAC 規則以允許您的使用者 `create` `exec` 資源，即

        p, role:myrole, exec, create, */*, allow 

    這可以新增到 `argocd-cm` `Configmap` 清單或 `AppProject` 清單中。

   有關更多資訊，請參閱 [RBAC 組態](rbac.md#exec-resource)。

## 變更允許的 shell

預設情況下，Argo CD 會依此順序嘗試執行 shell：

1. bash
2. sh
3. powershell
4. cmd

如果找不到任何 shell，終端機連線將會失敗。若要新增或變更允許的 shell，請變更 `argocd-cm` ConfigMap 中的 `exec.shells` 金鑰，並用逗號分隔它們。
