# DYU-VPNexus

<div align="center">

**大葉大學 FortiVPN Docker 客戶端**

*輕量級、容器化的 FortiVPN 解決方案，提供 SOCKS5 代理功能*

[安裝指南](#安裝) • [使用指南](#使用方法) • [配置說明](#配置說明)

</div>

---

## 目錄

- [簡介](#簡介)
- [功能](#功能)
- [架構說明](#架構說明)
- [安裝](#安裝)
- [使用方法](#使用方法)
- [配置說明](#配置說明)

## 簡介

這是一個基於 [OpenFortiVPN](https://github.com/adrienverge/openfortivpn) 的輕量級 Docker 容器，專為連接大葉大學 VPN 而設計。

## 功能

- 使用 Alpine Linux 作為基礎鏡像，體積小巧
- 集成最新版 OpenFortiVPN 客戶端
- 自動連接大葉大學 VPN 服務器
- 支持網絡轉發
- 提供 SOCKS5 代理服務
- 環境變量配置，無需重新構建鏡像
- 支持 Docker Compose 簡化部署和管理
- 支持自訂代理端口
- 極致的輕量級設計：VPN容器僅 24.4MB，代理容器僅 12.5MB，總計僅 36.9MB

## 架構說明

本項目採用分離式架構，符合容器最佳實踐：

1. **VPN容器**：負責建立和維護VPN連接
2. **PROXY容器**：提供SOCKS5代理服務，共享VPN容器的網絡

## 安裝

### 必要條件

- Docker Engine 20.10+
- Docker Compose v2+
- 有效的大葉大學 VPN 帳戶

### 快速安裝

1. 克隆儲存庫：

```bash
git clone https://github.com/username/dyu-vpnexus.git
cd dyu-vpnexus
```

2. 創建環境變量文件：

```bash
cp .env.example .env
```

3. 啟動服務：

```bash
docker-compose up -d
```

## 使用方法

### 使用 Docker Compose (推薦)

1. 創建 `.env` 文件並設置您的環境變量（參考 `.env.example`）
2. 運行以下命令啟動 VPN 和代理容器：

```bash
# 構建並啟動容器
docker-compose up -d

# 查看容器日誌
docker-compose logs -f
```

### 直接使用 Docker

#### 構建鏡像

```bash
docker build -t dyu-vpnexus .
```

#### 運行容器

使用自定義配置：

```bash
docker run --name dyu-vpn \
  --cap-add=NET_ADMIN \
  --device=/dev/ppp \
  -e VPN_HOST=vpn.dyu.edu.tw \
  -e VPN_PORT=443 \
  -e VPN_USERNAME=你的學號 \
  -e VPN_PASSWORD=你的密碼 \
  -e PROXY_PORT=11451 \
  -p 11451:11451 \
  -it dyu-vpnexus
```

> **注意**：需要 `--cap-add=NET_ADMIN` 和 `--device=/dev/ppp` 權限才能創建 PPP 接口和管理網絡。

### 使用代理服務

啟動容器後，SOCKS5代理會在主機的指定端口（預設 **11451**）提供服務。您可以在各種應用程式中配置此代理：

#### 瀏覽器設置

⚠️ **重要提示**：我們不建議使用系統代理設置，因為某些系統可能無法正確處理SOCKS5代理。請使用瀏覽器插件來設置代理。

##### 推薦方式：使用瀏覽器插件（最可靠）

1. **Chrome/Edge/Firefox**: 
   - 安裝 [SwitchyOmega](https://chrome.google.com/webstore/detail/proxy-switchyomega/padekgcemlokbadohgkifijomclgjgif) 或類似插件
   - 新增代理配置：
     - 代理協議: `SOCKS5`
     - 代理伺服器: `127.0.0.1`
     - 代理端口: `11451`（或您在.env中設定的PROXY_PORT）
   - 啟用該代理配置

2. **Firefox 內建代理**:
   - 設置 → 網絡設置 → 手動配置代理
   - SOCKS主機: `127.0.0.1` 端口: `11451`（或您在.env中設定的PROXY_PORT）
   - 選擇 "SOCKS v5"
   - 勾選 "為所有協議使用此代理服務器"

##### 系統代理設置（不推薦）

某些系統的代理設置可能無法正確處理SOCKS5代理，如果您嘗試使用系統代理但無法連接，請改用瀏覽器插件方式。

#### 終端/命令行

- **Windows (PowerShell)**:
  ```powershell
  $env:all_proxy="socks5://127.0.0.1:11451"
  ```

- **Linux/Mac (Bash)**:
  ```bash
  export ALL_PROXY=socks5://127.0.0.1:11451
  ```

#### 其他應用

大多數支持代理的應用都可以配置SOCKS5代理：
- 地址: `127.0.0.1` 或 `localhost`
- 端口: `11451`（或您在.env中設定的PROXY_PORT）
- 類型: `SOCKS5`

### 驗證連接

VPN 連接成功後，容器將保持運行。您可以通過以下命令驗證 VPN 連接狀態：

```bash
docker exec dyu-vpn ping -c 3 <內網地址>
```

## 網絡模式說明

預設情況下，docker-compose.yml 配置了專用網絡，這意味著：

- 只有容器內的流量會通過 VPN 隧道
- 主機和其他容器流量不受影響
- 可以通過 SOCKS5 代理選擇性使用 VPN 連接

## 配置說明

### 環境變量

您可以通過以下環境變量自定義配置：

| 環境變量 | 默認值 | 說明 |
|----------|--------|------|
| VPN_HOST | vpn.dyu.edu.tw | VPN 伺服器地址 |
| VPN_PORT | 443 | VPN 伺服器端口 |
| VPN_USERNAME | - | VPN 用戶名（學號） |
| VPN_PASSWORD | - | VPN 密碼 |
| TRUSTED_CERT | 1 | 是否信任所有證書 (1=是, 0=否) |
| SET_DNS | 1 | 是否設置 DNS (1=是, 0=否) |
| USE_PEERDNS | 1 | 是否使用對等 DNS (1=是, 0=否) |
| PROXY_PORT | 11451 | SOCKS5 代理端口 |
