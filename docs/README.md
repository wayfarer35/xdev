预构建 PHP 镜像（启用按需扩展）

目的

这个目录的 Dockerfile 会在构建时预安装大量常用 PHP 扩展，并将每个扩展对应的 ini 文件收集到 /opt/php-extensions-available 中。容器启动时可以通过环境变量按需启用扩展，而不需要在构建时指定要安装的扩展。

如何使用

- 构建镜像（示例）:

  docker build -t webdock:php-8.4-fpm-bookworm .

- 运行容器并启用特定扩展：

  docker run --rm -e ENABLE_EXTENSIONS=redis,gd,imagick webdock:php-8.4-fpm-bookworm php -m

  将输出包含启用的扩展列表。

- 启用全部扩展：

  docker run --rm -e ENABLE_EXTENSIONS=all webdock:php-8.4-fpm-bookworm php -m

实现细节

- 构建阶段会把 /usr/local/etc/php/conf.d/*.ini 拷贝到 /opt/php-extensions-available/<ext>.ini，并清理原有 conf.d，容器启动时通过 /usr/local/bin/docker-entrypoint.sh 创建 conf.d 下的符号链接来启用扩展。

限制与注意事项

- 并非所有扩展都能同时启用，某些扩展可能存在相互冲突或对特定 PHP 版本/系统无效。如果启用失败，entrypoint 会输出警告。
- 本方案并不会在运行时安装扩展，只能管理在镜像中已安装的扩展的启用/禁用状态。

后续改进建议

- 提供一个可挂载的配置文件（例如 /etc/php/extension-enable.conf）以便在容器启动时更灵活地管理扩展。
- 提供 web 界面或 CLI 脚本在容器内部列出/切换扩展状态。
## 生成的扩展数据与构建建议

- 现在统一使用单一的合并原始数据文件：`images/php/extensions/all-extensions.raw`。
- 格式说明：每行一条扩展记录，形如 `ext v1 v2 ... [| blocked=os1,os2]`。注释行以 `#` 开头。
- `blocked=` 字段来自 `install-php-extensions.md` 中的特殊需求，用于标注在某些发行版/系统上不应安装该扩展。

生成与刷新流程

- 生成脚本：`images/php/scripts/generate-extension-raw.sh`。
  - 优先使用本地 `images/php/scripts/supported-extensions.raw` 和仓库根目录的 `install-php-extensions.md`。
  - 若本地文件缺失，脚本会尝试从远程下载到 `images/php/scripts/cache/` 并使用缓存。
  - 常用选项：
    - `--supported-url <URL>` 覆盖 supported-extensions 源
    - `--md-url <URL>` 覆盖 md 文件源
    - `--force-download` 强制刷新下载并覆盖缓存
    - `--out <FILE>` 指定输出路径（默认 `images/php/extensions/all-extensions.raw`）

示例：使用本地文件生成（推荐在 CI/本地运行以保持数据一致）

```bash
images/php/scripts/generate-extension-raw.sh --out images/php/extensions/all-extensions.raw
```

构建时使用 raw

- `images/php/build.sh` 已改为基于 `images/php/extensions/all-extensions.raw` 来决定当前 `PHP_VERSION` + `OS` 下应安装的扩展（除非使用 `--no-list`）。
- 优先级：命令行 `--extensions` / `--extensions-file` > raw 自动选择。

示例：使用生成的 raw 构建镜像（会从 raw 自动选择适合的扩展）

```bash
build.sh -v 8.4 -m fpm -o bookworm
```

如果希望强制仅使用自定义扩展列表：

```bash
build.sh -v 8.4 -m fpm -o bookworm --extensions-file ./my-extensions.list
```

注意与建议

- 如果 `install-php-extensions.md` 不可用或下载失败，生成脚本会警告并忽略 special requirements —— 这可能会导致构建时选入在某些 OS 不被支持的扩展。
- 推荐在 CI 中运行 `generate-extension-raw.sh --force-download` 或将生成的 `all-extensions.raw` 纳入版本控制以保证可重复性。
