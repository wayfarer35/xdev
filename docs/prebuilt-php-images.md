# 预构建 PHP 镜像（按需启用扩展）

## 目的

本文件说明如何使用仓库中提供的脚本与配置来构建预装大量常用 PHP 扩展的镜像，并在容器运行时按需启用这些扩展。目标是把“安装/编译扩展”这一耗时且易出错的工作从日常开发流程中抽离出来，提高本地与 CI 的复现性。

## 目录与关键文件

- `images/php/build.sh`：构建 PHP 镜像的主脚本。
- `images/php/scripts/generate-extension-raw.sh`：生成合并后的 `all-extensions.raw` 数据源。
- `images/php/extensions/all-extensions.raw`：自动选择扩展的主数据源（由上面的脚本生成或手动维护）。
- `images/php/extensions/default-not-install.conf`：默认不安装的扩展列表（除非用 `--include` 强制包含）。
- `images/php/extensions/conflicts.conf`：冲突规则，格式 `preferred:conflict1 conflict2`，用于偏好保留某个扩展并移除冲突项。
- `images/php/extensions/` 下其它辅助文件：例如 `supported-extensions.raw`、`special-requirements.raw`（供生成脚本使用）。

## 参数参考表

| 参数 | 描述 |
|------|------|
| `-v <php_version>` | 指定 PHP 版本（脚本内有完整支持列表，例如 `8.4`, `8.5` 等）。 |
| `-m <mode>` | 模式，常用 `fpm` 或 `cli`。 |
| `-o <os>` | 目标操作系统/变体（例如 `bullseye`、`bookworm`、`alpine`），可用值受所选 PHP 版本限制。 |
| `--extensions="a b c"` | 显式指定要安装的扩展（覆盖自动选择）。支持空格或逗号分隔。 |
| `--exclude="a b c"` | 从自动选择的列表中排除指定扩展。 |
| `--include="a b c"` | 即使在 `default-not-install` 列表中，也强制将这些扩展包含进来。 |
| `-d, --dry-run` | 打印将要执行的 `docker build` 命令与已选扩展，不实际构建。 |
| `--fail-on-generate` | 当 `all-extensions.raw` 需要自动生成但生成失败时，脚本会以错误退出（适用于 CI 场景）。 |

## `build.sh`（构建 PHP 镜像）

位置：`images/php/build.sh`

基本用法：

```bash
cd images/php
./build.sh -v <php_version> -m <mode> -o <os> [options]
```

必需参数：
- `-v <php_version>`：指定 PHP 版本（脚本内有完整支持列表，例如 `8.4`, `8.5` 等）。
- `-m <mode>`：模式，常用 `fpm` 或 `cli`。
- `-o <os>`：目标操作系统/变体（例如 `bullseye`、`bookworm`、`alpine`），可用值受所选 PHP 版本限制。

重要选项：
- `--extensions="a b c"`：显式指定要安装的扩展（覆盖自动选择）。支持空格或逗号分隔。
- `--exclude="a b c"`：从自动选择的列表中排除指定扩展。
- `--include="a b c"`：即使在 `default-not-install` 列表中，也强制将这些扩展包含进来。
- `-d, --dry-run`：打印将要执行的 `docker build` 命令与已选扩展，不实际构建。
- `--fail-on-generate`：当 `all-extensions.raw` 需要自动生成但生成失败时，脚本会以错误退出（适用于 CI 场景）。

示例：

```bash
# 构建默认扩展集合
./build.sh -v 8.4 -m fpm -o bookworm

# 只安装特定扩展
./build.sh -v 8.4 -m fpm -o bullseye --extensions="pdo_mysql redis"

# 从默认选择中排除扩展
./build.sh -v 8.4 -m fpm -o bullseye --exclude="xdebug xhprof"

# 预览将运行的构建命令
./build.sh -v 8.4 -m fpm -o bullseye --dry-run
```

实现要点：
- 若 `images/php/extensions/all-extensions.raw` 不存在，`build.sh` 会尝试调用目录下的 `generate-extension-raw.sh` 来生成该文件（可由 `--fail-on-generate` 控制失败行为）。
- 自动选择逻辑会根据 `all-extensions.raw` 中每行指定的支持版本筛选扩展，同时会应用 `blocked=` 规则来排除在特定 OS/版本上不支持的扩展。
- 脚本会读取 `default-not-install.conf` 并在默认情况下排除这些扩展，除非通过 `--include` 恢复。
- 构建前会读取 `conflicts.conf` 并按优先规则去除冲突扩展。

## `generate-extension-raw.sh`（生成合并 raw 数据）

位置：`images/php/scripts/generate-extension-raw.sh`

作用：合并 `supported-extensions` 与 `special-requirements`（优先使用仓库内的本地文件，若缺失则尝试从 `mlocati/docker-php-extension-installer` 仓库下载），输出文件为 `images/php/extensions/all-extensions.raw`。

常用选项：
- `--force-download`：强制从远程刷新源文件并覆盖缓存。

注意事项：
- 若无法获取 `special-requirements`，脚本会输出警告并继续，但这可能导致某些发行版不兼容的扩展未被正确标记为 `blocked=`，从而进入自动选择列表。

## 运行时：按需启用扩展

- 镜像构建时会把各扩展对应的 `*.ini` 拷贝到 `/opt/php-extensions-available/`，并清空默认 `conf.d`。镜像入口脚本（entrypoint）在容器启动时根据环境变量 `ENABLE_EXTENSIONS` 在 `/usr/local/etc/php/conf.d/` 创建到这些 `ini` 的符号链接以启用扩展。
- 支持的用法：
	- `ENABLE_EXTENSIONS=all`：启用镜像里所有可用扩展。
	- `ENABLE_EXTENSIONS=redis,gd,imagick`：按逗号分隔启用指定扩展。





