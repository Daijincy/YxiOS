# YunX（云析）Android → iOS 移植规格说明（platform-spec）

> 本文档面向 Swift 工程师，目标是**不重读 Kotlin 源码**即可重写 iOS 核心。
> 所有正则、URL、请求头、请求体字段、JSON 字段树均从 `app/src/main/kotlin/com/yunx/app/data/` 原样抄录。
> 阅读对应实现时的行号可作为校验锚点。本文**不包含任何 Swift 实现代码**。

---

## 0. 原仓库归属与 License 署名（后续界面「关于」页必须照此署名）

- 原仓库地址（`git remote -v` 实测）：`https://github.com/CYQawa/YunX.git`
- License：**AGPL-3.0**。每个源文件头均带如下版权声明（原样复制，署名用）：

```
YunX (云析) - A network drive share-link parser and high-speed downloader for Android.
Copyright (C) 2026 CYQawa

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU Affero General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU Affero General Public License for more details.

You should have received a copy of the GNU Affero General Public License
along with this program.  If not, see <https://www.gnu.org/licenses/>.
```

`LICENSE` 文件头几行（GNU AFFERO GENERAL PUBLIC LICENSE）：

```
                    GNU AFFERO GENERAL PUBLIC LICENSE
                       Version 3, 19 November 2007

 Copyright (C) 2007 Free Software Foundation, Inc. <https://fsf.org/>
 Everyone is permitted to copy and distribute verbatim copies
 of this license document, but changing it is not allowed.
```

> 与 `YxiOS/docs/API-CONTRACT.md` 的对应关系：契约只覆盖 quark / baidu / pan123 / xunlei 四平台，本文档这四节即为契约 `PlatformClient.resolveShare / listChildren / getDirectURL` 的实现依据。UC / C139 / 115 / GitHub 本期不移植，仅在 §1 保留链接正则备查。

---

## 1. 分享链接正则（`network/ShareLinkParser.kt`，原样复制）

通用流程（`parse(text)`）：
1. 先用 `urlRegex` 从整段文案抓第一个 URL：`https?://[^\s]+`，并 trim 掉结尾标点 `。，,；;) ] } " '`。
2. 按平台顺序依次匹配，命中即返回（**顺序很重要**）。
3. 提取码优先级：URL 上的 `?pwd=xxxx`（115 为 `?password=`）＞ 文案里的「提取码/访问码/密码：xxxx」。
4. 提取码通用正则（原样）：
   - URL 内 pwd：`[?&]pwd=([A-Za-z0-9]+)`
   - 文案内：`(?:提取码|访问码|密码)[：:]\s*([A-Za-z0-9]{4,8})`

### 1.1 夸克 QUARK
- URL 形态：`https://pan.quark.cn/s/<shareId>`
- 正则（原样，IGNORE_CASE）：`pan\.quark\.cn/s/([A-Za-z0-9]+)`
- 解析字段：`shareId` = 分组1；`pwd` 可空。
- 注意：夸克 shareId 直接就是 `pwd_id`，**不要**再去前缀。

### 1.2 百度 BAIDU
- URL 形态：`https://pan.baidu.com/s/1<surl>?pwd=xxxx`
- 正则（原样，IGNORE_CASE）：`pan\.baidu\.com/s/(1[A-Za-z0-9_-]+)`
- 解析字段：分组1 以 `1` 开头；**代码会 `removePrefix("1")`**，对外的 `shareId`（即 surl）是去掉开头 `1` 之后的部分。例如 `/s/1abcDEF` → surl=`abcDEF`。
- 提取码：URL `?pwd=` 或文案。

### 1.3 123 云盘 PAN123
三种形态，按代码优先级依次匹配（均 IGNORE_CASE）：
```
123(?:865|pan)\.(?:com|cn)/s/([A-Za-z0-9]+-[A-Za-z0-9]+)   // www.123pan.com/s/<ShareKey> 等
share\.123pan\.cn/123pan/([A-Za-z0-9-]+)                    // <UID>.share.123pan.cn/123pan/<ShareKey>
api/srr\?sk=([A-Za-z0-9-]+)                                 // www.123pan.cn/api/srr?sk=<ShareKey>&st=s
```
- `shareId` = ShareKey。形态1 的 ShareKey 形如 `2785Vv-T4Ded`（含一个中划线，两端字母数字）。
- 提取码：URL `?pwd=` 或文案。**无提取码时绝不要传空字符串参数**（见 §4.3）。

### 1.4 迅雷 XUNLEI
- URL 形态：`https://pan.xunlei.com/s/<shareId>`
- 正则（原样，IGNORE_CASE）：`pan\.xunlei\.com/s/([A-Za-z0-9_-]+)`
- 解析字段：`shareId` = 分组1；`pwd` 可空（迅雷提取码走 `pass_code`）。

### 1.5 备查（本期不移植）
```
yun\.139\.com/shareweb/.*?/w/i/([A-Za-z0-9_-]+)            // 139 和彩云
115(?:cdn|rc)?\.com/s/(sw[A-Za-z0-9]+)                     // 115
115(?:cdn|rc)?\.com/(sw[A-Za-z0-9]{8,})-([A-Za-z0-9]{4,8}) // 115 口令形式（code-提取码）
[?&]password=([A-Za-z0-9]+)                                // 115 URL 内提取码
```

---

## 2. HTTP 公共配置（`network/HttpClients.kt`）

- **API 客户端**（登录/解析/直链）：connectTimeout=15s，readTimeout=60s，writeTimeout=30s，`retryOnConnectionFailure(true)`。
- **下载客户端**（分片）：
  - 协议**固定只用 HTTP/1.1**（`protocols = [HTTP_1_1]`）。原因：OkHttp HTTP/2 每流 16MB 接收窗口，慢消费会撑爆堆。iOS 移植时用 URLSession 默认即可，但要知道「HTTP/2 多路复用在分片下载时不是优势」。
  - 空闲连接池：8 条空闲连接，keepAlive 1 分钟。
  - Dispatcher maxRequests / maxRequestsPerHost = 64（仅排队 Call 上限；分片走同步 execute，真实并发由信号量控制）。
  - 同 API 客户端超时。
- 客户端支持运行时设置 HTTP 代理（`setProxy`），iOS 可忽略系统代理透传逻辑，用系统默认。
- **安全**：全程系统证书链 + 主机名校验，**不允许**关闭校验。

---

## 3. 夸克 QUARK（`QuarkApi.kt` / `QuarkConstants.kt`）

### 3.1 认证来源
- WebView 登录页：`https://pan.quark.cn/?fr=pc&platform=pc`，从域名 `https://pan.quark.cn` 的 Cookie 中抓取整串。
- **登录态判定**：Cookie 串必须同时包含 `__pus=` 与 `__puus=`，缺一即视为未登录（`QuarkConstants.isValidCookie`）。
- `__puus` 约 3 小时过期，是直链签名校验关键字段。
- **取链 UA（必带）**（注意不是普通浏览器 UA）：
  `Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) quark-cloud-drive/2.5.20 Chrome/100.0.4896.160 Electron/18.3.5.12-a038f7b798 Safari/537.36 Channel/pckk_other_ch`

### 3.2 端点
- baseURL：`https://drive-pc.quark.cn`（下文 path 均拼此 base）。所有业务 URL 都带 query `?pr=ucpro&fr=pc`。
- 分享 Token：`POST /1/clouddrive/share/sharepage/token?pr=ucpro&fr=pc`
- 分享文件列表：`GET /1/clouddrive/share/sharepage/detail?pr=ucpro&fr=pc`
- 下载直链：`POST /1/clouddrive/file/download?pr=ucpro&fr=pc&sys=win32&ve=3.23.2`
- 刷新会话：`GET /1/clouddrive/config?pr=ucpro&fr=pc`
- 转存：`POST /1/clouddrive/share/sharepage/save?pr=ucpro&fr=pc`
- 转存任务轮询：`GET /1/clouddrive/task?pr=ucpro&fr=pc&task_id=<id>&retry_index=0`
- 临时清理（取链成功后删转存文件）：`POST /1/clouddrive/file/delete?pr=ucpro&fr=pc&uc_param_str=`

### 3.3 请求 / 响应细节

**(1) 获取分享 Token**
- 请求头：`Cookie: <登录cookie>`、`User-Agent: <上面的 quark UA>`、`Content-Type: application/json`
- 请求体 JSON：`{"pwd_id":"<shareId>","passcode":"<提取码或空串>","support_visit_limit_private_share":true}`
- 响应：`status==200` 为成功。`data` 字段树：
  ```
  data:
    stoken     (string, 后续所有分享接口都要带)
    title      (string)
    first_fid  (string)
  ```

**(2) 分享文件列表（GET，query 拼在 URL）**
```
...&pwd_id=<shareId>&stoken=<urlEncode(stoken)>&pdir_fid=<父fid, 根目录="0">
   &ver=2&force=0&_page=1&_size=100&_fetch_banner=0&_fetch_share=0
   &fetch_relate_conversation=0&_fetch_total=1&_sort=file_type:asc,file_name:asc
```
- 必带头：`Cookie`、`User-Agent`、`Origin: https://pan.quark.cn`、`Referer: https://pan.quark.cn/`（缺 Origin/Referer 可能 400）。
- 响应 `data.list[]` 字段树（抓包为准，**不是**文档里的 fname/fsize/isdir）：
  ```
  data.list[]:
    fid           (string)
    file_name     (string, 文件名)
    size          (number, 字节)
    dir           (bool, 是否目录)
    pdir_fid      (string)
    share_fid_token (string, 取游客直链要用)
    updated_at    (string)
  ```

**(3) 获取下载直链**

两种路径：

- **登录态直链**（个人网盘里的文件，或已转存后的 fid）：
  - `POST /1/clouddrive/file/download?pr=ucpro&fr=pc&sys=win32&ve=3.23.2`
  - body：`{"fids":["<fid>"]}`
  - 成功判定：`status==200 || code==0`。失败时用 `code`（如 21001 file not found）与 `message`。
  - 响应 `data[0]`：
    ```
    data[0]:
      fid
      file_name   (空则回退 filename)
      download_url (直链)
      size
    ```

- **游客分享直链**（未登录，仅约 ≤50MB 小文件可用）：
  - 同端点。body：`{"fids":["<fid>"],"fids_token":["<share_fid_token>"],"pwd_id":"<shareId>","stoken":"<stoken>","speedup_session":"","token":""}`
  - 首次请求**不带 Cookie 头**。响应 `Set-Cookie` 里会下发游客令牌 `__pugs=...`；**后续下载该直链时必须把 `__pugs=值` 作为 Cookie 带上，否则 CDN 返回 412**。
  - 错误码：`23018` = 超出游客大小上限；`31001` = 需要登录。

**(4) 取到大文件直链的典型链路（登录态）**：
`getShareToken → getShareFiles → saveShareFile(转存到个人盘临时目录) → pollTask(轮询拿新 fid) → getDownloadLink(新fid) → deleteFile(清理转存)`。
- 转存 body：`{"pwd_id":shareId,"stoken":stoken,"pdir_fid":pdirFid,"to_pdir_fid":目标目录fid,"fid_list":["<fid>"],"fid_token_list":["<share_fid_token>"],"scene":"link"}` → `data.task_id`。
- 轮询：最多 10 次 ×1s。完成条件 `data.finished_at>0 || data.status==2 || data.task_status==2`；转存后新 fid 在 `data.save_as.save_as_top_fids[0]`。

### 3.4 特殊头 / 签名
- **下载直链防盗链 Referer 必须为**：`https://pan.quark.cn/`（下载分片时也要带）。
- 无 sign 加密。
- Cookie 保鲜：每次响应把 `Set-Cookie` 里最新的 `__puus`/`__pus` 合并回本地 Cookie 串；若 `__puus` 失效，可把请求 Cookie 里的 `__puus` 去掉后请求 `/config`，服务端会重新下发（refreshSession）。

---

## 4. 百度 BAIDU（`BaiduApi.kt` / `BaiduConstants.kt`）

### 4.1 认证来源
- WebView 登录页：`https://pan.baidu.com/`，从域名 `https://pan.baidu.com` 抓 Cookie。
- **登录态判定**：Cookie 串必须含 `BDUSS=`。
- 两套 UA：
  - `UA_WEB`（网页接口 share/verify、xpan/share、gettemplatevariable、filemetas）：
    `Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36`
  - `UA_NETDISK`（locatedownload、yun/api/list、filemanager）：
    `netdisk;12.24.6;piano;android-android;16;JSbridge4.4.0;jointBridge;1.1.0`
- `APP_ID = 250528`。

### 4.2 链路（share/verify → xpan/share list → share/transfer → locatedownload）

**(1) 验证提取码**
- `POST https://pan.baidu.com/share/verify?surl=<surl>`（surl 已去掉开头 `1`）
- 头：`Cookie`、`User-Agent: UA_WEB`、`Referer: https://pan.baidu.com/s/<surl>`、`Content-Type: application/x-www-form-urlencoded`
- body：`pwd=<urlEncode(pwd)>&vcode_str=&vcode=`
- 成功 `errno==0`；返回 `randsk`（URL 编码形式），**直接作为后续 sekey 使用**，同时它也是要补进 Cookie 的 `BDCLND=<randsk>`。

**(2) 列出分享文件**
- `GET https://pan.baidu.com/rest/2.0/xpan/share?method=list&shorturl=<surl>&page=1&num=100&root=<1|0>&dir=<urlEnc("/"或"/子目录")>[&sekey=<randsk>]`
  - 根目录 `root=1`；进入子目录 `root=0`。
  - 有 sekey 才拼 `&sekey=`；公共分享（无码）省略。
  - **子目录（root=0）必须在 Cookie 里补 `BDCLND=<sekey>`**，否则 errno=2。
- 头：`Cookie`(可能补了 BDCLND)、`UA_WEB`、`Referer: https://pan.baidu.com/s/<surl>`。
- 成功 `errno==0`。响应字段树：
  ```
  title     (string)
  share_id  (string, 转存要用)
  uk        (string, 转存要用)
  list[]:
    isdir           (string, "1"=目录)
    fs_id           (string, 文件用；目录用 path 作 fid)
    path            (string, 目录导航用)
    server_filename (string, 文件名)
    size            (number)
    server_mtime    (string)
  ```
- errno 语义：`0` 成功；`-12` 提取码错误；`-6` 未登录/身份验证失败；`403` 分享失效；`31066` 文件不存在。无 sekey 却 errno≠0 → 提示「该分享需要提取码」。

**(3) bdstoken（转存/建目录前必须拿）**
- `GET https://pan.baidu.com/api/gettemplatevariable?clienttype=0&app_id=250528&web=1&fields=<urlEncode('["bdstoken"]')>`
- 头：`Cookie`、`UA_WEB`。响应 `errno==0`，取 `result.bdstoken`。

**(4) 转存**
- `POST https://pan.baidu.com/share/transfer?shareid=<share_id>&from=<uk>&channel=chunlei&sekey=<randsk>&ondup=newcopy&web=1&app_id=250528&bdstoken=<bdstoken>&clienttype=0`
- body（form）：`fsidlist=%5B%22<fsId>%22%5D&path=<urlEncode(目标目录)>`
- Cookie 必须补 `BDCLND=<sekey>`；头：`UA_WEB`、`Origin: https://pan.baidu.com`、`Referer: https://pan.baidu.com/s/`、form content-type。
- 成功 `errno==0`。响应：
  ```
  extra.list[0]:
    to_fs_id  (转存后新 fs_id)
    to        (转存后新完整路径, locatedownload 要用)
  ```

**(5) 获取高速直链（locatedownload，取链核心）**
- `POST https://d.pcs.baidu.com/rest/2.0/pcs/file?method=locatedownload&app_id=250528&clienttype=17&ver=4.0&ant=1&check_blue=1&es=1&esl=1&apn_id=1_-1&freeisp=0&queryfree=0&use=1&dtype=1&eck=1&ehps=1&err_ver=1.0&network_type=WIFI&channel=0&path=<urlEnc(转存后完整路径)>&time=<unix秒>&rand=5ed606e9da222cde0474cdf70eda884b&devuid=0F1E9FC2E084472DA5A61C4CF4C759AF&cuid=0F1E9FC2E084472DA5A61C4CF4C759AF&deviceid=348642637967375013&psign=860a071f77c860e8cea06e4e54c518f3&version=2.2.111.34&version_app=12.24.6&vip=0`
- body：固定字符串 `0`；头：`Cookie(带BDUSS)`、`User-Agent: UA_NETDISK`、`Content-Type: application/x-www-form-urlencoded`。
- 成功 `errno==0`。响应 `urls[]` 候选直链（自带 sign/expires，无需自己算）：
  ```
  urls[]:
    url      (string, CDN 直链)
    encrypt  (int, 1=需 AES-CTR 解密的加密通道; 0=明文)
  ```
- **选链策略**：优先 `encrypt==0` 的 https 直链（appallNN.baidupcs.com，可直接 Range 下载）；**排除 rank1 的 d2-ant.baidu.com（encrypt=1，需 AES-CTR 解密且部分网络 TLS 握手失败）**；都加密才退回第一个 https，再不行第一个。
- 备选取链（个人盘已知 fs_id 时）：`GET https://pan.baidu.com/api/filemetas?dlink=1&fsids=<urlEncode(["<fsId>"])>&bdstoken=<token>&clienttype=0&app_id=250528&web=1` → `info[0].dlink`（文件删除即失效）。

### 4.3 特殊头 / 加密
- 直链无需额外加密；locatedownload 的 `psign`、`rand`、`devuid`、`cuid`、`deviceid` 均为**写死抓包常量**（见上），`time` 为当前 unix 秒。
- 失败信息取 `err_msg` ＞ `show_msg`，拼上 `（errno=xxx）`。

---

## 5. 123 云盘 PAN123（`Pan123Api.kt` / `Pan123Constants.kt`）

> ⚠️ **重要事实校正（与 iOS 契约 §7 不一致）**：本 Android 工程里，123 云盘**没有**账号密码→JWT 的请求链。它的登录方式是 WebView 打开 `https://yun.123pan.cn/`，用户登录后从浏览器 `localStorage` 读键 `authorToken`，值即 Bearer JWT（约 90 天过期，无 refresh 接口）。iOS 侧应照此实现：用 WKWebView 登录后通过 `WKWebView evaluateJavaScript` 取 `localStorage.getItem('authorToken')`，而不是写账号密码表单。契约里「123 用账号密码表单换 token / Pan123Auth」属于与源码不符的旧设想，以本节为准。

### 5.1 常量
- 业务 base：`API_BASE = https://yun.123pan.cn`；分享下载信息 base：`DOWNLOAD_BASE = https://www.123865.com`。
- UA：`WEB_UA = Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/127.0.0.0 Safari/537.36`；匿名分享列表用 `DART_UA = Dart/3.12 (dart:io)`。
- 设备头 `loginuuid`：32 位十六进随机串，**同一客户端固定、不参与签名**（可生成一次持久化）。
- 下载真实 CDN 直链时必带 `Referer: https://yun.123pan.cn/`。

### 5.2 签名算法（auth-key / auth-value，必须逐字还原）
签名内部固定 `OS=web`、`VER=3`（与请求头 platform/app-version 无关）。
- 数字替换表（索引=数字值 0..9）：`SIGN_TABLE = "adefghlmyijnopkqrstubcvwsz"`
- `ts` = 当前 unix **秒**。
1. **auth-key**：
   - `t = ts + 57600`（即 +16 小时），按 **UTC** 格式化为 `YYYYMMDDHHmm`（精确到分钟）。
   - 把这串数字的每一位字符，用替换表映射：字符 `'0'`→表[0]，`'1'`→表[1]……得到 `substituted`。
   - `auth_key = crc32_hex(substituted)`（标准 CRC-32/IEEE，输出 8 位小写十六进制，等价 Python `zlib.crc32 & 0xFFFFFFFF` 的 `%08x`）。
2. **auth-value**：
   - `random = 0..9999999` 随机整数。
   - `data = "<ts>|<random>|<path>|web|3|<auth_key>"`（path 见下）。
   - `auth_value = "<ts>-<random>-" + crc32_hex(data)`。
- **path** = URL 路径，**含 `/b` 前缀、不含 host、不含 query**，例如 `/b/api/share/download/info`、`/api/file/download_info`（个人盘 download_info 无 `/b`，签名 path 也照实写无 `/b`）。

鉴权请求统一头：
```
platform: web                      (分享下载信息用 android)
app-version: 3                     (分享下载信息用 39)
authorization: Bearer <authorToken>
loginuuid: <32hex>
auth-key: <auth_key>
auth-value: <auth_value>
User-Agent: WEB_UA                 (匿名分享列表用 DART_UA)
```

### 5.3 端点与字段树

**(1) 分享文件列表（匿名、无需登录、无需签名）**
- `GET https://yun.123pan.cn/b/api/share/get?limit=100&next=<游标, 首页"0">&orderBy=file_name&orderDirection=asc&shareKey=<urlEnc(ShareKey)>&ParentFileId=<父FileId>&Page=1[&SharePwd=<urlEnc(提取码)>]`
- 头：仅 `User-Agent: DART_UA`。
- **无提取码时不要拼 `SharePwd`**（传空会 400）。
- 成功 `code==0`。响应：
  ```
  data:
    Expired  (bool, true=分享已失效)
    Next     (string, "-1"=末页; 空串或数字=下一页游标)
    InfoList[]:
      FileId       (string, 即文件 fid)
      FileName     (string)
      Size         (number)
      Type         (int, 1=目录)
      ParentFileId (string)
      S3KeyFlag    (string)
      Etag         (string)
      StorageNode  (string)
      UpdateAt     (string)
  ```
  - 移植时把 `S3KeyFlag|Etag|StorageNode` 用 `|` 拼成一个串暂存（对应 Kotlin 的 `fidToken`），取直链时再拆。

**(2) 分享下载直链信息（需登录 + 签名，android 平台头）**
- `POST https://www.123865.com/b/api/share/download/info`
- 签名 path = `/b/api/share/download/info`；请求头 `platform=android`、`app-version=39`。
- body：`{"ShareKey":"<shareKey>","FileID":"<fileId>","S3KeyFlag":"<拆出的s3>","Size":<size>,"Etag":"<拆出的etag>"}`
- 成功 `code==0` → `data.DownloadURL`。

**(3) 个人盘下载直链（需登录 + 签名，web 平台头）**
- `POST https://yun.123pan.cn/api/file/download_info`（**注意无 `/b/`**）
- 签名 path = `/api/file/download_info`。
- body：`{"driveId":0,"etag":"<etag>","fileId":<fileId 数字>,"s3keyFlag":"<s3>","type":0,"fileName":"<名>","size":<size>}`
- 成功 `code==0` → `data.DownloadUrl`。

**(4) 用户信息（校验 token / 取昵称 / 容量）**
- `GET https://yun.123pan.cn/b/api/user/info`（带签名头）→ `data.Nickname`、`data.SpaceUsed`、`data.SpacePermanent`、`data.SpaceTemp`。

### 5.4 直链 URL 解码与跳转（关键，别漏）
拿到的 `DownloadURL/DownloadUrl` 通常不是可直接下载的 CDN 地址：
1. **解码**：
   - 若整串不含 `://`：直接 Base64 解码整串，结果应以 `http` 开头。
   - 若是 `...download-v2?params=<base64url>`：取 `params=` 后、`&` 前那段，把 `-`→`+`、`_`→`/` 做 Base64 解码。
2. **跟随跳转**：对解码后的 URL 发 GET（带 `Referer: https://yun.123pan.cn/` + `DART_UA`）：
   - 若响应 `Content-Length ≤ 8192` 且 body 以 `{` 开头，说明是跳转 JSON：读 `data.redirect_url`，循环跟随，**最多 5 跳**。
   - 响应较大/不是 JSON → 当前 URL 即最终可下载直链。
   - 下载最终直链时同样带 `Referer: https://yun.123pan.cn/`。

成功判定统一 `code==0`，否则抛 `message（code=xxx）`。

---

## 6. 迅雷 XUNLEI（`XunleiApi.kt` / `XunleiConstants.kt`）

### 6.1 认证
- 两个主机：`AUTH_BASE = https://xluser-ssl.xunlei.com`（登录/验证码/token）；`PAN_BASE = https://api-pan.xunlei.com`（文件/分享/下载）。
- App 凭据：`CLIENT_ID = Xp6vsxz_7IYVw2BB`、`CLIENT_SECRET = Xp6vsy4tN9toTVdMSpomVdXpRmES`。
- 登录是 OAuth2 换 token 链（access_token 约 12h，refresh_token 续期）。
- pan 请求用 `Authorization: Bearer <access_token>`。**游客模式（无 token）时整个 Authorization 头都不要发**——发一个失效的 `Bearer ` 反而会被判 unauthenticated。

### 6.2 登录请求链（账号密码）
顺序：`captcha/init → v3/login(密码) → 多数首登返回 review_panel(1007) → sendsms → smslogin → v1/auth/signin/token`。

1. **captcha/init**：`POST https://xluser-ssl.xunlei.com/v1/shield/captcha/init`
   - 头：`User-Agent: APP_UA`、`X-Client-Id: <CLIENT_ID>`、`X-Device-Id: <deviceId>`、`X-Client-Version: 8.31.0.9726`、`Content-Type: application/json`
   - body 含 `action`（如 `POST:/auth/signin/token`）、`client_id`、`device_id`、`redirect_uri=xlaccsdk01://xunlei.com/callback?state=harbor`、`meta`（含 `username`/`client_version=8.31.0.9726`/`package_name=com.xunlei.downloadprovider`/`timestamp=<ms>`/`captcha_sign=<见6.4>`/`user_id`）。
   - 返回 `captcha_token`（后续换 token / pan 请求要带 `X-Captcha-Token`）。
2. **密码登录**：`POST https://xluser-ssl.xunlei.com/xluser.core.login/v3/login`
   - UA：`android-ok-http-client/xl-acc-sdk/version-5.1.3.513006`，无 Cookie、无 x-device-id。
   - body：基础字段（protocolVersion=301、appid=40、appName=ANDROID-com.xunlei.downloadprovider、peerID、devicesign、netWorkType=WIFI、deviceModel=M2004J7AC、OSVersion=12、hl=zh-CN 等）+ `userName`、`passWord`（**明文**）、`isMd5Pwd:"0"`、`verifyKey:""`、`verifyCode:""`。
   - 响应：`errorCode=="0"` 或 `error=="success"` → 成功，取 `sessionID`（换 token 用）、`loginKey`、`nickName`、`userID`。否则若 `error=="review_panel"` 或 `errorCode=="1007"` → 需要短信验证。
3. **sendsms**：`POST .../v3/sendsms`（UA xl-acc-sdk/5.0.12.512000），body 加 `mobile`、`register:"0"`；返回 `creditkey`、`token`。
4. **smslogin**：`POST .../v3/smslogin`，body 加 `mobile`、`smsCode`、`token`、`creditkey`、`register:"0"` → 同密码登录响应，取 `sessionID`。
5. **换 access_token**：`POST https://xluser-ssl.xunlei.com/v1/auth/signin/token`
   - body：`{"client_id":"<CLIENT_ID>","client_secret":"<CLIENT_SECRET>","provider":"access_end_point_token","signin_token":"<sessionID>"}`
   - 头：`User-Agent: APP_UA`、`X-Client-Id`、`X-Device-Id`、`X-Client-Version`、`X-Captcha-Token`。
   - 返回 `access_token`、`refresh_token`（字段名 access_token/accessToken 兼容）。
6. **刷新**：`POST https://xluser-ssl.xunlei.com/v1/auth/token`，form：`grant_type=refresh_token&client_id=...&client_secret=...&refresh_token=<urlEnc>`。

> iOS 若不实现账号密码登录，至少要支持「用户从别处拿到 access_token/refresh_token 填入」；分享解析本身支持游客匿名（见下）。

### 6.3 Pan 接口
pan 请求统一头：`User-Agent: WEB_UA`（`Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36`）、`X-Device-Id`、`X-Client-Version: 8.31.0.9726`、`Content-Type: application/json`、`Origin: https://pan.xunlei.com`、`Referer: https://pan.xunlei.com/`，登录态加 `Authorization: Bearer`，有则加 `X-Captcha-Token`。**抓包确认无 x-signature 签名**。

- **分享解析**：`GET https://api-pan.xunlei.com/drive/v1/share?share_id=<id>&pass_code=<urlEnc>&limit=100&page_token=<>&thumbnail_size=SIZE_SMALL`
  - `data.share_status` 判定：`PASS_CODE_EMPTY`/`PASS_CODE_ERROR`/`PASS_CODE_NEED` → 对应「请输入/错误/需要提取码」（此时 files 为空数组但 HTTP 200，别误判空目录）。
  - 响应：
    ```
    data:
      title
      pass_code_token   (子目录/转存要用)
      next_page_token
      files[]:
        id            (string)
        name          (string)
        size          (number)
        kind          (string, "drive#folder"=目录)
        parent_id     (string)
        modified_time (string)
    ```
- **分享子目录**：`GET /drive/v1/share/detail?share_id=&parent_id=&pass_code_token=&limit=100&page_token=&thumbnail_size=SIZE_SMALL`，files 结构同上。
- **转存**：`POST /drive/v1/share/restore`，body `{"share_id":..,"pass_code_token":..,"parent_id":目标目录,"ancestor_ids":[],"file_ids":[...],"specify_parent_id":true}` → `params.trace_file_ids` 是 JSON 字符串 `{"分享id":"转存后新id"}`。
- **取直链（文件详情）**：`GET /drive/v1/files/<fileId>?_magic=2021&usage=PLAY&thumbnail_size=SIZE_LARGE&with=hdr10&with=subtitle_files&with=task&with=public_share_tag`
  - 响应 `data.links["application/octet-stream"].url`（兜底 `data.web_content_link`）即为下载直链；同时有 `id`、`name`、`size`。
  - 分享文件需先 restore 到个人盘再调本接口取直链。
- 失败处理：HTTP 401 或 `error=="unauthenticated"` → 用 refresh_token 换新 token 并重新 init captcha 后重试一次；`error=="captcha_invalid"` → 重新 init captcha 后重试一次。

### 6.4 加密 / 签名（captcha_sign 与设备指纹）
- **captcha_sign**：
  - `raw = CLIENT_ID + "8.31.0.9726" + "com.xunlei.downloadprovider" + deviceId + timestamp_ms`
  - 对 10 个盐依次做 `h = md5_hex(h + salt)`（链式，初值 raw）。盐表见 `XunleiConstants.CAPTCHA_SALTS`（10 个字符串，原样抄）。
  - `sign = "1." + h`。
- **devicesign（登录 body 用）**：`div101.<deviceId><md5_hex(sha1_hex(deviceId + "com.xunlei.downloadprovider" + "40" + "34a062aaa22f906fca4fefe9fb3a3021"))>`。deviceId 为 32 位十六进随机串，生成后持久化复用。
- 这两套都是开源实现为避免所有用户共用官方指纹被风控而做；iOS 可自生成 deviceId/peerId 并本地持久化。

---

## 7. 下载引擎规格（`download/` 包）

> iOS 契约 §5 给的是**简化目标**（每任务 min(4, size/8MB) 片）。本节是 Android 真实算法，移植时可按契约简化，但下列「行为正确性」要点必须保留，否则会损坏文件。

### 7.1 取总大小（`ChunkDownloader.getTotalSize`）
- 先发 `Range: bytes=0-0` 的探测请求：
  - 响应必须是 **206**，且 `Content-Range` 形如 `bytes 0-0/<total>`，解析出 total。
  - 若 Content-Type 含 `text/html`（防盗链/错误页）→ 视为取不到大小。
- 探测失败再退回不带 Range、读 `Content-Length`。
- 总大小未知 → 走流式降级（开放区间 `bytes=from-`，读到 EOF）。

### 7.2 分片策略（`DownloadManager.chunkCountFor`）
- 基础片数按大小分档：
  - `< 5MB` → 1 片（不分片）
  - `< 50MB` → 8
  - `< 500MB` → 32
  - `≥ 500MB` → 64
- 任务池模型：`want = max(分档值, 线程数×8)`，再夹到 `total/256KB` 与 **512** 上限。单片下限 256KB。
- 分片 = 前 70%（`mainPoolCount = chunkCount*0.7`）等分固定块（`part_$i`）；后 30% 为弹性区（`seg_<start>_<end>.part`），由空闲 worker 按实时速度动态领取，块大小夹在 [256KB, 4MB]、尾部收缩到约 64KB。
- **并发上限**：全进程在飞分片数 `MAX_INFLIGHT_CHUNKS = clamp(maxHeap/8/64KB, 8, 512)`（iOS 可直接定一个 16~64 的常量）。**迅雷单文件并发 Range 封顶 8 路**（`RANGE_WORKERS_CAP=8`），超过会被 CDN 降级成 200 整文件。

### 7.3 Range 头构造
- 普通分片：`Range: bytes=<start>-<end>`（闭区间，含两端）。
- 断点续传：`from = start + 本地 part 文件已有字节数`；请求头 `bytes=<from>-<end>`。
- 开放区间（流式）：`bytes=<from>-`。
- 校验：206 响应必须核对 `Content-Range` 的 start==请求 from、end==请求 end，否则判失败。`Content-Range` 解析正则（原样）：`bytes\s+(\d+)-(\d+)/(\d+|\*)`。
- **Range 被忽略（返回 200 整文件）时绝不为单分片下整文件**；累计 3 次（`RANGE_IGNORED_TOLERANCE=3`）后整任务回退单流整文件下载到独立文件 `full_single.bin`（从 0 开始，不复用旧分片）。

### 7.4 断点续传记录与恢复
- 每个任务一个分片目录（Android：`cache/download_tmp/<taskId>/`）；iOS 对应 `Documents/Downloads/<uuid>/`。
- 分片文件：主池 `part_$i`、弹性 `seg_<start>_<end>.part`、计划签名 `plan.txt`（内容 `chunks=<n> total=<总> main=<主池片数>`）。
- **恢复时**：读 `plan.txt`，若签名（chunks/total/main）与本次不一致 → 整个分片目录清空重下（否则区间错位会导致文件膨胀/损坏）。
- 一致时：每个分片用 `seek(已有长度)` 续写；暂停后回写进度以**磁盘上分片真实字节总和**为准（不信 DB 旧值）。
- 弹性区只续传「按字节连续的已完成前缀」，不完整的 seg 删除重下。

### 7.5 重试策略
- 单片 IO 瞬时失败：指数退避 `delay = min(500ms×(attempt+1), 3000ms)`，最多 3 次（`CHUNK_RETRIES=3`）。
- 任务级失败自动重试：默认 3 次（可配，上限 10），间隔 `1200ms×第几次`，part 文件保留、断点续传。
- 看门狗「慢连接抢占」：某路瞬时速度 < max(12KB/s, 本任务平均单路/2) 且跑够 15s、剩余 >128KB → 断开该连接换一条新连接从已收字节续传（已收字节保留，不退避）。收尾阶段放宽门槛。每路最多抢 3 次、每轮最多抢 2 路（iOS 可省略此优化，但分片+并发必须有）。

### 7.6 完成拼接方式
- 顺序：`part_0 … part_{mainPool-1}`（前半连续）+ 所有 `seg_*.part` 按 start 升序（后半）。
- **流式边合并边写最终文件、边删分片**（峰值占用 ≈ 文件大小 + 一个分片，不再做第二份合并副本）。
- 落盘前完整性校验：每个分片非空 + 实际写入总字节 == total；任一不符即中止、不保存损坏文件。合并中途失败/取消要删除半成品。
- 单流回退时输出 `full_single.bin`，校验写入 == total。

### 7.7 文件命名 / 路径
- 文件名来自 API 返回（夸克 `file_name`、百度 `server_filename`、123 `FileName`、迅雷 `name`）；空名兜底从 URL 路径末段取，再兜底 `download_<时间戳>`。
- 同名时在扩展名前加时间戳防重（`base_<yyyyMMddHHmmss>.ext`），**绝不预删用户已有文件**。
- 下载请求头必须带上取直链时记录的 `User-Agent`、`Referer`、必要的 `Cookie`（夸克直链要 Referer + 可能的 `__pugs`；123 直链要 `Referer: https://yun.123pan.cn/`）。
- 网络读缓冲 64KB；全局限速为令牌桶（0=不限）。

---

## 8. Kotlin → Swift 移植易踩坑点

1. **URL 编码**：Kotlin 用 `URLEncoder.encode(s,"UTF-8")`，其行为是 `application/x-www-form-urlencoded`（空格编成 `+`）。Swift `URLQueryItem`/`URLComponents` 会把空格编成 `%20`。拼 query 时统一用 `URLComponents`，并注意百度 `dir=/`、`fsidlist=["x"]` 这类需手动 percent-encode 的串（`CharacterSet.urlQueryAllowed` 要放宽松，保留 `[` `]` 等的编码）。
2. **Cookie 处理**：
   - 夸克/百度是整串 Cookie 手动塞 `Cookie` 头（**不要**让 URLSession 自动管理，否则各域名 Cookie 混在一起）。
   - 百度子目录/转存要**手动往 Cookie 串追加 `; BDCLND=<sekey>`**；123 用 Bearer token 不用 Cookie；迅雷用 Bearer + 游客模式完全不带 Authorization。
   - 夸克要处理响应 `Set-Cookie`，把 `__puus`/`__pus`/`__pugs` 合并回本地串。
3. **响应编码 charset**：OkHttp 默认按响应头 charset（多为 UTF-8）解码。Swift `URLSession.dataTask` 拿到的是 `Data`，需自己 `String(data:encoding:.utf8)`；遇到非 UTF-8（少见）不要硬解。
4. **时间戳精度**：所有 `time`/`timestamp` 字段（百度 locatedownload 的 `time`、123 签名的 `ts`、迅雷 captcha 的 `timestamp`）都是**秒级 unix**（123/百度）或**毫秒级**（迅雷 `timestamp_ms`）。别混用：123/百度用秒，迅雷 captcha_sign 与 meta.timestamp 用毫秒。
5. **JSON 解析差异**：
   - Kotlin `JSONObject.optXxx` 对缺失/类型错很宽容。Swift `JSONDecoder` 严格，建议用可选字段 `decodeIfPresent`，并对字段名大小写敏感：123 大量 PascalCase（`FileId/FileName/S3KeyFlag/Etag/StorageNode/InfoList/DownloadURL/ShareKey`），夸克/百度是 snake_case/camelCase 混用，**不要**统一加 `convertFromSnakeCase`。
   - 夸克成功判定是 `status==200 || code==0`；百度是 `errno==0`；123 是 `code==0`；迅雷是顶层无 errno、看 `error` 字段。**四平台成功码标准不同，别做统一拦截器**。
   - 数字可能是字符串（百度 `isdir` 是 `"1"` 字符串；fsid 多为字符串），解码时按字符串/数字双兼容。
6. **CRC32 / MD5 / SHA1 / Base64**：123 签名用标准 CRC-32（IEEE），Swift 无内置，需自己实现或用 `zlib` 的 `crc32`（`import zlib`）；MD5/SHA1 用 `CryptoKit` 没有（CryptoKit 无 MD5），需 CommonCrypto。Base64：123 的 `params=` 是 **Base64URL**（`-`/`_`），解码前要换回 `+`/`/`。
7. **正则**：Kotlin `Regex` 与 Swift `NSRegularExpression`/`Regex` 语法基本兼容（本文所有正则可直接用），但注意 IGNORE_CASE 要显式开；Swift 原生 `Regex` 语法略不同，建议用 `NSRegularExpression` 以确保分组行为一致。
8. **HttpClients 用系统证书链**：iOS 同理走 ATS 默认，不要关校验；若直链是 http（少数）需在 Info.plist 配 ATS 例外。
9. **断点续传文件句柄**：Kotlin 用 `RandomAccessFile.seek`；iOS 用 `FileHandle.seek(toOffset:)`，注意写完 `synchronize()` 再关，避免进度记录与磁盘不一致。
10. **错误透传**：各平台服务端 message/err_msg/errorDesc 要原样作为中文 `errorMessage` 展示（对应契约 `YxiOSError`）。

---

## 9. 与 iOS API-CONTRACT 的对应核对

| 契约要求 | 本文档依据 |
|---|---|
| `ShareLinkParser.parse` 识别四平台 | §1.1~§1.4 正则 |
| `PlatformClient.requiresLogin` | 夸克大文件需登录（游客仅~50MB，§3.3）；百度必须 BDUSS（§4）；123 取下载信息需 JWT（§5.3）；迅雷分享可游客匿名、取直链建议登录（§6.3） |
| `resolveShare/listChildren` | 夸克 §3.3(2)、百度 §4.2(2)、123 §5.3(1)、迅雷 §6.3 |
| `getDirectURL` | 夸克 §3.3(3)、百度 §4.2(5)、123 §5.3(2)/(3)+§5.4、迅雷 §6.3 文件详情 |
| `PlatformAuth.cookie`（夸克/百度） | §3.1 / §4.1 |
| `PlatformAuth.token`（123 JWT / 迅雷） | §5.1（authorToken）/ §6.2（access_token） |
| 登录态来源（WebView 抓 Cookie / localStorage） | 夸克/百度 §3.1/§4.1；123 §5.1（**不是账号密码表单**）；迅雷账号密码链 §6.2 |
| 下载引擎 | §7（契约 §5 为简化版，保留正确性要点即可） |
